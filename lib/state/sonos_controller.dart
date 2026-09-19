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
import '../data/sonos/soap_client.dart' show SonosSoapException, retryUnreachable;
import '../data/sonos/sonos_repository.dart';
import '../data/sonos/sonority_error.dart';
import '../data/sonos/speaker_settings.dart';
import '../features/profiles/profile.dart';
import '../features/profiles/profile_controller.dart'
    show EntityIssue, entityFreePlan, preflightProfile;
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

/// Reads/writes per-speaker EQ + volume (profile capture/restore, and the
/// diagnostics bundle's read-only snapshot). A provider so demo mode can swap in
/// a client that can't touch the network.
final speakerSettingsProvider =
    Provider<SpeakerSettingsClient>((ref) => SpeakerSettingsClient());

final sonosControllerProvider =
    AsyncNotifierProvider<SonosController, SonosSystem?>(SonosController.new);

/// Which speaker to settle-read the topology from after unbonding [unbonding].
///
/// Never one of the speakers this pass just unbonded. Each refuses :1400 for
/// ~20-30s afterwards, `_settleRead` swallows a refused socket, and the next
/// loop iteration then acts on topology where the speaker is still bonded. Two
/// of them are easy to pick by accident: for a group the "owner" IS one of them
/// (the coordinator), and the caller's fallback is frequently the new
/// coordinator. Returns null when nothing else is reachable, so the caller can
/// fall back to its last known IP.
@visibleForTesting
String? settleReadIp(
  SonosSystem sys, {
  String? ownerIp,
  String? fallbackIp,
  required Iterable<String> unbonding,
}) {
  final freed = {for (final x in unbonding) sys.device(x)?.ip};
  return ownerIp ??
      (freed.contains(fallbackIp) ? null : fallbackIp) ??
      [
        for (final d in sys.devicesByUuid.values)
          if (d.ip != null && !freed.contains(d.ip)) d.ip!
      ].firstOrNull;
}

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

  SpeakerSettingsClient get _settings => ref.read(speakerSettingsProvider);

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
    // The extended EQ bundle (sub/surround/night/speech/height) is read only from
    // the coordinators that actually carry it (soundbars + HT/sub coordinators) —
    // the Sub device 803s every EQ read, and a plain speaker answers with junk
    // defaults. Shared with the diagnostics dump so the gate can't drift.
    final extended = sys.extendedEqUuids;
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
        final extendedEq = extended.contains(uuid);
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
      final failed = await _settings.apply(ip, s, cancel: _activeOp);
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
      // `AddHTSatellite` absorbs a speaker straight out of a stereo pair or a
      // zone (EXP-23 Q7/Q9/Q10), so those need no freeing. NOT "and keep their
      // Trueplay": the coefficients survive in storage but come back off and
      // cannot be switched on, so the only thing the absorb buys is the skipped
      // write. It has NEVER been shown to absorb one out of another HOME
      // THEATER (untestable here, one soundbar) so those are freed first
      // rather than assumed. Without this the write would target a speaker the
      // other bar still claims.
      // Seeded from what we already know; the authoritative read happens inside
      // the try so a discovery failure still marks the step failed.
      final known = previous;
      final satellites = [for (final e in target.entries.skip(1)) e.uuid];
      Set<String> keepFor(SonosSystem s) {
        final live = s.memberByUuid(soundbar.uuid);
        return {soundbar.uuid, if (live != null) ...s.bondMemberUuids(live)};
      }
      final needsFree = known != null &&
          satellites.any((u) => known.mustFreeBeforeBonding(u,
              keep: keepFor(known), absorbing: true));
      ph.seed([
        if (needsFree) ('free', l10n.stepFreeConflicting),
        ('bond', l10n.stepBondNSpeakers(target.entries.length - 1)),
      ]);
      try {
        var sys = known ?? await _repo.discover();
        sys = await _freeConflicts(sys, satellites,
            keep: keepFor(sys), absorbing: true, ph: ph,
            fallbackIp: soundbarDevice.ip);
        sys = await _applyHtTarget(
          bar: soundbarDevice,
          current: sys.memberByUuid(soundbar.uuid) ?? soundbar,
          target: target,
          sys: sys,
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
    Future<bool> Function(List<EntityIssue> issues, SonosSystem scanned)?
        confirmIssues,
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
        // The scanned system goes with the issues: the dialog prices this
        // apply's Trueplay cost off it, and only this scan is fresh enough.
        final proceed = await confirmIssues(issues, scanned);
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
        // Nothing to keep and nothing absorbs a standalone room, so this is
        // the shared helper with the degenerate arguments. It also reads back
        // from the right speaker when the bond's coordinator IS the one freed.
        final plan = entityFreePlan(e, sys);
        sys = await _freeConflicts(sys, plan.uuids.toList(),
            keep: plan.keep, absorbing: plan.absorbing, ph: ph,
            phaseLabel: l10n.stepFreeFromBond);
        _activeOp?.throwIfCancelled();
        ph.phase('names', l10n.stepRestoreRoomName);
        // Retried: topology converging doesn't mean the freed speaker is
        // answering again, and losing a whole profile apply over a room-name
        // restore isn't worth it (the exact failure in the user bundle).
        if (!await retryUnreachable(
            () => _repo.setRoomName(
                ip: dev!.ip!, name: e.names[e.primaryUuid] ?? dev.roomName),
            cancel: _activeOp)) {
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
        // Free any member bonded elsewhere. `keep` must come from the LIVE
        // group, never the target set. Passing `involved` made `keep` and
        // `uuids` identical, so a member that coordinates its own bond (where
        // `ownerOf` returns itself) was never freed.
        //
        // …but `AddBondedZones` cannot DROP a member, or move the coordinator:
        // such a map faults on every attempt. `groupEditIsInPlace` is exactly
        // that test, so the live group only counts as "keep" when the rebuild
        // really can re-assert over it. Otherwise nothing is kept and the whole
        // bond is dissolved first, which is what `editGroup` does too. All of
        // that is [entityFreePlan], shared with the pre-flight.
        final htSourced = _htSourced(sys, involved);
        final plan = entityFreePlan(e, sys);
        sys = await _freeConflicts(sys, plan.uuids.toList(),
            keep: plan.keep,
            absorbing: plan.absorbing,
            ph: ph,
            fallbackIp: coord!.ip);
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
        // createGroup can sit for ~30s waiting on a member Sonos only just
        // unbonded, so say something rather than looking hung. It writes,
        // verifies and re-asserts until the group is really there (or throws),
        // so there's nothing left to poll for here.
        ph.note(l10n.stepApplyingSettle);
        sys = await _repo.createGroup(
            members: memberEntries,
            sub: sub,
            previous: sys,
            skipNameSnapshot: htSourced,
            onNote: ph.log,
            cancel: _activeOp);
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
        // Free any satellite currently bonded to a different coordinator/pair,
        // EXCEPT one sitting in a stereo pair, which `AddHTSatellite` absorbs
        // directly: the pair dissolves implicitly and the speaker's coefficients
        // survive in storage, where freeing it first (detach +
        // `SeparateStereoPair`) wipes them outright. Measured over two cycles
        // each way. EXP-23 Q7/Q9. That is NOT usable retention (it comes back
        // off and the enable destroys it), so what this buys is the skipped
        // write, and no copy credits it. `keep` MUST include this
        // bar's current members: an HT is not absorbable, so without them an
        // unchanged re-apply would free every satellite it already has,
        // stripping the bond, wiping its Trueplay, and destroying the
        // zero-write no-op the diff exists for.
        final plan = entityFreePlan(e, sys);
        sys = await _freeConflicts(sys, plan.uuids.toList(),
            keep: plan.keep,
            absorbing: plan.absorbing,
            ph: ph,
            fallbackIp: bar!.ip);
        // Diff against the live layout and apply only what changed — no strip.
        // A re-applied/unchanged layout is a no-op (zero writes); otherwise
        // remove just the satellites that move or leave, then additively bond.
        // Confirmed on hardware (tool/diff_apply_spike.dart) that additive
        // AddHTSatellite holds without stripping, and is more reliable than a
        // full rebuild-from-bare since it only bonds what's actually missing.
        final cur = sys.memberByUuid(bar.uuid);
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

  /// Free every speaker in [uuids] that is bonded somewhere the target cannot
  /// absorb it from, returning the settled system.
  ///
  /// ONE implementation because every caller kept drifting: the question is
  /// `isStandalone`, NOT `ownerOf(u) != target`. For a group's COORDINATOR
  /// `ownerOf` returns that speaker's own uuid, so an owner-based test reads it
  /// as unbonded, skips the free, and the bond write then silently no-ops
  /// (hardware-caught: it dissolved a live zone without forming the new group).
  ///
  /// [absorbing] is true for a home-theater target, which can take a speaker
  /// straight out of a pair or zone without a separate free (EXP-23 Q7/Q9/Q10),
  /// so those are skipped. It says nothing about the tuning surviving: a
  /// bonding change clears the whole destination set either way (Q20). `AddBondedZones` absorbs from nothing (Q11), and
  /// absorbing out of another home theater is unmeasured, so both are freed.
  Future<SonosSystem> _freeConflicts(
    SonosSystem sys,
    Iterable<String> uuids, {
    required Set<String> keep,
    required bool absorbing,
    required Phases ph,
    String? fallbackIp,
    String? phaseLabel,
  }) async {
    final l10n = appL10n();
    final label = phaseLabel ?? l10n.stepFreeConflicting;
    // Speakers a dissolve this pass has ALREADY freed. Freeing one member of a
    // bonded group dissolves the whole bond, so its siblings need no write of
    // their own, and the settle poll below returns its last read whether or not
    // it converged, so without this a stale read (routine: `fallbackIp` can be
    // the coordinator that just stopped answering :1400) sent a second
    // destructive write against a map that no longer exists. Seen with a stereo
    // pair built out of BOTH members of one zone.
    final dissolved = <String>{};
    for (final u in uuids) {
      if (dissolved.contains(u)) continue;
      if (!sys.mustFreeBeforeBonding(u, keep: keep, absorbing: absorbing)) continue;
      final owner = sys.ownerOf(u);
      final src = sys.memberByUuid(owner ?? '');
      _activeOp?.throwIfCancelled();
      ph.phase('free', label);
      ph.note(l10n.stepFreeing(sys.device(u)?.roomName ?? u));
      // An unbond is a bond write, so it obeys the same rule as every other one:
      // an 8s timeout or an 800 very often STILL APPLIES, so it means "go
      // verify", not "failed". Aborting here left the source bond a speaker short
      // and the destination untouched, on a write a retry would have completed.
      // The poll below is the verdict; a permanent fault (401/402) never
      // converges, so it still surfaces.
      try {
        await _repo.freeSpeaker(sys, u, cancel: _activeOp);
      } on OperationCancelled {
        rethrow;
      } on SonosSoapException catch (e) {
        if (e.faultCode != '800') rethrow;
        ph.log('free $u: error 800 (mid-reshuffle), verifying');
      } catch (e) {
        ph.log('free $u: write failed ($e), verifying');
      }
      if (src?.isGroup ?? false) dissolved.addAll(src!.channelMapUuids);
      // Read back from the FORMER OWNER, but a bond's COORDINATOR is its own
      // owner, so in that case the "owner" is the very speaker that just
      // stopped answering :1400 for ~20-30s. Fall back then, or _settleRead
      // swallows the refused socket and hands the next iteration stale
      // topology.
      final ownerIp = owner == null || owner == u ? null : sys.device(owner)?.ip;
      // …and neither may the fallback be a speaker THIS pass is unbonding, for
      // the same reason: it is inside its own refused window. `fallbackIp` is
      // often the group's new coordinator, which is frequently one of them.
      final ip = settleReadIp(sys,
          ownerIp: ownerIp, fallbackIp: fallbackIp, unbonding: uuids) ?? _lastIp;
      // POLL, don't settle-read once: the topology lags ~15s and a single 4s
      // read swallows its own error, so the next iteration would act on a
      // system where this speaker is still bonded.
      sys = await _pollUntil(
        previous: sys,
        ip: ip,
        attempts: 6,
        until: (s) => s.ownerOf(u) == null,
      );
      // Read the poll's verdict, but do NOT abort on it. A read that never
      // converges is routine, not evidence the unbond failed: the write very
      // often applied and the topology is simply lagging or refusing (both
      // documented), and the bond write downstream re-asserts until it
      // verifies. Aborting here is the exact regression the retry rule exists
      // to prevent. What was missing is that the real cause only reached the
      // raw log, so a bond that then failed ~110s later surfaced as
      // `bondingIncomplete` with nothing explaining why. Now it's on the
      // timeline.
      if (sys.ownerOf(u) != null) {
        ph.note(l10n.stepFreeUnconfirmed(sys.device(u)?.roomName ?? u));
      }
    }
    return sys;
  }

  /// Members of [uuids] currently bonded into a HOME THEATER, whose room name
  /// is therefore the BAR's, not their own.
  ///
  /// Must be read BEFORE freeing. `RemoveHTSatellite` doesn't restore a
  /// satellite's name and nothing ever captured the original, so a group built
  /// out of one would snapshot the bar's name and a later separate would
  /// rename the speaker into a collision with the live home theater
  /// (`Woonkamer` → `Woonkamer 2`). Better no snapshot than a wrong one.
  Set<String> _htSourced(SonosSystem sys, Iterable<String> uuids) => {
    for (final u in uuids)
      if (sys.memberByUuid(sys.ownerOf(u) ?? '')?.isHomeTheater ?? false) u,
  };

  /// Fails fast when any of [devices] has no IP, so the engine's own guard
  /// (which throws the same error) can't fire AFTER a free has already
  /// dissolved a live bond. Cheap preconditions run before destructive ones.
  void _requireIps(Iterable<SonosDevice> devices) {
    if (devices.any((d) => d.ip == null)) {
      throw const SonorityError(SonorityErrorCode.speakerIpUnknown);
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
      // The coordinator can be a discovery stub with no address (its `Location`
      // went stale, or the topology gave it none). Only the remove step needs
      // guarding — the bond step's `bondAndVerify` raises `coordinatorIpUnknown`
      // itself, and the no-op case above writes nothing and must keep working
      // without one.
      final barIp = bar.ip;
      if (barIp == null) {
        throw SonorityError(SonorityErrorCode.soundbarNotOnNetwork, bar.roomName);
      }
      // Only genuine leaves reach here (a dropped sub / a replaced speaker) —
      // a speaker that merely moves channel stays bonded and reassigns in place.
      ph.phase('remove', l10n.stepRemoveUnused(diff.toRemove.length));
      await _repo.removeHtSatellites(
          soundbarIp: barIp, uuids: diff.toRemove, cancel: _activeOp);
      ph.note(l10n.stepWaitingSettle);
      sys = await _settleRead(sys, barIp);
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
      try {
        // Before anything destructive: the free below DISSOLVES whatever bond a
        // member is in, and `createGroup` rejects a member with no IP, so a
        // speaker recovered from topology alone would have cost the user a live
        // group and then thrown without a single bond write. Inside the TRY, not
        // just the guard: `tracker.start` has already marked the step active, so
        // a throw that skips `tracker.fail` leaves the timeline spinning forever
        // under a red header with the reason only in the snackbar.
        _requireIps([for (final m in members) m.device, if (sub != null) sub]);
        final wanted = name?.trim();
        // Speakers bonded elsewhere must be FREED first: unlike `AddHTSatellite`,
        // which absorbs a speaker straight out of a live pair or zone,
        // `AddBondedZones` is ACCEPTED and silently does nothing when a member is
        // still bonded somewhere else: the group never forms (EXP-23 Q11, two
        // cycles). Freeing clears that bond's room calibration, which is why the
        // picker warns before you get here.
        var sys = previous ?? await _repo.discover();
        // A group target absorbs from nothing (EXP-23 Q11), hence absorbing:false.
        final needsFree = involved
            .any((u) => sys.mustFreeBeforeBonding(u, keep: const {}, absorbing: false));
        ph.seed([
          if (needsFree) ('free', l10n.stepFreeConflicting),
          ('bond', l10n.stepBondSpeakers),
          ('confirm', l10n.stepWaitForConfirm),
          if (wanted != null && wanted.isNotEmpty && coord.ip != null)
            ('name', l10n.stepNameGroup),
        ]);
        final htSourced = _htSourced(sys, involved);
        sys = await _freeConflicts(sys, involved,
            keep: const {}, absorbing: false, ph: ph, fallbackIp: coord.ip);
        ph.phase('bond', l10n.stepBondSpeakers);
        // Writes, verifies and re-asserts until the bond is really there, or
        // throws didNotCreateGroup. Seed from `sys`, not `previous`: the free
        // loop advanced it, and the pre-free topology still shows the members
        // bonded elsewhere.
        var system = await _repo.createGroup(
            members: members,
            sub: sub,
            previous: sys,
            skipNameSnapshot: htSourced,
            onNote: ph.log,
            cancel: _activeOp);
        // The bond is confirmed, but the absorbed members can linger in the
        // room list for a few seconds (the ~15s topology lag). Wait for them
        // to go before adopting the topology, or the overview shows the new
        // group AND stale room cards for its members.
        ph.phase('confirm', l10n.stepWaitForConfirm);
        system = await _pollUntil(
          previous: system,
          ip: coord.ip ?? _lastIp,
          until: (s) => !members
              .skip(1)
              .any((m) => s.allMembers.any((x) => x.uuid == m.device.uuid)),
        );
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
        await _repo.separateGroup(
            members: members,
            channelMapSet: cms,
            // The FULL membership keys the name snapshot; `members` is only the
            // resolved subset to write to.
            snapshotUuids: group.channelMapUuids,
            cancel: _activeOp);
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

  /// Reconfigures an [existing] bonded group to the target [members] (+ optional
  /// [sub] / [name]). Diff-based (hardware-confirmed, `tool/group_reassert_spike`):
  /// if the target keeps every current member and the coordinator is unchanged,
  /// re-asserts the new map IN PLACE (adds + channel changes — no teardown, no
  /// audio interruption); otherwise (a member/sub is dropped, or the coordinator
  /// changes) dissolves the group and recreates it, since `AddBondedZones` faults
  /// on any map that drops a bonded member. Mirrors the HT `_applyHtTarget` split.
  Future<void> editGroup({
    required ZoneGroupMember existing,
    required List<({SonosDevice device, GroupChannel channel})> members,
    SonosDevice? sub,
    String? name,
  }) async {
    final cms = existing.channelMapSet;
    if (members.length < 2 || cms == null || cms.isEmpty) {
      throw const SonorityError(SonorityErrorCode.groupNeedsTwo);
    }
    final coord = members.first.device;
    final target = [
      for (final m in members) m.device.uuid,
      if (sub != null) sub.uuid,
    ];
    final current = existing.channelMapUuids; // coordinator first, incl. any Sub
    final inPlace = groupEditIsInPlace(
      currentUuids: current,
      targetUuids: target,
      targetCoordUuid: coord.uuid,
    );
    // Verify the FULL target applied — per-member channel + Sub, not just the
    // membership set. Critical for an in-place channel reassignment (membership
    // is unchanged, so a set-only check would pass before the write even lands).
    // Coordinator-aware: `AddBondedZones` cannot move the coordinator, so a
    // target that coordinates elsewhere is NOT already applied. It needs the
    // dissolve-and-recreate path, and the flow's Apply gate agrees via
    // `_bondDiffers`.
    bool applied(SonosSystem s) =>
        s.memberByUuid(coord.uuid)?.matchesGroupLayout(
            {for (final m in members) m.device.uuid: m.channel},
            subUuid: sub?.uuid,
            coordUuid: coord.uuid) ??
        false;

    final wanted = name?.trim();
    final needsName = wanted != null && wanted.isNotEmpty && coord.ip != null;

    final previous = state.value;
    // Skip the bond phase entirely when the live layout already matches the
    // target (e.g. a name-only edit) — no needless live write, mirroring the HT
    // `_applyHtTarget` no-op case.
    final needsBond = !(previous != null && applied(previous));
    final l10n = appL10n();
    final tracker =
        _newTracker([ApplyStep(id: 'edit', label: l10n.stepEditGroup)]);
    _activeOp = CancellationToken();

    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('edit');
      final ph = _phases(tracker, 'edit');
      try {
        // Before anything destructive: the free below DISSOLVES whatever bond a
        // taken speaker is in, and the rebuild path dissolves THIS group, so a
        // missing IP has to fail here, not after. An in-place re-assert only
        // writes to the coordinator; a rebuild goes through `separateGroup` +
        // `createGroup`, which need every member's IP AND the OUTGOING
        // coordinator's (it isn't in `members` on a coordinator change, and
        // `separateGroup` throws on its missing IP). Inside the TRY, not just the
        // guard, or `tracker.fail` is skipped and the step spins forever.
        if (needsBond) {
          _requireIps(inPlace
              ? [coord]
              : [
                  for (final m in members) m.device,
                  if (sub != null) sub,
                  if (previous?.device(existing.uuid) case final outgoing?)
                    outgoing,
                ]);
        }
        // A member taken from ANOTHER bond has to be freed first: `AddBondedZones`
        // is accepted and silently no-ops on a speaker bonded elsewhere (EXP-23
        // Q11), and `reassertGroup` would then re-assert: each attempt rebuilding
        // this group and clearing its Trueplay (Q8a), until it gave up. `keep` is
        // the group's own members, so an ordinary edit frees nothing.
        final keepInGroup = {...current, existing.uuid};
        final needsFree = needsBond &&
            previous != null &&
            target.any((u) =>
                previous.mustFreeBeforeBonding(u, keep: keepInGroup, absorbing: false));
        ph.seed([
          if (needsFree) ('free', l10n.stepFreeConflicting),
          if (needsBond && !inPlace) ('separate', l10n.stepSeparateRestore),
          if (needsBond)
            ('bond', inPlace ? l10n.stepUpdateGroup : l10n.stepBondSpeakers),
          if (needsName) ('name', l10n.stepNameGroup),
        ]);
        var system = previous;
        var htSourced = const <String>{};
        if (needsBond && system != null) {
          htSourced = _htSourced(system, target);
          system = await _freeConflicts(system, target,
              keep: keepInGroup, absorbing: false, ph: ph,
              fallbackIp: coord.ip);
        }
        if (needsBond && inPlace) {
          // Adds + channel reassignments apply on the live coordinator.
          // reassertGroup re-asserts until verified (like HT bondAndVerify) — an
          // in-place group re-assert intermittently 800s mid-reshuffle / partial-
          // applies, so a single write is unreliable.
          ph.phase('bond', l10n.stepUpdateGroup);
          system = await _repo.reassertGroup(
            members: members,
            sub: sub,
            currentUuids: current,
            previous: system,
            skipNameSnapshot: htSourced,
            onNote: ph.log,
            cancel: _activeOp,
          );
        } else if (needsBond) {
          // A drop / coordinator change can't be re-asserted — dissolve first.
          final ordered = [
            existing.uuid,
            ...current.where((u) => u != existing.uuid),
          ];
          // `system`, not `previous`: the free loop above may have advanced it.
          final old = ordered
              .map((u) => system?.device(u))
              .whereType<SonosDevice>()
              .toList();
          if (existing.ip != null &&
              system != null &&
              !_isOwnGroupCoordinator(system, existing.uuid)) {
            ph.phase('detach', l10n.stepDetach);
            await _repo.detachFromGroup(existing.ip!);
            system = await _pollUntil(
              previous: system,
              ip: existing.ip,
              attempts: 6,
              until: (s) => _isOwnGroupCoordinator(s, existing.uuid),
            );
          }
          ph.phase('separate', l10n.stepSeparateRestore);
          await _repo.separateGroup(
              members: old,
              channelMapSet: cms,
              snapshotUuids: current,
              cancel: _activeOp);
          // Straight into the rebuild: createGroup re-asserts until the group
          // verifies, so a write that lands mid-dissolve is retried rather than
          // leaving the group torn down. (This is where a settle poll used to
          // paper over createGroup writing exactly once.)
          ph.phase('bond', l10n.stepBondSpeakers);
          system = await _repo.createGroup(
              members: members,
              sub: sub,
              previous: system,
              skipNameSnapshot: htSourced,
              onNote: ph.log,
              cancel: _activeOp);
        }
        if (needsName) {
          ph.phase('name', l10n.stepNameGroup);
          if (await _repo.setRoomName(ip: coord.ip!, name: wanted)) {
            system = await _pollUntil(
              previous: system,
              ip: coord.ip,
              attempts: 6,
              until: (s) => s.allMembers
                  .any((m) => m.uuid == coord.uuid && m.zoneName == wanted),
            );
          }
        }
        tracker.done('edit');
        return system;
      } catch (e) {
        tracker.fail('edit', localizedError(l10n, e));
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
