import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n.dart';
import '../data/models/sonos_models.dart';
import '../data/sonos/apply_progress.dart';
import '../data/sonos/cancellation.dart';
import '../data/sonos/channel_map.dart';
import '../data/sonos/diagnostics_log.dart';
import '../data/sonos/front_layout.dart' as front_layout;
import '../data/sonos/identify_service.dart';
import '../data/sonos/led_identify.dart';
import '../data/sonos/sonos_repository.dart';
import '../data/sonos/sonority_error.dart';
import '../data/sonos/speaker_settings.dart';
import '../features/profiles/profile.dart';
import '../features/profiles/profile_controller.dart'
    show EntityIssue, preflightProfile;
import 'localized_error.dart';
import 'shared_preferences_store.dart';

/// Localized name for an entity kind — used in progress step labels. The
/// `kindLabel` getter on [EntitySnapshot] is the widget-side equivalent.
String _kindLabel(AppLocalizations l10n, EntityKind kind) => switch (kind) {
      EntityKind.homeTheater => l10n.entityKindHomeTheater,
      EntityKind.stereoPair => l10n.entityKindStereoPair,
      EntityKind.zone => l10n.entityKindZone,
      EntityKind.custom => l10n.entityKindCustom,
      EntityKind.single => l10n.entityKindSpeaker,
    };

final sonosRepositoryProvider = Provider<SonosRepository>(
    (ref) => SonosRepository(store: SharedPreferencesKeyValueStore()));

/// Phase emitters for one parent (entity) step — built by
/// `SonosController._phases`, consumed by the apply helpers so each phase
/// becomes a persistent sub-step in the progress timeline instead of an
/// overwriting note.
typedef Phases = ({
  void Function(List<(String, String)>) seed,
  void Function(String id, String label) phase,
  void Function(String) note,
  void Function(String) log,
  void Function({String? detail}) skipPhase,
});

/// Live per-step progress of the in-flight bonding operation (full HT setup /
/// profile-apply). The flow/profile UI watches this to show a stepper with the
/// active step and exactly where a failure happened. Empty when idle.
class ApplyProgressNotifier extends Notifier<List<ApplyStep>> {
  @override
  List<ApplyStep> build() => const [];
  void set(List<ApplyStep> steps) => state = steps;
  void clear() => state = const [];
}

final applyProgressProvider =
    NotifierProvider<ApplyProgressNotifier, List<ApplyStep>>(
      ApplyProgressNotifier.new,
    );

/// Accumulating raw log of the in-flight bonding operation — the same step/note
/// events as [applyProgressProvider], kept as timestamped lines for the
/// power-user log view + copy-out. Cleared at the start of each operation.
class OperationLogNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void add(String line) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ts = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    state = [...state, '$ts  $line'];
  }

  void clear() => state = const [];
}

final operationLogProvider =
    NotifierProvider<OperationLogNotifier, List<String>>(
      OperationLogNotifier.new,
    );

/// Plays a chime on a speaker to help identify Left vs Right. Holds a local
/// HTTP server, so it's torn down when the provider is disposed.
final identifyServiceProvider = Provider<IdentifyServiceClient>((ref) {
  final service = IdentifyServiceClient(null, (m) {
    if (kDebugMode) debugPrint('[identify] $m');
    DiagnosticsLog.add('[identify] $m');
  });
  ref.onDispose(service.dispose);
  return service;
});

/// Blinks a speaker's status LED to identify it. The default identify action:
/// silent, non-intrusive, and works on every platform (including the sandboxed
/// macOS app, where the chime can't).
final ledIdentifyProvider = Provider<LedIdentifyClient>((ref) {
  return LedIdentifyClient(null, (m) {
    if (kDebugMode) debugPrint('[led] $m');
    DiagnosticsLog.add('[led] $m');
  });
});

final sonosControllerProvider =
    AsyncNotifierProvider<SonosController, SonosSystem?>(SonosController.new);

/// Holds the discovered Sonos system and drives the bonding actions.
///
/// Scans automatically on first read (app launch); `AsyncLoading` == working;
/// `AsyncError` surfaces a message to the UI.
class SonosController extends AsyncNotifier<SonosSystem?> {
  String? _lastIp;

  /// The in-flight bonding operation's cancel token, if any. Set at the start of
  /// each bonding op and tripped by [cancelActiveOperation] (the Abort button).
  CancellationToken? _activeOp;

  /// Aborts the in-flight bonding operation at its next checkpoint. Cooperative:
  /// an in-flight SOAP write still completes, but the sequence stops before the
  /// next step — which is why the UI warns it can leave an in-between state.
  void cancelActiveOperation() => _activeOp?.cancel();

  @override
  Future<SonosSystem?> build() => _discover();

  SonosRepository get _repo => ref.read(sonosRepositoryProvider);

  final _settings = SpeakerSettingsClient();

