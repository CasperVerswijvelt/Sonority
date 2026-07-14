import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/apply_progress.dart';
import '../data/sonos/cancellation.dart';
import '../data/sonos/channel_map.dart';
import '../data/sonos/front_layout.dart' as front_layout;
import '../data/sonos/identify_service.dart';
import '../data/sonos/led_identify.dart';
import '../data/sonos/sonos_repository.dart';
import '../data/sonos/speaker_settings.dart';
import '../features/profiles/profile.dart';
import '../features/profiles/profile_controller.dart'
    show EntityIssue, preflightProfile;

final sonosRepositoryProvider =
    Provider<SonosRepository>((ref) => SonosRepository());

/// Phase emitters for one parent (entity) step — built by
/// `SonosController._phases`, consumed by the apply helpers so each phase
/// becomes a persistent sub-step in the progress timeline instead of an
/// overwriting note.
typedef Phases = ({
  void Function(List<(String, String)>) seed,
  void Function(String id, String label) phase,
  void Function(String) note,
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
        ApplyProgressNotifier.new);

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
        OperationLogNotifier.new);

/// Plays a chime on a speaker to help identify Left vs Right. Holds a local
/// HTTP server, so it's torn down when the provider is disposed.
final identifyServiceProvider = Provider<IdentifyServiceClient>((ref) {
  final service = IdentifyServiceClient(
    null,
    kDebugMode ? (m) => debugPrint('[identify] $m') : null,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Blinks a speaker's status LED to identify it. The default identify action:
/// silent, non-intrusive, and works on every platform (including the sandboxed
/// macOS app, where the chime can't).
final ledIdentifyProvider = Provider<LedIdentifyClient>((ref) {
  return LedIdentifyClient(
    null,
    kDebugMode ? (m) => debugPrint('[led] $m') : null,
  );
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
      List<EntitySnapshot> entities,
      {required bool audio, required bool volume}) async {
    final sys = state.value;
    if (sys == null || (!audio && !volume)) return entities;
    final out = <EntitySnapshot>[];
    for (final e in entities) {
      final map = <String, SpeakerSettings>{};
      for (final uuid in e.involvedUuids) {
        final ip = sys.device(uuid)?.ip;
        if (ip == null) continue;
        final s = await _settings.read(ip, audio: audio, volume: volume);
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
      EntitySnapshot e, SonosSystem sys, Phases ph) async {
    if (e.settings.isEmpty) return;
    ph.phase('settings', 'Restore settings');
    for (final entry in e.settings.entries) {
      _activeOp?.throwIfCancelled();
      final dev = sys.device(entry.key);
      final ip = dev?.ip;
      if (ip == null) {
        ph.note('skipping settings for ${entry.key} — not on the network');
        continue;
      }
      final s = entry.value;
      final what = [
        if (s.hasAudioSettings) 'audio settings',
        if (s.hasVolume) 'volume',
      ].join(' + ');
      ph.note('restoring $what — ${dev!.typeLabel}');
      final failed = await _settings.apply(ip, s);
      if (failed > 0) {
        ph.note('$failed setting(s) for ${dev.typeLabel} could not be applied');
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
    if (state.isLoading) return; // ponytail: single in-flight op; queue only if users hit it
    // The layout IS the target — no `preserveExisting` overlay, so deselected
    // roles drop out and get unbonded. Subs go via [subUuids] (repeatable channel).
    final target = front_layout.buildLayoutMap(
      soundbar: soundbar,
      soundbarDevice: soundbarDevice,
      desired: {for (final e in layout.entries) e.key: e.value.uuid},
      subUuids: [for (final d in subs) d.uuid],
      preserveExisting: false,
    );

    final tracker = _newTracker(
        [const ApplyStep(id: 'bond', label: 'Set up home theater')]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('bond');
      final ph = _phases(tracker, 'bond');
      ph.seed([('bond', 'Bond ${target.entries.length - 1} speakers')]);
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
      } on OperationCancelled {
        rethrow;
      } catch (e) {
        tracker.fail('bond', '$e');
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
  Future<void> applyProfile(Profile profile, {Set<String> skip = const {}}) async {
    if (state.isLoading) return; // ponytail: single in-flight op; queue only if users hit it
    final current = state.value;
    if (current == null) return;
    final entities =
        profile.entities.where((e) => !skip.contains(e.primaryUuid)).toList();
    if (entities.isEmpty) return;

    final tracker = _newTracker([
      for (final e in entities)
        ApplyStep(id: e.primaryUuid, label: '${e.kindLabel}: ${e.label}'),
    ]);
    _activeOp = CancellationToken();

    final previous = current;
    state = const AsyncValue.loading();
    final result =
        await AsyncValue.guard(() => _runEntitySteps(entities, previous, tracker));
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
    final tracker = _newTracker([
      const ApplyStep(id: _scanStepId, label: 'Scan network for Sonos system'),
      for (final e in profile.entities)
        ApplyStep(id: e.primaryUuid, label: '${e.kindLabel}: ${e.label}'),
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
      // (discover()/SSDP isn't interruptible, so scan-abort lands the instant
      // discovery returns — the throwIfCancelled right after.)
      tracker.start(_scanStepId);
      SonosSystem? scanned;
      try {
        if (state.isLoading) {
          scanned = await future;
        } else {
          await scan();
          scanned = state.value;
        }
      } catch (_) {/* handled below */}
      cancel.throwIfCancelled(); // aborted during the scan? stop before any write
      if (scanned == null) {
        tracker.fail(
            _scanStepId, 'Couldn’t find your Sonos system on the network.');
        throw state.error ??
            Exception('Couldn’t find your Sonos system on the network.');
      }
      tracker.done(_scanStepId);

      // Step 2 — pre-flight. If anything's missing/conflicting, confirm before
      // any write (declining aborts cleanly — nothing bonded yet).
      final issues = preflightProfile(profile, scanned);
      final hasIssues =
          issues.any((i) => i.missing.isNotEmpty || i.conflicts.isNotEmpty);
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
          tracker.done(e.primaryUuid,
              detail: 'skipped — $miss not on the network');
        } else {
          applicable.add(e);
        }
      }
      previous = scanned;
    } catch (_) {
      _activeOp = null;
      rethrow;
    }

    // Step 3 — bond the resolvable entities under the same progress timeline
    // (reusing the cancel token set up top so Abort stays wired throughout).
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
        () => _runEntitySteps(applicable, previous, tracker));
    _commit(result, previous);
  }

  static const _scanStepId = '__scan';

  /// One progress step per entity (bond → restore name → restore settings),
  /// failing the step and rethrowing on the first error. Shared by
  /// [applyProfile] and [scanAndApplyProfile]; [sys] is the current live system.
  Future<SonosSystem> _runEntitySteps(
      List<EntitySnapshot> entities, SonosSystem sys, ApplyProgress tracker) async {
    for (final e in entities) {
      _activeOp?.throwIfCancelled(); // abort before starting the next entity
      tracker.start(e.primaryUuid);
      final ph = _phases(tracker, e.primaryUuid);
      // Pre-list the phases knowable from the snapshot; conditional ones
      // (freeing conflicts, removing changed satellites) pop in when needed.
      ph.seed([
        if (e.kind == EntityKind.homeTheater)
          ('bond', 'Bond ${e.involvedUuids.length - 1} speakers')
        else if (e.kind != EntityKind.single)
          ('bond', 'Bond ${e.involvedUuids.length} speakers'),
        ('names', 'Restore room name'),
        if (e.settings.isNotEmpty) ('settings', 'Restore settings'),
      ]);
      try {
        sys = await _applyEntity(e, sys, ph);
        // Restore captured EQ/volume last — bonding can reset EQ.
        await _restoreSettings(e, sys, ph);
        tracker.done(e.primaryUuid);
      } on OperationCancelled {
        rethrow;
      } catch (err) {
        tracker.fail(e.primaryUuid, '$err');
        rethrow;
      }
    }
    return sys;
  }

  Future<SonosSystem> _applyEntity(
      EntitySnapshot e, SonosSystem sys, Phases ph) async {
    switch (e.kind) {
      case EntityKind.single:
        final dev = sys.device(e.primaryUuid);
        if (dev?.ip == null) {
          throw Exception('“${e.label}” isn’t on the network.');
        }
        if (sys.ownerOf(e.primaryUuid) != null) {
          _activeOp?.throwIfCancelled();
          ph.phase('free', 'Free from its current bond');
          await _repo.freeSpeaker(sys, e.primaryUuid);
          ph.note('waiting for Sonos to settle');
          sys = await _settleRead(sys, dev!.ip!);
        }
        _activeOp?.throwIfCancelled();
        ph.phase('names', 'Restore room name');
        if (!await _repo.setRoomName(
            ip: dev!.ip!, name: e.names[e.primaryUuid] ?? dev.roomName)) {
          ph.skipPhase(detail: 'name unchanged — nothing to do');
        }
        return sys;

      // Stereo pair / zone / custom all share one channel-map bond path.
      case EntityKind.stereoPair || EntityKind.zone || EntityKind.custom:
        final map = e.mapSet;
        if (map == null) throw Exception('Stored group is malformed.');
        final coord = sys.device(e.primaryUuid);
        if (coord?.ip == null) {
          throw Exception('“${e.label}” coordinator isn’t on the network.');
        }
        final involved = e.involvedUuids.toList();
        // Already exactly this group? Just re-assert the name (no disruptive write).
        if (_isGroupFormed(sys, e.primaryUuid, involved)) {
          ph.phase('bond', 'Bond ${involved.length} speakers');
          ph.skipPhase(detail: 'already formed — nothing to do');
          _activeOp?.throwIfCancelled();
          ph.phase('names', 'Restore room name');
          if (!await _repo.setRoomName(
              ip: coord!.ip!, name: e.names[coord.uuid] ?? coord.roomName)) {
            ph.skipPhase(detail: 'name unchanged — nothing to do');
          }
          return sys;
        }
        // Free any member currently bonded outside this group.
        for (final u in involved) {
          final owner = sys.ownerOf(u);
          if (owner != null && !involved.contains(owner)) {
            _activeOp?.throwIfCancelled();
            ph.phase('free', 'Free conflicting speakers');
            ph.note('freeing ${sys.device(u)?.roomName ?? u}');
            await _repo.freeSpeaker(sys, u);
            sys = await _settleRead(sys, coord!.ip!);
          }
        }
        // Resolve members (coordinator-first) + sub from the stored map.
        final parsed =
            ZoneGroupMember(uuid: e.primaryUuid, zoneName: '', channelMapSet: map);
        final memberEntries = <({SonosDevice device, GroupChannel channel})>[];
        for (final entry in parsed.groupChannels.entries) {
          final d = sys.device(entry.key);
          if (d?.ip == null) {
            throw Exception('A speaker in “${e.label}” isn’t on the network.');
          }
          memberEntries.add((device: d!, channel: entry.value));
        }
        final subU = parsed.subUuid;
        final sub = subU == null ? null : sys.device(subU);
        if (subU != null && sub?.ip == null) {
          throw Exception('The Sub for “${e.label}” isn’t on the network.');
        }
        if (memberEntries.length < 2) {
          throw Exception('“${e.label}” is missing speakers.');
        }
        _activeOp?.throwIfCancelled();
        ph.phase('bond',
            'Bond ${memberEntries.length} speakers${sub != null ? ' + sub' : ''}');
        await _repo.createGroup(members: memberEntries, sub: sub);
        ph.note('waiting for Sonos to confirm');
        sys = await _pollUntil(
          previous: sys,
          ip: coord!.ip,
          attempts: 8,
          until: (s) => _isGroupFormed(s, e.primaryUuid, involved),
        );
        if (!_isGroupFormed(sys, e.primaryUuid, involved)) {
          throw Exception('Sonos did not form “${e.label}”.');
        }
        _activeOp?.throwIfCancelled();
        ph.phase('names', 'Restore room name');
        if (!await _repo.setRoomName(
            ip: coord.ip!, name: e.names[coord.uuid] ?? coord.roomName)) {
          ph.skipPhase(detail: 'name unchanged — nothing to do');
        }
        return sys;

      case EntityKind.homeTheater:
        final bar = sys.device(e.primaryUuid);
        if (bar?.ip == null) {
          throw Exception('Soundbar for “${e.label}” isn’t on the network.');
        }
        final map = e.mapSet;
        if (map == null) throw Exception('Stored home theater is malformed.');
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
            ph.phase('free', 'Free conflicting speakers');
            ph.note('freeing ${sys.device(u)?.roomName ?? u}');
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
        final cur = sys.allMembers
            .where((m) => m.uuid == bar!.uuid)
            .cast<ZoneGroupMember?>()
            .firstOrNull;
        sys = await _applyHtTarget(
          bar: bar!,
          current: cur ?? ZoneGroupMember(uuid: bar.uuid, zoneName: e.label),
          target: fullTarget,
          sys: sys,
          ph: ph,
        );
        _activeOp?.throwIfCancelled();
        ph.phase('names', 'Restore room name');
        if (!await _repo.setRoomName(
            ip: bar.ip!, name: e.names[bar.uuid] ?? bar.roomName)) {
          ph.skipPhase(detail: 'name unchanged — nothing to do');
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
    final diff = front_layout.diffHtLayout(current: current, target: target);
    final bondLabel = 'Bond ${target.entries.length - 1} speakers';
    if (diff.isNoOp) {
      ph.phase('bond', bondLabel);
      ph.skipPhase(detail: 'layout unchanged — nothing to do');
      return sys;
    }
    if (diff.toRemove.isNotEmpty) {
      ph.phase('remove', 'Remove ${diff.toRemove.length} changed speakers');
      await _repo.removeHtSatellites(
          soundbarIp: bar.ip!, uuids: diff.toRemove, cancel: _activeOp);
      ph.note('waiting for Sonos to settle');
      sys = await _settleRead(sys, bar.ip!);
    }
    ph.phase('bond', bondLabel);
    return _repo.bondAndVerify(
        coordinator: bar,
        target: target,
        previous: sys,
        onNote: ph.note,
        cancel: _activeOp);
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
    if (ip == null) throw Exception('Speaker IP unknown; rescan and retry.');
    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await _repo.setRoomName(ip: ip, name: name);
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
            e.key: e.key == device.uuid ? e.value.copyWith(roomName: name) : e.value
        };
        system = SonosSystem(groups: system.groups, devicesByUuid: patched);
      }
      return system;
    });
    state = result;
    if (result.hasError) rethrowLast(result);
  }

  /// Unbonds the satellites occupying [channels] (e.g. {LF,RF} fronts, {LR,RR}
  /// surrounds, {SW} sub) from the soundbar, polling until those channels are
  /// gone. UUIDs come from the authoritative `channelAssignments`.
  Future<void> removeHtRoles({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required Set<SonosChannel> channels,
    String label = 'speakers',
  }) async {
    final ip = soundbarDevice.ip;
    if (ip == null) throw Exception('Soundbar IP unknown; rescan and retry.');
    final uuids = <String>{
      for (final c in channels) ...soundbar.uuidsForChannel(c),
    };
    if (uuids.isEmpty) return;

    final tracker = _newTracker([ApplyStep(id: 'remove', label: 'Remove $label')]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('remove');
      final ph = _phases(tracker, 'remove');
      ph.seed([
        ('unbond', 'Unbond ${uuids.length} speaker(s)'),
        ('settle', 'Wait for Sonos to settle'),
      ]);
      try {
        ph.phase('unbond', 'Unbond ${uuids.length} speaker(s)');
        await _repo.removeHtSatellites(
            soundbarIp: ip, uuids: uuids, cancel: _activeOp);
        ph.phase('settle', 'Wait for Sonos to settle');
        // The soundbar itself always survives an unbond; a null member here is
        // the transient mid-reshuffle drop-out, NOT confirmation — keep polling.
        bool rolesGone(SonosSystem s) {
          final m = s.allMembers
              .where((x) => x.uuid == soundbar.uuid)
              .cast<ZoneGroupMember?>()
              .firstOrNull;
          if (m == null) return false;
          return channels.every((c) => !m.channelAssignments.containsKey(c));
        }

        final sys = await _pollUntil(previous: previous, ip: ip, until: rolesGone);
        // Sonos can 200-OK an unbond yet silently no-op — re-assert before done.
        if (!rolesGone(sys)) {
          throw Exception('Sonos did not remove the $label — try again.');
        }
        tracker.done('remove');
        return sys;
      } on OperationCancelled {
        rethrow;
      } catch (e) {
        tracker.fail('remove', '$e');
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
    assert(members.length >= 2, 'createGroup needs ≥2 members (UI must gate this)');
    if (members.length < 2) {
      throw Exception('A group needs at least 2 speakers.');
    }
    final coord = members.first.device;
    final involved = [
      for (final m in members) m.device.uuid,
      if (sub != null) sub.uuid,
    ];

    final tracker = _newTracker([
      ApplyStep(id: 'group', label: 'Create group (${members.length} speakers)'),
    ]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('group');
      final ph = _phases(tracker, 'group');
      final wanted = name?.trim();
      ph.seed([
        ('bond', 'Bond speakers'),
        ('confirm', 'Wait for Sonos to confirm'),
        if (wanted != null && wanted.isNotEmpty && coord.ip != null)
          ('name', 'Name the group'),
      ]);
      try {
        ph.phase('bond', 'Bond speakers');
        await _repo.createGroup(members: members, sub: sub);
        ph.phase('confirm', 'Wait for Sonos to confirm');
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
          throw Exception(
              'Sonos did not create the group — a speaker may be incompatible.');
        }
        if (wanted != null && wanted.isNotEmpty && coord.ip != null) {
          ph.phase('name', 'Name the group');
          await _repo.setRoomName(ip: coord.ip!, name: wanted);
          system = await _pollUntil(
            previous: system,
            ip: coord.ip,
            attempts: 6,
            until: (s) => s.allMembers
                .any((m) => m.uuid == coord.uuid && m.zoneName == wanted),
          );
        }
        tracker.done('group');
        return system;
      } on OperationCancelled {
        rethrow;
      } catch (e) {
        tracker.fail('group', '$e');
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
    final members =
        ordered.map((u) => sys.device(u)).whereType<SonosDevice>().toList();
    if (members.isEmpty) return;
    final coord = members.first;
    final involved = group.channelMapUuids;
    final subU = group.subUuid;
    // Audio members reappear as rooms after separation; a Sub stays Invisible.
    final audioReappear =
        members.where((m) => m.uuid != coord.uuid && m.uuid != subU);

    final tracker =
        _newTracker([const ApplyStep(id: 'ungroup', label: 'Separate group')]);
    _activeOp = CancellationToken();

    final previous = sys;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('ungroup');
      final ph = _phases(tracker, 'ungroup');
      ph.seed([
        ('separate', 'Separate + restore room names'),
        ('settle', 'Wait for Sonos to settle'),
      ]);
      try {
        // 1. A bond can't be dissolved while the coordinator is a non-coordinator
        //    member of a larger playback group — detach into its own group first.
        if (coord.ip != null && !_isStandalone(previous, coord.uuid)) {
          ph.phase('detach', 'Detach from playback group');
          await _repo.detachFromGroup(coord.ip!);
          await _pollUntil(
            previous: previous,
            ip: coord.ip,
            attempts: 6,
            until: (s) => _isStandalone(s, coord.uuid),
          );
        }
        // 2. Dissolve (SeparateStereoPair on the live map) + restore names.
        ph.phase('separate', 'Separate + restore room names');
        await _repo.separateGroup(members: members, channelMapSet: cms);
        ph.phase('settle', 'Wait for Sonos to settle');
        final system = await _pollUntil(
          previous: previous,
          ip: coord.ip ?? _lastIp,
          attempts: 8,
          until: (s) =>
              !_isGroupFormed(s, coord.uuid, involved) &&
              audioReappear.every((m) => s.allMembers.any((x) => x.uuid == m.uuid)),
        );
        if (_isGroupFormed(system, coord.uuid, involved)) {
          throw Exception('Sonos did not separate the group — try again.');
        }
        tracker.done('ungroup');
        return system;
      } on OperationCancelled {
        rethrow;
      } catch (e) {
        tracker.fail('ungroup', '$e');
        rethrow;
      }
    });
    _commit(result, previous);
  }

  /// True when [uuid] is its own playback-group coordinator (standalone group).
  bool _isStandalone(SonosSystem system, String uuid) {
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
    final m = system.allMembers
        .where((x) => x.uuid == coordUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
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

  /// Surfaces the error to the caller (so the UI can show a SnackBar) while
  /// keeping it in `state` for inline display.
  void rethrowLast(AsyncValue<SonosSystem?> result) {
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
        onLog: ref.read(operationLogProvider.notifier).add,
      );

  /// Phase emitters bound to one parent (entity) step, so call sites don't
  /// thread the parent id: [seed] pre-lists the phases knowable upfront as
  /// pending sub-steps, [phase] begins one (seeded or conditional), [note]
  /// streams verbose progress to the active phase's subtitle, and [skipPhase]
  /// marks the active phase as a no-op (short-circuits like "layout
  /// unchanged"). Child ids are prefixed with the parent id to stay unique in
  /// the flat step list.
  Phases _phases(ApplyProgress t, String parentId) => (
        seed: (subs) => t.seedSubs(parentId,
            [for (final (id, label) in subs) ('$parentId/$id', label)]),
        phase: (id, label) => t.startSub(parentId, '$parentId/$id', label),
        note: t.noteActive,
        skipPhase: t.skipSub,
      );

  /// Finalizes a bonding op's [result] against the pre-op [previous] state.
  /// A user **abort** is not an error: restore `state` to the last-known system
  /// (the live layout may be mid-change — that's the warned-about case) and
  /// rethrow [OperationCancelled] so the progress screen can close. Otherwise
  /// behaves like the old `state = result; if (hasError) rethrowLast(result)`.
  void _commit(AsyncValue<SonosSystem?> result, SonosSystem? previous) {
    _activeOp = null;
    if (result.error is OperationCancelled) {
      state = AsyncData(previous);
      throw const OperationCancelled();
    }
    state = result;
    if (result.hasError) rethrowLast(result);
  }
}
