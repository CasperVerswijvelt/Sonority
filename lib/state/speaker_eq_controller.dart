import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/custom_eq.dart';
import '../data/sonos/diagnostics_log.dart';
import '../data/sonos/key_value_store.dart';
import '../data/sonos/sonority_error.dart';
import '../data/sonos/trueplay_apply.dart';
import '../data/sonos/trueplay_codec.dart';
import 'shared_preferences_store.dart';
import 'sonos_controller.dart' show sonosRepositoryProvider;
import 'trueplay_controller.dart';

/// Writes spectral tunings to a player's `:1443` API. A provider so demo mode can
/// swap in a client that can't touch the network.
final trueplayApplyProvider =
    Provider<TrueplayApplyClient>((ref) => const TrueplayApplyClient());

/// Durable store for the EQ the user chose. A provider for the same reason.
final eqStoreProvider =
    Provider<KeyValueStore>((ref) => SharedPreferencesKeyValueStore());

/// What a pre-flight found on the target speakers.
enum EqPreflight {
  /// Nothing stored, or the stored tuning is one we wrote. Safe to apply.
  ok,

  /// A tuning exists that Sonority did not author — almost certainly a Trueplay
  /// calibration measured in the Sonos app. Coefficients can never be read back
  /// off a speaker, so applying would destroy it with no way to restore it.
  /// Needs an explicit, informed confirmation.
  wouldOverwrite,

  /// No member reports a tunable channel (e.g. an unbonded Sub, which has no
  /// channel role to author against).
  nothingTunable,
}

@immutable
class SpeakerEqStatus {
  /// Which entity this status is about. The provider is global but the screen is
  /// per-entity, so without this a stale "Applied" or error from one home
  /// theater renders on the next entity's EQ page.
  final String? entityId;
  final bool busy;
  final Object? error;

  /// Set after a successful apply, so the UI can say so without re-reading.
  final bool applied;

  const SpeakerEqStatus({
    this.entityId,
    this.busy = false,
    this.error,
    this.applied = false,
  });

  /// Nothing to show for [id] — either idle, or reporting on another entity.
  bool isIdleFor(String id) => entityId != id;
}

final speakerEqControllerProvider =
    NotifierProvider<SpeakerEqController, SpeakerEqStatus>(
        SpeakerEqController.new);

/// Applies a user-authored EQ to a bonded entity (or a single speaker).
///
/// The write is per player and the whole set goes in one batch, under one shared
/// session id: a satellite only commits if the coordinator is in the same batch,
/// and the coordinator only commits if every member carries a tuning. So members
/// the user left flat still get a passthrough blob — skipping them would silently
/// drop the whole apply.
class SpeakerEqController extends Notifier<SpeakerEqStatus> {
  /// Live-apply scheduling: at most one apply in flight, and at most one queued.
  /// A newer value replaces the queued one rather than joining a backlog, so
  /// dragging a slider can never build up a burst of writes to real speakers.
  Timer? _debounce;
  _EqRequest? _pending;
  bool _inFlight = false;
  DateTime _lastApply = DateTime.fromMillisecondsSinceEpoch(0);

  static const _debounceDelay = Duration(milliseconds: 600);
  static const _minInterval = Duration(milliseconds: 1500);

