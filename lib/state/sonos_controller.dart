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
import '../features/profiles/profile.dart';

final sonosRepositoryProvider =
    Provider<SonosRepository>((ref) => SonosRepository());

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
final identifyServiceProvider = Provider<IdentifyService>((ref) {
  final service = IdentifyService(
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
      try {
        final sys = await _applyHtTarget(
          bar: soundbarDevice,
          current: soundbar,
          target: target,
          sys: previous ?? await _repo.discover(),
          note: (n) => tracker.note('bond', n),
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
    final result = await AsyncValue.guard(() async {
      SonosSystem? sys = previous;
      for (final e in entities) {
        tracker.start(e.primaryUuid);
        try {
          sys = await _applyEntity(e, sys!, (n) => tracker.note(e.primaryUuid, n));
          tracker.done(e.primaryUuid);
        } on OperationCancelled {
          rethrow;
        } catch (err) {
          tracker.fail(e.primaryUuid, '$err');
          rethrow;
        }
      }
      return sys ?? await _repo.discover();
    });
    _commit(result, previous);
  }

  Future<SonosSystem> _applyEntity(
      EntitySnapshot e, SonosSystem sys, void Function(String) note) async {
    switch (e.kind) {
      case EntityKind.single:
        final dev = sys.device(e.primaryUuid);
        if (dev?.ip == null) {
          throw Exception('“${e.label}” isn’t on the network.');
        }
        if (sys.ownerOf(e.primaryUuid) != null) {
          note('freeing from its current bond');
          await _repo.freeSpeaker(sys, e.primaryUuid);
          sys = await _settleRead(sys, dev!.ip!);
        }
        await _repo.setRoomName(ip: dev!.ip!, name: e.names[e.primaryUuid] ?? dev.roomName);
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
          await _repo.setRoomName(
              ip: coord!.ip!, name: e.names[coord.uuid] ?? coord.roomName);
          return sys;
        }
        // Free any member currently bonded outside this group.
        for (final u in involved) {
          final owner = sys.ownerOf(u);
          if (owner != null && !involved.contains(owner)) {
            note('freeing $u');
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
        note('bonding ${memberEntries.length} speakers${sub != null ? ' + sub' : ''}');
        await _repo.createGroup(members: memberEntries, sub: sub);
        sys = await _pollUntil(
          previous: sys,
          ip: coord!.ip,
          attempts: 8,
          until: (s) => _isGroupFormed(s, e.primaryUuid, involved),
        );
        if (!_isGroupFormed(sys, e.primaryUuid, involved)) {
          throw Exception('Sonos did not form “${e.label}”.');
        }
        await _repo.setRoomName(
            ip: coord.ip!, name: e.names[coord.uuid] ?? coord.roomName);
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
            note('freeing $u');
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
          note: note,
        );
        await _repo.setRoomName(ip: bar.ip!, name: e.names[bar.uuid] ?? bar.roomName);
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
    required void Function(String) note,
  }) async {
    final diff = front_layout.diffHtLayout(current: current, target: target);
    if (diff.isNoOp) {
      note('layout unchanged — nothing to do');
      return sys;
    }
    if (diff.toRemove.isNotEmpty) {
      note('removing ${diff.toRemove.length} changed speakers');
      await _repo.removeHtSatellites(
          soundbarIp: bar.ip!, uuids: diff.toRemove, cancel: _activeOp);
      sys = await _settleRead(sys, bar.ip!);
    }
    note('bonding ${target.entries.length - 1} speakers');
    return _repo.bondAndVerify(
        coordinator: bar,
        target: target,
        previous: sys,
        onNote: note,
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
      var system = await _pollUntil(
        previous: previous,
        ip: ip,
        attempts: 8,
        until: (s) => s.allMembers.any((m) => m.uuid == device.uuid && m.zoneName == name),
      );
      // refresh() reuses the prior device index, so patch the renamed device so
      // its roomName isn't stale until the next full scan.
      final patched = {
        for (final e in system.devicesByUuid.entries)
          e.key: e.key == device.uuid ? e.value.copyWith(roomName: name) : e.value
      };
      system = SonosSystem(groups: system.groups, devicesByUuid: patched);
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
      try {
        tracker.note('remove', 'unbonding ${uuids.length} speaker(s)');
        await _repo.removeHtSatellites(
            soundbarIp: ip, uuids: uuids, cancel: _activeOp);
        tracker.note('remove', 'waiting for Sonos to settle');
        final sys = await _pollUntil(
          previous: previous,
          ip: ip,
          until: (s) {
            final m = s.allMembers
                .where((x) => x.uuid == soundbar.uuid)
                .cast<ZoneGroupMember?>()
                .firstOrNull;
            if (m == null) return true;
            return channels.every((c) => !m.channelAssignments.containsKey(c));
          },
        );
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
    if (members.length < 2) return;
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
      try {
        tracker.note('group', 'bonding speakers');
        await _repo.createGroup(members: members, sub: sub);
        tracker.note('group', 'waiting for Sonos to confirm');
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
        final wanted = name?.trim();
        if (wanted != null && wanted.isNotEmpty && coord.ip != null) {
          tracker.note('group', 'naming the group');
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
      try {
        // 1. A bond can't be dissolved while the coordinator is a non-coordinator
        //    member of a larger playback group — detach into its own group first.
        if (coord.ip != null && !_isStandalone(previous, coord.uuid)) {
          tracker.note('ungroup', 'detaching from playback group');
          await _repo.detachFromGroup(coord.ip!);
          await _pollUntil(
            previous: previous,
            ip: coord.ip,
            attempts: 6,
            until: (s) => _isStandalone(s, coord.uuid),
          );
        }
        // 2. Dissolve (SeparateStereoPair on the live map) + restore names.
        tracker.note('ungroup', 'separating + restoring room names');
        await _repo.separateGroup(members: members, channelMapSet: cms);
        tracker.note('ungroup', 'waiting for Sonos to settle');
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
