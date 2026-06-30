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
/// `null` data == not scanned yet; `AsyncLoading` == working; `AsyncError`
/// surfaces a message to the UI.
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
  Future<SonosSystem?> build() async => null;

  SonosRepository get _repo => ref.read(sonosRepositoryProvider);

  Future<void> scan() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final system = await _repo.discover();
      _lastIp = system.devicesByUuid.values
          .map((d) => d.ip)
          .firstWhere((ip) => ip != null, orElse: () => null);
      return system;
    });
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

  /// Bonds one or more roles ([additions]: channel → speaker) onto the
  /// soundbar — fronts (LF/RF or an Amp on both), surrounds (LR/RR), and/or a
  /// sub (SW). Overlays the additions on the existing layout and applies the
  /// diff via [_applyHtTarget] (additive bond, no strip), emitting per-step
  /// progress via [applyProgressProvider].
  Future<void> applyHomeTheaterLayout({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required Map<SonosChannel, SonosDevice> additions,
  }) async {
    if (additions.isEmpty) return;

    // Existing layout overlaid with the new assignments → the full target map.
    final target = front_layout.buildLayoutMap(
      soundbar: soundbar,
      soundbarDevice: soundbarDevice,
      desired: {
        ...soundbar.channelAssignments,
        for (final e in additions.entries) e.key: e.value.uuid,
      },
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
        if (_ownerOf(sys, e.primaryUuid) != null) {
          note('freeing from its current bond');
          await _repo.freeSpeaker(sys, e.primaryUuid);
          sys = await _settleRead(sys, dev!.ip!);
        }
        await _repo.setRoomName(ip: dev!.ip!, name: e.names[e.primaryUuid] ?? dev.roomName);
        return sys;

      case EntityKind.stereoPair:
        final uuids = e.involvedUuids.toList();
        if (uuids.length != 2) throw Exception('Stored pair is malformed.');
        final left = sys.device(uuids[0]);
        final right = sys.device(uuids[1]);
        if (left?.ip == null || right?.ip == null) {
          throw Exception('A paired speaker isn’t on the network.');
        }
        for (final u in uuids) {
          if (_ownerOf(sys, u) != null && _ownerOf(sys, u) != uuids[0]) {
            await _repo.freeSpeaker(sys, u);
            sys = await _settleRead(sys, left!.ip!);
          }
        }
        await _repo.createStereoPair(left: left!, right: right!);
        sys = await _pollUntil(
          previous: sys,
          ip: left.ip,
          attempts: 8,
          until: (s) => _isPaired(s, left.uuid, right.uuid),
        );
        if (!_isPaired(sys, left.uuid, right.uuid)) {
          throw Exception('Sonos did not pair “${e.label}”.');
        }
        await _repo.setRoomName(ip: left.ip!, name: e.names[left.uuid] ?? left.roomName);
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
          final owner = _ownerOf(sys, u);
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

  /// The coordinator/pair-primary UUID that currently owns [uuid] as a bonded
  /// member, or null if it's standalone.
  String? _ownerOf(SonosSystem sys, String uuid) {
    for (final g in sys.groups) {
      for (final m in g.members) {
        if (m.uuid != uuid &&
            (m.channelAssignments.values.contains(uuid) ||
                m.satellites.any((s) => s.uuid == uuid))) {
          return m.uuid;
        }
        if (m.isStereoPair && m.stereoPairUuids.contains(uuid)) {
          return m.stereoPairUuids.first;
        }
      }
    }
    return null;
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

  Future<void> createStereoPair({
    required SonosDevice left,
    required SonosDevice right,
  }) async {
    final tracker = _newTracker([
      ApplyStep(id: 'pair', label: 'Pair ${left.roomName} + ${right.roomName}'),
    ]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('pair');
      try {
        tracker.note('pair', 'creating stereo pair');
        await _repo.createStereoPair(left: left, right: right);
        tracker.note('pair', 'waiting for Sonos to confirm the pair');
        final system = await _pollUntil(
          previous: previous,
          ip: left.ip ?? _lastIp,
          attempts: 8,
          // Paired AND the right speaker has gone Invisible (left the room list);
          // its Invisible flag lags the pair forming by a few seconds.
          until: (s) =>
              _isPaired(s, left.uuid, right.uuid) &&
              !s.allMembers.any((m) => m.uuid == right.uuid),
        );
        // Sonos accepts the command (200) but silently no-ops incompatible pairs.
        if (!_isPaired(system, left.uuid, right.uuid)) {
          throw Exception(
              'Sonos did not pair these speakers — they may be incompatible.');
        }
        tracker.done('pair');
        return system;
      } on OperationCancelled {
        rethrow;
      } catch (e) {
        tracker.fail('pair', '$e');
        rethrow;
      }
    });
    _commit(result, previous);
  }

  Future<void> separateStereoPair({
    required SonosDevice left,
    required SonosDevice right,
  }) async {
    final tracker =
        _newTracker([const ApplyStep(id: 'separate', label: 'Separate stereo pair')]);
    _activeOp = CancellationToken();

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      tracker.start('separate');
      try {
        tracker.note('separate', 'separating + restoring room names');
        await _repo.separateStereoPair(left: left, right: right);
        tracker.note('separate', 'waiting for Sonos to settle');
        final sys = await _pollUntil(
          previous: previous,
          ip: left.ip ?? _lastIp,
          attempts: 8,
          // Wait for not-paired AND the right speaker's restored name to
          // propagate (it briefly keeps the pair name until topology catches up).
          until: (s) {
            if (_isPaired(s, left.uuid, right.uuid)) return false;
            final r = s.allMembers
                .where((m) => m.uuid == right.uuid)
                .cast<ZoneGroupMember?>()
                .firstOrNull;
            return r != null && r.zoneName != left.roomName;
          },
        );
        tracker.done('separate');
        return sys;
      } on OperationCancelled {
        rethrow;
      } catch (e) {
        tracker.fail('separate', '$e');
        rethrow;
      }
    });
    _commit(result, previous);
  }

  bool _isPaired(SonosSystem system, String leftUuid, String rightUuid) {
    for (final p in system.stereoPairs) {
      final uuids = p.stereoPairUuids.toSet();
      if (uuids.contains(leftUuid) && uuids.contains(rightUuid)) return true;
    }
    return false;
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