  /// Reads each entity's per-speaker settings ([audio] bundle and/or [volume])
  /// and returns copies enriched with a `settings` map. Called by
  /// the create flow when the user opts into saving speaker settings; keeps the
  /// SOAP reads off the widget. Speakers not currently on the network are simply
  /// skipped (nothing to read).
  Future<List<EntitySnapshot>> captureSettings(
    List<EntitySnapshot> entities, {
    required bool audio,
    required bool volume,
  }) async {
    final sys = state.value;
    if (sys == null || (!audio && !volume)) return entities;
    final out = <EntitySnapshot>[];
    for (final e in entities) {
      final map = <String, SpeakerSettings>{};
      for (final uuid in e.involvedUuids) {
        final dev = sys.device(uuid);
        final ip = dev?.ip;
        if (ip == null) continue;
        // In an HT only the coordinator (soundbar) carries the audio bundle; the
        // satellites reject every EQ read with UPnPError 803, so skip their audio
        // reads entirely rather than fire ~17 calls that all fault.
        final isHtSatellite =
            e.kind == EntityKind.homeTheater && uuid != e.primaryUuid;
        // The extended EQ bundle (sub/surround/night/speech/height) is only
        // meaningful on a soundbar, a sub, or an HT coordinator — a plain speaker
        // answers those GetEQ calls with junk defaults. Gate it per DEVICE, not
        // per entity, so a plain member of a group that merely CONTAINS a sub
        // isn't swept in (it still captures bass/treble/loudness).
        final extendedEq =
            (dev?.isSoundbar ?? false) ||
            (dev?.isSub ?? false) ||
            (e.kind == EntityKind.homeTheater && uuid == e.primaryUuid);
        final s = await _settings.read(
          ip,
          audio: audio && !isHtSatellite,
          volume: volume,
          extendedEq: extendedEq,
        );
        if (!s.isEmpty) map[uuid] = s;
      }
      out.add(map.isEmpty ? e : e.copyWith(settings: map));
    }
    return out;
  }

  /// Restores each captured per-speaker setting after a bond has settled (bonding
  /// can reset EQ, so this must run last). Best-effort + a no-op when [e] carries
  /// no settings (old profiles / toggles off) → zero extra writes.
  Future<void> _restoreSettings(
    EntitySnapshot e,
    SonosSystem sys,
    Phases ph,
  ) async {
    if (e.settings.isEmpty) return;
    final l10n = appL10n();
    ph.phase('settings', l10n.stepRestoreSettings);
    for (final entry in e.settings.entries) {
      _activeOp?.throwIfCancelled();
      final dev = sys.device(entry.key);
      final ip = dev?.ip;
      if (ip == null) {
        ph.note(l10n.stepSkippingSettingsOffline);
        continue;
      }
      final s = entry.value;
      final what = [
        if (s.hasAudioSettings) l10n.stepAudioSettings,
        if (s.hasVolume) l10n.stepVolume,
      ].join(' + ');
      ph.note(l10n.stepRestoring(what, dev!.typeLabel));
      final failed = await _settings.apply(ip, s);
      if (failed > 0) {
        ph.note(l10n.stepSettingsFailed(failed, dev.typeLabel));
      }
    }
  }

  /// Discover the system and cache an IP for cheap refreshes. Runs on launch
  /// (from [build]) and on every explicit [scan].
  Future<SonosSystem?> _discover() async {
    final system = await _repo.discover();
    _lastIp = system.devicesByUuid.values
        .map((d) => d.ip)
        .firstWhere((ip) => ip != null, orElse: () => null);
    return system;
  }

