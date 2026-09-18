import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/custom_eq.dart';
import '../data/sonos/diagnostics_log.dart';
import '../data/sonos/key_value_store.dart';
import '../data/sonos/soap_client.dart';
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
  bool _inFlight = false;

  @override
  SpeakerEqStatus build() => const SpeakerEqStatus();

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

  /// Would applying destroy a tuning the user would want back?
  ///
  /// It deliberately does NOT short-circuit on "we have stored offsets, so
  /// whatever is up there must be ours". Coefficients can never be read back, so
  /// a Trueplay measured in the Sonos app *after* our last apply is
  /// indistinguishable from our own EQ — and skipping the confirm would destroy
  /// it silently and irreversibly. The screen asks once per visit, so re-applying
  /// while you tweak still doesn't nag.
  Future<bool> wouldOverwrite({required List<SonosDevice> members}) async {
    final targets = members.where((d) => d.ip != null).toList();
    if (targets.isEmpty) return false;

    final repo = ref.read(sonosRepositoryProvider);
    // In parallel: independent reads of different speakers, and doing them one
    // at a time makes the user wait for the sum of the round trips.
    final verdicts = await Future.wait(targets.map((d) async {
      try {
        // Retried: a speaker refuses :1400 for ~20-30s after being bonded or
        // unbonded, and that is exactly when someone opens this page.
        final c = await retryUnreachable(() => repo.roomCalibration(d.ip!),
            attempts: 3, interval: const Duration(seconds: 2));
        return c.available;
      } catch (e) {
        // "We couldn't ask" is not "there is nothing there". The honest verdict
        // for an unreadable member is unknown, and unknown has to warn — the
        // alternative is destroying a calibration without telling anyone.
        DiagnosticsLog.add(
            '[eq] ${d.roomName} calibration status unreadable ($e); '
            'warning rather than assuming it holds nothing');
        return true;
      }
    }));
    return verdicts.any((v) => v);
  }

  // ------------------------------------------------------------------ apply

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
    }
  }

  Future<bool> _applyInner(
    String entityId,
    List<SonosDevice> members,
    Map<String, List<double>> offsets,
  ) async {
    if (members.isEmpty) {
      throw const SonorityError(SonorityErrorCode.nothingTunable);
    }
    // ABORT, never filter. An IP-less member is a bonded speaker we simply
    // can't reach right now; dropping it produces the incomplete set that
    // stores nothing, and then ENABLES that partial set — which is the
    // documented way to destroy the tunings on the members left out.
    for (final d in members) {
      if (d.ip == null) {
        DiagnosticsLog.add('[eq] ${d.roomName} has no IP; aborting before any '
            'write rather than shipping an incomplete set');
        throw const SonorityError(SonorityErrorCode.speakerIpUnknown);
      }
    }
    final targets = members;

    // One session id for the whole batch: a member declaring a different session
    // than the rest of the set is dropped.
    //
    // ⚠️ SHAPE MATTERS, or at least has never been shown not to. Every apply
    // that has ever been accepted used `trueplay_<serial>_<firmware>_<stamp>`,
    // with the `RINCON_` prefix stripped off the serial. A different shape is
    // the kind of thing this endpoint answers with a 200 and silently drops, so
    // keep to the one that is known to work rather than the one that reads
    // nicer.
    final session = _sessionId(targets.first, DateTime.now());
    final grid = eqGrid();

    // Read every member's vocabulary AT ONCE. These are independent reads and a
    // sequential loop costs the sum of the round trips — measured at 3.4s for a
    // five-member home theatre, which is most of the time an apply takes.
    final configs = await Future.wait(targets.map((d) async =>
        (d, (await _apply.readDeviceConfig(ip: d.ip!, rincon: d.uuid)).config)));

    final tunings = <SonosDevice, SpectralTuning>{};
    for (final (d, cfg) in configs) {
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
        bandOffsetsDb: offsets[d.uuid] ?? flatCurve(),
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
    final stored = await Future.wait(
        tunings.keys.map((d) => _pollAvailable(d.ip!, want: true)));
    if (stored.any((ok) => !ok)) {
      throw const SonorityError(SonorityErrorCode.tuningNotStored);
    }

    // Storing is not enabling — that is a separate call, which is also what
    // makes the existing Trueplay switch an instant A/B for this EQ.
    final trueplay = ref.read(trueplayControllerProvider.notifier);
    await trueplay.setEnabled(tunings.keys, true);

    // `setEnabled` is per-device best-effort and swallows its failures, so ask
    // the oracle instead of trusting it. A half-enabled set is audibly wrong on
    // some speakers and right on others, which is worse than a clean failure.
    final calibration = ref.read(trueplayControllerProvider).byUuid;
    final notOn = [
      for (final d in tunings.keys)
        if (calibration[d.uuid]?.enabled == false) d.roomName,
    ];
    if (notOn.isNotEmpty) {
      DiagnosticsLog.add('[eq] stored, but not enabled on: ${notOn.join(", ")}');
      throw const SonorityError(SonorityErrorCode.tuningNotEnabled);
    }

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
    if (_inFlight) return false;
    _inFlight = true;
    state = SpeakerEqStatus(entityId: entityId, busy: true);
    try {
      final targets = members.where((d) => d.ip != null).toList();
      for (final d in targets) {
        final status =
            await _apply.clearAllTunings(ip: d.ip!, rincon: d.uuid, live: true);
        // Same rule as apply: a 200 proves nothing, but a non-200 IS a failure
        // and is the only one the transport can tell us about.
        if (status != 200) {
          DiagnosticsLog.add(
              '[eq] ${d.roomName} (${d.ip}) rejected the clear: HTTP $status');
          throw const SonorityError(SonorityErrorCode.tuningNotCleared);
        }
      }
      // Every member, not just the first: one that silently kept its
      // coefficients would otherwise be reported as cleared while still
      // filtering audio.
      final cleared = await Future.wait(
          targets.map((d) => _pollAvailable(d.ip!, want: false)));
      if (cleared.any((ok) => !ok)) {
        throw const SonorityError(SonorityErrorCode.tuningNotCleared);
      }
      // Switch the calibration flag back off too. Enabling it is part of
      // applying, so leaving it on after a clear hands back a speaker that
      // reads "calibration on" with nothing stored — not the state we found it
      // in. It is a no-op on an empty slot, which is exactly why it is cheap to
      // put right.
      await ref
          .read(trueplayControllerProvider.notifier)
          .setEnabled(targets, false);
      await _store.setString(_key(entityId), jsonEncode({'v': 1}));
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

  /// The session id every member of a batch declares.
  ///
  /// ⚠️ **NOT a free-form label, whatever the shape of it suggests.** Measured on
  /// hardware, a player stores the tuning only when the id is
  /// `<anything>_<THAT PLAYER'S SERIAL>_<a.b.c.d>_<anything>`:
  ///
  /// | id                                   | result  |
  /// |--------------------------------------|---------|
  /// | `x_<serial>_1.2.3.4_<stamp>`         | stored  |
  /// | `x_<serial>_86.8.78270.0_<stamp>`    | stored  |
  /// | `x_<serial>_1.2.3_<stamp>` (3 parts) | DROPPED |
  /// | `x_<serial>_1.2.3.4.5_<stamp>` (5)   | DROPPED |
  /// | `x_<serial>_86.8-78270_<stamp>`      | DROPPED |
  /// | `x_<serial>_<stamp>` (no version)    | DROPPED |
  /// | `x_<OTHER serial>_1.2.3.4_<stamp>`   | DROPPED |
  /// | `hello world`                        | DROPPED |
  ///
  /// The prefix and any trailing field are genuinely free. A dropped id is the
  /// silent kind of failure: HTTP 200, nothing stored, no error.
  ///
  /// The table is a STANDALONE sweep, which is why this is called once for the
  /// whole batch rather than per member: a batch shares one id, and a six-member
  /// home theater stored on every member from an id carrying only the
  /// coordinator's serial. A satellite takes its coordinator's serial too.
  ///
  /// The version field is built from the speaker's real firmware, because a real
  /// value survives a `>=` check if one exists — Sonos ships it as `86.8-78270`,
  /// which is not four dotted numbers, so it is re-shaped rather than used raw.
  static String _sessionId(SonosDevice d, DateTime now) {
    String p(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${p(now.month)}-${p(now.day)}_'
        '${p(now.hour)}-${p(now.minute)}-${p(now.second)}';
    final serial = d.uuid.startsWith('RINCON_')
        ? d.uuid.substring('RINCON_'.length)
        : d.uuid;
    return 'sonority_${serial}_${_fourPartVersion(d.softwareVersion)}_$stamp';
  }

  /// Any digit groups in [firmware], padded or truncated to exactly four parts.
  /// `86.8-78270` becomes `86.8.78270.0`; anything unparseable becomes `1.0.0.0`.
  static String _fourPartVersion(String? firmware) {
    final parts = RegExp(r'\d+')
        .allMatches(firmware ?? '')
        .map((m) => m.group(0)!)
        .toList();
    while (parts.length < 4) {
      parts.add('0');
    }
    return parts.take(4).join('.');
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