  @override
  SpeakerEqStatus build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SpeakerEqStatus();
  }

  TrueplayApplyClient get _apply => ref.read(trueplayApplyProvider);
  KeyValueStore get _store => ref.read(eqStoreProvider);

  static String _key(String entityId) => 'eq:$entityId';

  // ---------------------------------------------------------------- storage

  /// The band offsets the user last applied to this entity, by member UUID.
  ///
  /// Inputs are what is stored, never the fitted coefficients: a speaker will
  /// not hand its coefficients back, and a cascade cannot be re-trimmed. This is
  /// also where a room measurement will be referenced once one exists.
  Future<Map<String, List<double>>> loadStored(String entityId) async {
    final raw = await _store.getString(_key(entityId));
    if (raw == null) return const {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final offsets = (m['offsets'] as Map<String, dynamic>?) ?? const {};
      return {
        for (final e in offsets.entries)
          if ((e.value as List).length == kEqBands.length)
            // Drop anything that isn't the current band count rather than
            // handing a short list to the sliders — composeCorrection's length
            // check is an assert, so in release it would be a RangeError.
            e.key: [for (final v in e.value as List) (v as num).toDouble()],
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _persist(
      String entityId, Map<String, List<double>> offsets) async {
    await _store.setString(
      _key(entityId),
      jsonEncode({
        'v': 1,
        'offsets': offsets,
        // Reserved for the room measurement the offsets sit on top of.
        'measurementId': null,
      }),
    );
  }

  // -------------------------------------------------------------- pre-flight

  Future<EqPreflight> preflight({
    required String entityId,
    required List<SonosDevice> members,
  }) async {
    final targets = members.where((d) => d.ip != null).toList();
    if (targets.isEmpty) return EqPreflight.nothingTunable;
    if ((await loadStored(entityId)).isNotEmpty) return EqPreflight.ok;

    final repo = ref.read(sonosRepositoryProvider);
    for (final d in targets) {
      try {
        if ((await repo.roomCalibration(d.ip!)).available) {
          return EqPreflight.wouldOverwrite;
        }
      } catch (_) {
        // Unreachable or unsupported: it can't be holding a tuning we'd lose.
      }
    }
    return EqPreflight.ok;
  }

  // ------------------------------------------------------------------ apply

  /// Debounced, coalesced apply for live mode. Safe to call on every slider
  /// release; only the latest value is ever written.
  void requestLiveApply({
    required String entityId,
    required List<SonosDevice> members,
    required Map<String, List<double>> offsets,
  }) {
    _pending = _EqRequest(entityId, members, offsets);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _drain);
  }

  /// Cancels a queued live apply (leaving the screen, switching live mode off).
  void cancelPending() {
    _debounce?.cancel();
    _debounce = null;
    _pending = null;
  }

  Future<void> _drain() async {
    if (_inFlight) return; // the in-flight run picks _pending up when it lands
    final req = _pending;
    if (req == null) return;
    _pending = null;

    final since = DateTime.now().difference(_lastApply);
    if (since < _minInterval) {
      _pending = req;
      _debounce?.cancel();
      _debounce = Timer(_minInterval - since, _drain);
      return;
    }

    await apply(
      entityId: req.entityId,
      members: req.members,
      offsets: req.offsets,
    );
    if (_pending != null) {
      _debounce?.cancel();
      _debounce = Timer(_minInterval, _drain);
    }
  }

  /// Compose, fit and write the EQ to every member, then enable it.
  ///
  /// Returns true when the speakers confirm the tuning is stored. An HTTP 200 is
  /// not a verdict — the player accepts wrong channel ids, too many sections or
  /// an inconsistent session id with a 200 and stores nothing — so the result is
  /// always read back from `GetRoomCalibrationStatus`.
  Future<bool> apply({
    required String entityId,
    required List<SonosDevice> members,
    required Map<String, List<double>> offsets,
  }) async {
    if (_inFlight) return false;
    _inFlight = true;
    state = SpeakerEqStatus(entityId: entityId, busy: true);
    try {
      final ok = await _applyInner(entityId, members, offsets);
      state = SpeakerEqStatus(entityId: entityId, applied: ok);
      return ok;
    } catch (e) {
      DiagnosticsLog.add('[eq] apply failed: $e');
      state = SpeakerEqStatus(entityId: entityId, error: e);
      return false;
    } finally {
      _inFlight = false;
      _lastApply = DateTime.now();
    }
  }

  Future<bool> _applyInner(
    String entityId,
    List<SonosDevice> members,
    Map<String, List<double>> offsets,
  ) async {
    final targets = members.where((d) => d.ip != null).toList();
    if (targets.isEmpty) {
      throw const SonorityError(SonorityErrorCode.nothingTunable);
    }

    // One session id for the whole batch. It is a free-form label, but a member
    // declaring a different session than the rest of the set is dropped.
    final session = 'sonority_${entityId}_'
        '${DateTime.now().millisecondsSinceEpoch}';
    final grid = eqGrid();

    final tunings = <SonosDevice, SpectralTuning>{};
    for (final d in targets) {
      // Channel ids are re-read immediately before every apply and never cached:
      // they track the channel ROLE a bond assigns, they are scoped per player,
      // and a soundbar's list is not predictable from its layout at all. Wrong
      // ids mean HTTP 200 with nothing stored and no error.
      final cfg = (await _apply.readDeviceConfig(ip: d.ip!, rincon: d.uuid))
          .config;
      // ABORT, never skip. A batch missing one bonded member is exactly the
      // incomplete set that stores nothing — and if the rest happened to commit,
      // enabling a partial set is the documented way to destroy the tunings on
      // the members that were left out.
      if (cfg == null || cfg.channels.isEmpty) {
        DiagnosticsLog.add(
            '[eq] ${d.roomName} (${d.ip}) reported no tunable channels; '
            'aborting before any write');
        throw const SonorityError(SonorityErrorCode.nothingTunable);
      }
      // A degenerate config would fit to a do-nothing cascade, and the oracle
      // would still flip — reporting "Applied" for an EQ that does nothing.
      if (cfg.maxSections < 2 ||
          cfg.sampleRates.take(cfg.channels.length).any((r) => r <= 0)) {
        DiagnosticsLog.add('[eq] ${d.roomName} reported an unusable config '
            '(maxSections ${cfg.maxSections}, rates ${cfg.sampleRates})');
        throw const SonorityError(SonorityErrorCode.nothingTunable);
      }

      final correction = composeCorrection(
        bandOffsetsDb: offsets[d.uuid] ?? List.filled(kEqBands.length, 0),
        freqs: grid,
      );
      tunings[d] = SpectralTuning(
        deviceId: session,
        channels: [
          for (var i = 0; i < cfg.channels.length; i++)
            ChannelTuning(
              channel: cfg.channels[i],
              biquads: sectionsForCorrection(
                correction,
                grid,
                fs: cfg.sampleRates[i],
                maxSections: cfg.maxSections,
              ),
            ),
        ],
      );
    }
    if (tunings.isEmpty) {
      throw const SonorityError(SonorityErrorCode.nothingTunable);
    }

    for (final e in tunings.entries) {
      final status = await _apply.applySpectral(
        ip: e.key.ip!,
        rincon: e.key.uuid,
        tuning: e.value,
        live: true,
      );
      // A 200 is not success — but a non-200 IS failure, and it is the only
      // failure the transport can tell us about at all, so don't discard it.
      if (status != 200) {
        DiagnosticsLog.add(
            '[eq] ${e.key.roomName} (${e.key.ip}) rejected the tuning: '
            'HTTP $status');
        throw const SonorityError(SonorityErrorCode.tuningNotStored);
      }
    }

    // ⚠️ The oracle can only observe "a tuning exists", so it genuinely proves a
    // FIRST apply and cannot distinguish a re-apply that stored from one that
    // silently didn't — `available` is already 1 either way. Poll every member
    // regardless: on a first apply that catches a satellite that failed to
    // commit while the coordinator did, which one-member polling misses.
    for (final d in tunings.keys) {
      if (!await _pollAvailable(d.ip!, want: true)) {
        throw const SonorityError(SonorityErrorCode.tuningNotStored);
      }
    }

    // Storing is not enabling — that is a separate call, which is also what
    // makes the existing Trueplay switch an instant A/B for this EQ.
    await ref
        .read(trueplayControllerProvider.notifier)
        .setEnabled(tunings.keys, true);

    await _persist(entityId, offsets);
    return true;
  }

  // ----------------------------------------------------------------- remove

  /// Clears the stored tuning. Irreversible by design — this is the only path
  /// that may call `ClearAllTunings`; switching the EQ *off* goes through the
  /// Trueplay enable flag, which preserves what is stored.
  Future<bool> remove({
    required String entityId,
    required List<SonosDevice> members,
  }) async {
    cancelPending();
    if (_inFlight) return false;
    _inFlight = true;
    state = SpeakerEqStatus(entityId: entityId, busy: true);
    try {
      final targets = members.where((d) => d.ip != null).toList();
      for (final d in targets) {
        await _apply.clearAllTunings(ip: d.ip!, rincon: d.uuid, live: true);
      }
      if (targets.isNotEmpty &&
          !await _pollAvailable(targets.first.ip!, want: false)) {
        throw const SonorityError(SonorityErrorCode.tuningNotCleared);
      }
      await _store.setString(_key(entityId), jsonEncode({'v': 1}));
      await ref.read(trueplayControllerProvider.notifier).load(targets);
      state = const SpeakerEqStatus();
      return true;
    } catch (e) {
      DiagnosticsLog.add('[eq] remove failed: $e');
      state = SpeakerEqStatus(entityId: entityId, error: e);
      return false;
    } finally {
      _inFlight = false;
    }
  }

  Future<bool> _pollAvailable(String ip, {required bool want}) async {
    final repo = ref.read(sonosRepositoryProvider);
    for (var i = 0; i < 8; i++) {
      try {
        if ((await repo.roomCalibration(ip)).available == want) return true;
      } catch (_) {
        // Keep polling: a player can refuse briefly right after a write.
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    return false;
  }
}

@immutable
class _EqRequest {
  final String entityId;
  final List<SonosDevice> members;
  final Map<String, List<double>> offsets;
  const _EqRequest(this.entityId, this.members, this.offsets);
}