  Future<void> scan() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_discover);
  }

  /// Re-read topology after a change to confirm the new layout took effect.
  Future<void> refresh() async {
    final current = state.value;
    final ip = _lastIp;
    if (current == null || ip == null) {
      await scan();
      return;
    }
    state = await AsyncValue.guard(() => _repo.refresh(current, ip));
  }

  /// Applies the [layout] (channel → speaker: fronts LF/RF or an Amp on both,
  /// surrounds LR/RR) plus [subs] (SW, up to two) to the soundbar as the COMPLETE
  /// desired satellite set. The setup flow pre-seeds [layout] from the current
  /// bond and edits it, so an omitted role means "unbond it" — [_applyHtTarget]
  /// diffs current-vs-target and `RemoveHTSatellite`s whatever's no longer wanted
  /// before additively bonding the rest. Emits per-step progress via
  /// [applyProgressProvider]. A no-op layout (equals current) writes nothing.
  Future<void> applyHomeTheaterLayout({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required Map<SonosChannel, SonosDevice> layout,
    List<SonosDevice> subs = const [],
  }) async {
    // ponytail: single in-flight op; queue only if users hit it.
    if (state.isLoading) return;
    // The layout IS the target — no `preserveExisting` overlay, so deselected
    // roles drop out and get unbonded. Subs go via [subUuids] (repeatable channel).
    final target = front_layout.buildLayoutMap(
      soundbar: soundbar,
      soundbarDevice: soundbarDevice,
      desired: {for (final e in layout.entries) e.key: e.value.uuid},
      subUuids: [for (final d in subs) d.uuid],
      preserveExisting: false,
    );

    final l10n = appL10n();
    final tracker = _newTracker(
        [ApplyStep(id: 'bond', label: l10n.stepSetUpHomeTheater)]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('bond');
      final ph = _phases(tracker, 'bond');
      ph.seed([('bond', l10n.stepBondNSpeakers(target.entries.length - 1))]);
      try {
        final sys = await _applyHtTarget(
          bar: soundbarDevice,
          current: soundbar,
          target: target,
          sys: previous ?? await _repo.discover(),
          ph: ph,
        );
        tracker.done('bond');
        return sys;
      } catch (e) {
        // OperationCancelled lands here too — its message is the aborted text.
        tracker.fail('bond', localizedError(l10n, e));
        rethrow;
      }
    });
    _commit(result, previous);
  }

  /// Re-applies a saved [profile] to the live system: one progress step per
  /// entity (HT / stereo pair / single room), skipping any whose primary UUID is
  /// in [skip] (e.g. a speaker the pre-flight found missing). Each entity frees
  /// conflicting speakers, re-bonds (staged for HT), and restores its room
  /// names. Emits per-step progress via [applyProgressProvider].
  Future<void> applyProfile(
    Profile profile, {
    Set<String> skip = const {},
  }) async {
    // ponytail: single in-flight op; queue only if users hit it.
    if (state.isLoading) return;
    final current = state.value;
    if (current == null) return;
    final entities = profile.entities
        .where((e) => !skip.contains(e.primaryUuid))
        .toList();
    if (entities.isEmpty) return;

    final l10n = appL10n();
    final tracker = _newTracker([
      for (final e in entities)
        ApplyStep(
            id: e.primaryUuid, label: '${_kindLabel(l10n, e.kind)}: ${e.label}'),
    ]);
    _activeOp = CancellationToken();

    final previous = current;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _runEntitySteps(entities, previous, tracker),
    );
    _commit(result, previous);
  }

  /// Like [applyProfile] but for an out-of-app launch (app shortcut / home-screen
  /// widget): there's no reliable prior scan (or it's stale), so the FIRST
  /// progress step scans the network, then a fresh pre-flight runs. When it finds
  /// missing/conflicting speakers, [confirmIssues] is asked (the UI shows the
  /// same confirm dialog as an in-app apply, over the progress screen); returning
  /// false aborts. Otherwise it applies straight through, auto-skipping missing
  /// entities. Runs behind the same progress screen as [applyProfile].
  Future<void> scanAndApplyProfile(
    Profile profile, {
    Future<bool> Function(List<EntityIssue> issues)? confirmIssues,
  }) async {
    if (_activeOp != null) return; // don't stack bonding ops
    // Set the cancel token BEFORE the scan so Abort works during the scan step
    // too (not just once bonding starts).
    final cancel = CancellationToken();
    _activeOp = cancel;
    final l10n = appL10n();
    final tracker = _newTracker([
      ApplyStep(id: _scanStepId, label: l10n.stepScanNetwork),
      for (final e in profile.entities)
        ApplyStep(
            id: e.primaryUuid, label: '${_kindLabel(l10n, e.kind)}: ${e.label}'),
    ]);

    // ponytail: cooperative cancel — steps 1–2 (scan/preflight/confirm) run
    // outside AsyncValue.guard, so ANY throw here (incl. preflight/confirm) must
    // null _activeOp exactly once or the entry guard above dead-locks every future
    // apply. This catch owns that; only step 3's _commit nulls the happy path.
    final List<EntitySnapshot> applicable;
    final SonosSystem previous;
    try {
      // Step 1 — scan. Reuse an in-flight app-launch discovery (also lets it
      // commit so its late completion can't clobber the applied state below);
      // otherwise run a fresh scan since a launch's earlier scan may be stale.
      // (discover()/SSDP isn't interruptible, so we race it against the token
      // via [_untilCancelled]: an abort stops the UI waiting in ~250ms while the
      // socket self-closes in the background — the throwIfCancelled right after
      // turns that into a clean stop before any write.)
      tracker.start(_scanStepId);
      final scanFuture = state.isLoading
          ? future
          : scan().then((_) => state.value);
      SonosSystem? scanned;
      try {
        scanned = await untilCancelled(scanFuture, cancel);
      } catch (_) {
        /* aborted → rethrown by throwIfCancelled below; other errors
                       → scanned stays null → handled below */
      }
      cancel
          .throwIfCancelled(); // aborted during the scan? stop before any write
      if (scanned == null) {
        tracker.fail(_scanStepId, l10n.errSystemNotFound);
        throw state.error ??
            const SonorityError(SonorityErrorCode.systemNotFound);
      }
      tracker.done(_scanStepId);

      // Step 2 — pre-flight. If anything's missing/conflicting, confirm before
      // any write (declining aborts cleanly — nothing bonded yet).
      final issues = preflightProfile(profile, scanned);
      final hasIssues = issues.any(
        (i) => i.missing.isNotEmpty || i.conflicts.isNotEmpty,
      );
      if (hasIssues && confirmIssues != null) {
        final proceed = await confirmIssues(issues);
        if (!proceed) throw const OperationCancelled();
      }
      cancel.throwIfCancelled();
      // Auto-skip entities whose speakers aren't present.
      final blocked = <String, String>{
        for (final i in issues)
          if (i.blocked) i.entity.primaryUuid: i.missing.toSet().join(', '),
      };
      applicable = <EntitySnapshot>[];
      for (final e in profile.entities) {
        final miss = blocked[e.primaryUuid];
        if (miss != null) {
          tracker.done(e.primaryUuid, detail: l10n.stepSkippedMissing(miss));
        } else {
          applicable.add(e);
        }
      }
      previous = scanned;
    } catch (_) {
      _activeOp = null;
      // Abort during scan/pre-flight: mark the step that was running. No-op for
      // the "not found" path (scan step already failed) and a confirm decline
      // (no step active), so only a real abort attaches the reason.
      tracker.failActive(l10n.errAborted);
      rethrow;
    }

    // Step 3 — bond the resolvable entities under the same progress timeline
    // (reusing the cancel token set up top so Abort stays wired throughout).
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _runEntitySteps(applicable, previous, tracker),
    );
    _commit(result, previous);
  }

  static const _scanStepId = '__scan';

  /// One progress step per entity (bond → restore name → restore settings),
  /// failing the step and rethrowing on the first error. Shared by
  /// [applyProfile] and [scanAndApplyProfile]; [sys] is the current live system.
  Future<SonosSystem> _runEntitySteps(
      List<EntitySnapshot> entities, SonosSystem sys, ApplyProgress tracker) async {
    final l10n = appL10n();
    for (final e in entities) {
      _activeOp?.throwIfCancelled(); // abort before starting the next entity
      tracker.start(e.primaryUuid);
      final ph = _phases(tracker, e.primaryUuid);
      // Pre-list the phases knowable from the snapshot; conditional ones
      // (freeing conflicts, removing changed satellites) pop in when needed.
      ph.seed([
        if (e.kind == EntityKind.homeTheater)
          ('bond', l10n.stepBondNSpeakers(e.involvedUuids.length - 1))
        else if (e.kind != EntityKind.single)
          ('bond', l10n.stepBondNSpeakers(e.involvedUuids.length)),
        ('names', l10n.stepRestoreRoomName),
        if (e.settings.isNotEmpty) ('settings', l10n.stepRestoreSettings),
      ]);
      try {
        sys = await _applyEntity(e, sys, ph);
        // Restore captured EQ/volume last — bonding can reset EQ.
        await _restoreSettings(e, sys, ph);
        tracker.done(e.primaryUuid);
      } catch (err) {
        // OperationCancelled lands here too — its message is the aborted text.
        tracker.fail(e.primaryUuid, localizedError(l10n, err));
        rethrow;
      }
    }
    return sys;
  }

  Future<SonosSystem> _applyEntity(
      EntitySnapshot e, SonosSystem sys, Phases ph) async {
    final l10n = appL10n();
    switch (e.kind) {
      case EntityKind.single:
        final dev = sys.device(e.primaryUuid);
        if (dev?.ip == null) {
          throw SonorityError(SonorityErrorCode.entityNotOnNetwork, e.label);
        }
        if (sys.ownerOf(e.primaryUuid) != null) {
          _activeOp?.throwIfCancelled();
          ph.phase('free', l10n.stepFreeFromBond);
          await _repo.freeSpeaker(sys, e.primaryUuid);
          ph.note(l10n.stepWaitingSettle);
          sys = await _settleRead(sys, dev!.ip!);
        }
        _activeOp?.throwIfCancelled();
        ph.phase('names', l10n.stepRestoreRoomName);
        if (!await _repo.setRoomName(
            ip: dev!.ip!, name: e.names[e.primaryUuid] ?? dev.roomName)) {
          ph.skipPhase(detail: l10n.stepNameUnchanged);
        }
        return sys;

      // Stereo pair / zone / custom all share one channel-map bond path.
      case EntityKind.stereoPair || EntityKind.zone || EntityKind.custom:
        final map = e.mapSet;
        if (map == null) {
          throw const SonorityError(SonorityErrorCode.malformedGroup);
        }
        final coord = sys.device(e.primaryUuid);
        if (coord?.ip == null) {
          throw SonorityError(
              SonorityErrorCode.coordinatorNotOnNetwork, e.label);
        }
        final involved = e.involvedUuids.toList();
        // Already exactly this group? Just re-assert the name (no disruptive write).
        if (_isGroupFormed(sys, e.primaryUuid, involved)) {
          ph.phase('bond', l10n.stepBondNSpeakers(involved.length));
          ph.skipPhase(detail: l10n.stepAlreadyFormed);
          _activeOp?.throwIfCancelled();
          ph.phase('names', l10n.stepRestoreRoomName);
          if (!await _repo.setRoomName(
              ip: coord!.ip!, name: e.names[coord.uuid] ?? coord.roomName)) {
            ph.skipPhase(detail: l10n.stepNameUnchanged);
          }
          return sys;
        }
        // Free any member currently bonded outside this group.
        for (final u in involved) {
          final owner = sys.ownerOf(u);
          if (owner != null && !involved.contains(owner)) {
            _activeOp?.throwIfCancelled();
            ph.phase('free', l10n.stepFreeConflicting);
            ph.note(l10n.stepFreeing(sys.device(u)?.roomName ?? u));
            await _repo.freeSpeaker(sys, u);
            sys = await _settleRead(sys, coord!.ip!);
          }
        }
        // Resolve members (coordinator-first) + sub from the stored map.
        final parsed = ZoneGroupMember(
          uuid: e.primaryUuid,
          zoneName: '',
          channelMapSet: map,
        );
        final memberEntries = <({SonosDevice device, GroupChannel channel})>[];
        for (final entry in parsed.groupChannels.entries) {
          final d = sys.device(entry.key);
          if (d?.ip == null) {
            throw SonorityError(
                SonorityErrorCode.speakerInEntityNotOnNetwork, e.label);
          }
          memberEntries.add((device: d!, channel: entry.value));
        }
        final subU = parsed.subUuid;
        final sub = subU == null ? null : sys.device(subU);
        if (subU != null && sub?.ip == null) {
          throw SonorityError(SonorityErrorCode.subNotOnNetwork, e.label);
        }
        if (memberEntries.length < 2) {
          throw SonorityError(
              SonorityErrorCode.entityMissingSpeakers, e.label);
        }
        _activeOp?.throwIfCancelled();
        ph.phase(
            'bond',
            sub != null
                ? l10n.stepBondNSpeakersWithSub(memberEntries.length)
                : l10n.stepBondNSpeakers(memberEntries.length));
        await _repo.createGroup(members: memberEntries, sub: sub);
        ph.note(l10n.stepWaitingConfirm);
        sys = await _pollUntil(
          previous: sys,
          ip: coord!.ip,
          attempts: 8,
          until: (s) => _isGroupFormed(s, e.primaryUuid, involved),
        );
        if (!_isGroupFormed(sys, e.primaryUuid, involved)) {
          throw SonorityError(SonorityErrorCode.didNotForm, e.label);
        }
        _activeOp?.throwIfCancelled();
        ph.phase('names', l10n.stepRestoreRoomName);
        if (!await _repo.setRoomName(
            ip: coord.ip!, name: e.names[coord.uuid] ?? coord.roomName)) {
          ph.skipPhase(detail: l10n.stepNameUnchanged);
        }
        return sys;

      case EntityKind.homeTheater:
        final bar = sys.device(e.primaryUuid);
        if (bar?.ip == null) {
          throw SonorityError(SonorityErrorCode.soundbarNotOnNetwork, e.label);
        }
        final map = e.mapSet;
        if (map == null) {
          throw const SonorityError(SonorityErrorCode.malformedHomeTheater);
        }
        // The saved map IS the exact target (bar + every satellite, including a
        // second Sub in a dual-sub setup) — use it directly rather than a
        // channel→uuid map, which would collapse two SW entries into one.
        final fullTarget = ChannelMap.parse(map);
        final satUuids = fullTarget.entries.skip(1).map((e) => e.uuid).toSet();
        // Free any satellite currently bonded to a different coordinator/pair.
        for (final u in satUuids) {
          final owner = sys.ownerOf(u);
          if (owner != null && owner != bar!.uuid) {
            _activeOp?.throwIfCancelled();
            ph.phase('free', l10n.stepFreeConflicting);
            ph.note(l10n.stepFreeing(sys.device(u)?.roomName ?? u));
            await _repo.freeSpeaker(sys, u);
            sys = await _settleRead(sys, bar.ip!);
          }
        }
        // Diff against the live layout and apply only what changed — no strip.
        // A re-applied/unchanged layout is a no-op (zero writes); otherwise
        // remove just the satellites that move or leave, then additively bond.
        // Confirmed on hardware (tool/diff_apply_spike.dart) that additive
        // AddHTSatellite holds without stripping, and is more reliable than a
        // full rebuild-from-bare since it only bonds what's actually missing.
        final cur = sys.memberByUuid(bar!.uuid);
        sys = await _applyHtTarget(
          bar: bar,
          current: cur ?? ZoneGroupMember(uuid: bar.uuid, zoneName: e.label),
          target: fullTarget,
          sys: sys,
          ph: ph,
        );
        _activeOp?.throwIfCancelled();
        ph.phase('names', l10n.stepRestoreRoomName);
        if (!await _repo.setRoomName(
            ip: bar.ip!, name: e.names[bar.uuid] ?? bar.roomName)) {
          ph.skipPhase(detail: l10n.stepNameUnchanged);
        }
        return sys;
    }
  }

  /// Brings the coordinator [bar]'s live layout to [target] with the minimum
  /// writes: skip entirely when unchanged, `RemoveHTSatellite` only the
  /// satellites that move/leave (AddHTSatellite 800s on a map that would drop
  /// them), then additively `bondAndVerify` the target. Shared by profile-apply
  /// and the in-app HT setup flow.
  Future<SonosSystem> _applyHtTarget({
    required SonosDevice bar,
    required ZoneGroupMember current,
    required ChannelMap target,
    required SonosSystem sys,
    required Phases ph,
  }) async {
    final l10n = appL10n();
    final diff = front_layout.diffHtLayout(current: current, target: target);
    final bondLabel = l10n.stepBondNSpeakers(target.entries.length - 1);
    if (diff.isNoOp) {
      ph.phase('bond', bondLabel);
      ph.skipPhase(detail: l10n.stepLayoutUnchanged);
      return sys;
    }
    if (diff.toRemove.isNotEmpty) {
      // Only genuine leaves reach here (a dropped sub / a replaced speaker) —
      // a speaker that merely moves channel stays bonded and reassigns in place.
      ph.phase('remove', l10n.stepRemoveUnused(diff.toRemove.length));
      await _repo.removeHtSatellites(
          soundbarIp: bar.ip!, uuids: diff.toRemove, cancel: _activeOp);
      ph.note(l10n.stepWaitingSettle);
      sys = await _settleRead(sys, bar.ip!);
    }
    ph.phase('bond', bondLabel);
    // One calm, steady subtitle for the whole (re-)assert loop; the per-attempt
    // retry churn stays in the log (ph.log) rather than flickering the timeline
    // — a swap 800s and re-asserts several times, which reads as alarming
    // otherwise even though it's normal Sonos settling.
    ph.note(l10n.stepApplyingSettle);
    return _repo.bondAndVerify(
      coordinator: bar,
      target: target,
      previous: sys,
      onNote: ph.log,
      cancel: _activeOp,
    );
  }

  Future<SonosSystem> _settleRead(SonosSystem sys, String ip) async {
    await interruptibleDelay(const Duration(seconds: 4), _activeOp);
    try {
      return await _repo.refresh(sys, ip);
    } catch (_) {
      return sys;
    }
  }

  /// Renames a room (the visible zone) via SetZoneAttributes, then polls until
  /// the new name propagates — the topology lags ~15s, so a single refresh would
  /// show the old name and the AppBar wouldn't update until a manual refresh.
  Future<void> renameRoom({
    required SonosDevice device,
    required String name,
  }) async {
    final ip = device.ip;
    if (ip == null) {
      throw const SonorityError(SonorityErrorCode.speakerIpUnknown);
    }
    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      try {
        await _repo.setRoomName(ip: ip, name: name);
      } catch (e) {
        // This path has no progress tracker, so a fault would otherwise only
        // reach the UI as an AsyncError and never the diagnostics bundle.
        DiagnosticsLog.add('[rename] "$name" @ $ip failed: $e');
        rethrow;
      }
      bool propagated(SonosSystem s) =>
          s.allMembers.any((m) => m.uuid == device.uuid && m.zoneName == name);
      var system = await _pollUntil(
        previous: previous,
        ip: ip,
        attempts: 8,
        until: propagated,
      );
      // Only assert the new name once the topology actually confirms it —
      // otherwise return the real read rather than an optimistic name Sonos
      // never took. refresh() reuses the prior device index, so patch the
      // renamed device so its roomName isn't stale until the next full scan.
      if (propagated(system)) {
        final patched = {
          for (final e in system.devicesByUuid.entries)
            e.key: e.key == device.uuid
                ? e.value.copyWith(roomName: name)
                : e.value,
        };
        system = SonosSystem(groups: system.groups, devicesByUuid: patched);
      }
      return system;
    });
    _commit(result, previous);
  }

  /// Unbonds the satellites occupying [channels] (e.g. {LF,RF} fronts, {LR,RR}
  /// surrounds, {SW} sub) from the soundbar, polling until those channels are
  /// gone. UUIDs come from the authoritative `channelAssignments`.
  Future<void> removeHtRoles({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required Set<SonosChannel> channels,
    String? label,
  }) async {
    final ip = soundbarDevice.ip;
    if (ip == null) {
      throw const SonorityError(SonorityErrorCode.soundbarIpUnknown);
    }
    final uuids = <String>{
      for (final c in channels) ...soundbar.uuidsForChannel(c),
    };
    if (uuids.isEmpty) return;

    final l10n = appL10n();
    final lbl = label ?? l10n.stepSpeakers;
    final tracker =
        _newTracker([ApplyStep(id: 'remove', label: l10n.stepRemoveLabel(lbl))]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('remove');
      final ph = _phases(tracker, 'remove');
      ph.seed([
        ('unbond', l10n.stepUnbondN(uuids.length)),
        ('settle', l10n.stepWaitForSettle),
      ]);
      try {
        ph.phase('unbond', l10n.stepUnbondN(uuids.length));
        await _repo.removeHtSatellites(
            soundbarIp: ip, uuids: uuids, cancel: _activeOp);
        ph.phase('settle', l10n.stepWaitForSettle);
        // The soundbar itself always survives an unbond; a null member here is
        // the transient mid-reshuffle drop-out, NOT confirmation — keep polling.
        bool rolesGone(SonosSystem s) {
          final m = s.memberByUuid(soundbar.uuid);
          if (m == null) return false;
          return channels.every((c) => !m.channelAssignments.containsKey(c));
        }

        final sys = await _pollUntil(
          previous: previous,
          ip: ip,
          until: rolesGone,
        );
        // Sonos can 200-OK an unbond yet silently no-op — re-assert before done.
        if (!rolesGone(sys)) {
          throw SonorityError(SonorityErrorCode.didNotRemove, lbl);
        }
        tracker.done('remove');
        return sys;
      } catch (e) {
        // OperationCancelled lands here too — its message is the aborted text.
        tracker.fail('remove', localizedError(l10n, e));
        rethrow;
      }
    });
    _commit(result, previous);
  }

  /// Creates a bonded **speaker group** from [members] (≥2, each with a channel;
  /// first is the coordinator) + an optional [sub], polling until it forms AND
  /// the other members leave the room list, then optionally names it. One path
  /// for stereo / zone / custom.
  Future<void> createGroup({
    required List<({SonosDevice device, GroupChannel channel})> members,
    SonosDevice? sub,
    String? name,
  }) async {
    assert(
      members.length >= 2,
      'createGroup needs ≥2 members (UI must gate this)',
    );
    if (members.length < 2) {
      throw const SonorityError(SonorityErrorCode.groupNeedsTwo);
    }
    final coord = members.first.device;
    final involved = [
      for (final m in members) m.device.uuid,
      if (sub != null) sub.uuid,
    ];

    final l10n = appL10n();
    final tracker = _newTracker([
      ApplyStep(id: 'group', label: l10n.stepCreateGroupN(members.length)),
    ]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('group');
      final ph = _phases(tracker, 'group');
      final wanted = name?.trim();
      ph.seed([
        ('bond', l10n.stepBondSpeakers),
        ('confirm', l10n.stepWaitForConfirm),
        if (wanted != null && wanted.isNotEmpty && coord.ip != null)
          ('name', l10n.stepNameGroup),
      ]);
      try {
        ph.phase('bond', l10n.stepBondSpeakers);
        await _repo.createGroup(members: members, sub: sub);
        ph.phase('confirm', l10n.stepWaitForConfirm);
        var system = await _pollUntil(
          previous: previous,
          ip: coord.ip ?? _lastIp,
          attempts: 8,
          until: (s) =>
              _isGroupFormed(s, coord.uuid, involved) &&
              !members
                  .skip(1)
                  .any((m) => s.allMembers.any((x) => x.uuid == m.device.uuid)),
        );
        // Sonos accepts the command (200) but silently no-ops if a speaker is
        // incompatible — confirm the group actually formed.
        if (!_isGroupFormed(system, coord.uuid, involved)) {
          throw const SonorityError(SonorityErrorCode.didNotCreateGroup);
        }
        if (wanted != null && wanted.isNotEmpty && coord.ip != null) {
          ph.phase('name', l10n.stepNameGroup);
          await _repo.setRoomName(ip: coord.ip!, name: wanted);
          system = await _pollUntil(
            previous: system,
            ip: coord.ip,
            attempts: 6,
            until: (s) => s.allMembers.any(
              (m) => m.uuid == coord.uuid && m.zoneName == wanted,
            ),
          );
        }
        tracker.done('group');
        return system;
      } catch (e) {
        // OperationCancelled lands here too — its message is the aborted text.
        tracker.fail('group', localizedError(l10n, e));
        rethrow;
      }
    });
    _commit(result, previous);
  }

  /// Separates [group] back into standalone rooms (names restored): detach from
  /// any playback group → dissolve via the live channel map → poll until gone.
  Future<void> separateGroup(ZoneGroupMember group) async {
    final sys = state.value;
    if (sys == null) return;
    final cms = group.channelMapSet;
    if (cms == null || cms.isEmpty) return;
    // Coordinator first, then the rest (incl. any Sub).
    final ordered = [
      group.uuid,
      ...group.channelMapUuids.where((u) => u != group.uuid),
    ];
    final members = ordered
        .map((u) => sys.device(u))
        .whereType<SonosDevice>()
        .toList();
    if (members.isEmpty) return;
    final coord = members.first;
    final involved = group.channelMapUuids;
    final subU = group.subUuid;
    // Audio members reappear as rooms after separation; a Sub stays Invisible.
    final audioReappear = members.where(
      (m) => m.uuid != coord.uuid && m.uuid != subU,
    );

    final l10n = appL10n();
    final tracker =
        _newTracker([ApplyStep(id: 'ungroup', label: l10n.stepSeparateGroup)]);
    _activeOp = CancellationToken();

    final previous = sys;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('ungroup');
      final ph = _phases(tracker, 'ungroup');
      ph.seed([
        ('separate', l10n.stepSeparateRestore),
        ('settle', l10n.stepWaitForSettle),
      ]);
      try {
        // 1. A bond can't be dissolved while the coordinator is a non-coordinator
        //    member of a larger playback group — detach into its own group first.
        if (coord.ip != null && !_isOwnGroupCoordinator(previous, coord.uuid)) {
          ph.phase('detach', l10n.stepDetach);
          await _repo.detachFromGroup(coord.ip!);
          await _pollUntil(
            previous: previous,
            ip: coord.ip,
            attempts: 6,
            until: (s) => _isOwnGroupCoordinator(s, coord.uuid),
          );
        }
        // 2. Dissolve (SeparateStereoPair on the live map) + restore names.
        ph.phase('separate', l10n.stepSeparateRestore);
        await _repo.separateGroup(members: members, channelMapSet: cms);
        ph.phase('settle', l10n.stepWaitForSettle);
        final system = await _pollUntil(
          previous: previous,
          ip: coord.ip ?? _lastIp,
          attempts: 8,
          until: (s) =>
              !_isGroupFormed(s, coord.uuid, involved) &&
              audioReappear.every(
                (m) => s.allMembers.any((x) => x.uuid == m.uuid),
              ),
        );
        if (_isGroupFormed(system, coord.uuid, involved)) {
          throw const SonorityError(SonorityErrorCode.didNotSeparate);
        }
        tracker.done('ungroup');
        return system;
      } catch (e) {
        // OperationCancelled lands here too — its message is the aborted text.
        tracker.fail('ungroup', localizedError(l10n, e));
        rethrow;
      }
    });
    _commit(result, previous);
  }

  /// True when [uuid] is its own playback-group coordinator (a standalone
  /// playback group). NB: this is about playback grouping, NOT bonding — it is
  /// unrelated to `SonosSystem.isStandalone` (which means "not bonded into an
  /// HT/group").
  bool _isOwnGroupCoordinator(SonosSystem system, String uuid) {
    for (final g in system.groups) {
      if (g.members.any((m) => m.uuid == uuid)) {
        return g.coordinatorUuid == uuid;
      }
    }
    return true;
  }

  /// True when [coordUuid] is a live bonded group whose members (incl. any Sub)
  /// are exactly [involved].
  bool _isGroupFormed(
      SonosSystem system, String coordUuid, List<String> involved) {
    final m = system.memberByUuid(coordUuid);
    if (m == null || !m.isGroup) return false;
    final have = m.channelMapUuids.toSet();
    final want = involved.toSet();
    return have.length == want.length && have.containsAll(want);
  }

  /// Re-reads topology until [until] holds or attempts run out. Sonos takes up
  /// to ~15s to re-enumerate satellites after a bonding change, so a single
  /// short delay would show a stale/transient layout.
  Future<SonosSystem> _pollUntil({
    required SonosSystem? previous,
    required String? ip,
    required bool Function(SonosSystem) until,
    int attempts = 6,
    Duration interval = const Duration(seconds: 3),
  }) async {
    SonosSystem? system = previous;
    for (var i = 0; i < attempts; i++) {
      await interruptibleDelay(interval, _activeOp);
      try {
        system = system == null || ip == null
            ? await _repo.discover()
            : await _repo.refresh(system, ip);
        if (until(system)) return system;
      } catch (_) {
        // transient mid-reshuffle errors are expected; keep polling
      }
    }
    return system ?? await _repo.discover();
  }

  /// Surfaces the error to the caller (so the UI can show a SnackBar / the
  /// progress screen can flip to Retry). The topology is NOT left in `state` as
  /// an error — `_commit` restores the last-known system first (see there).
  void _rethrowLast(AsyncValue<SonosSystem?> result) {
    final err = result.error;
    if (err != null) throw err;
  }

  /// Builds an [ApplyProgress] wired to both the live timeline
  /// ([applyProgressProvider]) and the accumulating raw log
  /// ([operationLogProvider]) — every bonding op uses this so the shared
  /// progress screen shows both views from one source.
  ApplyProgress _newTracker(List<ApplyStep> steps) => ApplyProgress(
    steps,
    onChange: ref.read(applyProgressProvider.notifier).set,
    onLog: (line) {
      // The per-op log drives the progress screen (cleared each op); the
      // app-wide DiagnosticsLog keeps a rolling copy for the bundle.
      ref.read(operationLogProvider.notifier).add(line);
      DiagnosticsLog.add(line);
    },
  );

  /// Phase emitters bound to one parent (entity) step, so call sites don't
  /// thread the parent id: [seed] pre-lists the phases knowable upfront as
  /// pending sub-steps, [phase] begins one (seeded or conditional), [note]
  /// streams verbose progress to the active phase's subtitle, and [skipPhase]
  /// marks the active phase as a no-op (short-circuits like "layout
  /// unchanged"). Child ids are prefixed with the parent id to stay unique in
  /// the flat step list.
  Phases _phases(ApplyProgress t, String parentId) => (
    seed: (subs) => t.seedSubs(parentId, [
      for (final (id, label) in subs) ('$parentId/$id', label),
    ]),
    phase: (id, label) => t.startSub(parentId, '$parentId/$id', label),
    note: t.noteActive,
    log: t.logActive,
    skipPhase: t.skipSub,
  );

  /// Finalizes a bonding op's [result] against the pre-op [previous] state.
  /// On ANY error (a user **abort** or a real failure like [SonosSoapException])
  /// the topology stays the last-known system rather than becoming an
  /// [AsyncError] — otherwise the overview would drop the whole system and show
  /// the error instead. Abort rethrows [OperationCancelled] so the progress
  /// screen closes; a real failure rethrows so the progress screen / snackbar
  /// shows it (the failed step already lives in [applyProgressProvider]). Only a
  /// successful [result] is adopted as the new topology.
  void _commit(AsyncValue<SonosSystem?> result, SonosSystem? previous) {
    _activeOp = null;
    if (result.error is OperationCancelled) {
      state = AsyncData(previous);
      throw const OperationCancelled();
    }
    if (result.hasError) {
      state = AsyncData(previous); // keep showing the last-known system
      _rethrowLast(result); // progress screen / snackbar shows the error
    }
    state = result; // success: adopt the new topology
  }
}
