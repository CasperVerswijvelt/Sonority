import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/apply_progress.dart';
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
}

final applyProgressProvider =
    NotifierProvider<ApplyProgressNotifier, List<ApplyStep>>(
        ApplyProgressNotifier.new);

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
  /// soundbar in a single guided pass — fronts (LF/RF or an Amp on both),
  /// surrounds (LR/RR), and/or a sub (SW). Stages the writes per the Phase 0
  /// finding (surrounds+sub first, then fronts) and emits per-step progress via
  /// [applyProgressProvider] so the UI shows which step is active and exactly
  /// where it failed. Each stage verifies + re-asserts via [bondAndVerify].
  Future<void> applyHomeTheaterLayout({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required Map<SonosChannel, SonosDevice> additions,
  }) async {
    if (additions.isEmpty) return;

    bool isFront(SonosChannel c) =>
        c == SonosChannel.leftFront || c == SonosChannel.rightFront;
    final addsFronts = additions.keys.any(isFront);
    final addsNonFronts = additions.keys.any((c) => !isFront(c));

    // Desired = existing layout overlaid with the new assignments.
    final desired = <SonosChannel, String>{
      ...soundbar.channelAssignments,
      for (final e in additions.entries) e.key: e.value.uuid,
    };

    final progress = ref.read(applyProgressProvider.notifier);
    final tracker = ApplyProgress(
      [
        if (addsNonFronts)
          const ApplyStep(id: 'surrounds', label: 'Bond surrounds & sub'),
        if (addsFronts)
          const ApplyStep(id: 'fronts', label: 'Bond front speakers'),
      ],
      onChange: progress.set,
    );

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      SonosSystem? sys = previous;

      Future<void> stage(String id, Map<SonosChannel, String> roles) async {
        tracker.start(id);
        try {
          sys = await _repo.bondAndVerify(
            coordinator: soundbarDevice,
            target: front_layout.buildLayoutMap(
              soundbar: soundbar,
              soundbarDevice: soundbarDevice,
              desired: roles,
            ),
            previous: sys,
            onNote: (n) => tracker.note(id, n),
          );
          tracker.done(id);
        } catch (e) {
          tracker.fail(id, '$e');
          rethrow;
        }
      }

      // Stage 1: everything except fronts (so satellites settle before fronts
      // are layered on — the order that proved stable on hardware).
      if (addsNonFronts) {
        await stage('surrounds',
            {for (final e in desired.entries) if (!isFront(e.key)) e.key: e.value});
      }
      // Stage 2: the full layout (adds the fronts).
      if (addsFronts) {
        await stage('fronts', desired);
      }
      return sys ?? await _repo.discover();
    });
    state = result;
    if (result.hasError) rethrowLast(result);
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

    final progress = ref.read(applyProgressProvider.notifier);
    final tracker = ApplyProgress(
      [
        for (final e in entities)
          ApplyStep(id: e.primaryUuid, label: '${e.kindLabel}: ${e.label}'),
      ],
      onChange: progress.set,
    );

    final previous = current;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      SonosSystem? sys = previous;
      for (final e in entities) {
        tracker.start(e.primaryUuid);
        try {
          sys = await _applyEntity(e, sys!, (n) => tracker.note(e.primaryUuid, n));
          tracker.done(e.primaryUuid);
        } catch (err) {
          tracker.fail(e.primaryUuid, '$err');
          rethrow;
        }
      }
      return sys ?? await _repo.discover();
    });
    state = result;
    if (result.hasError) rethrowLast(result);
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
        final desired = _channelsOf(map);
        // Free any satellite currently bonded to a different coordinator/pair.
        for (final u in desired.values.toSet()) {
          final owner = _ownerOf(sys, u);
          if (owner != null && owner != bar!.uuid) {
            note('freeing $u');
            await _repo.freeSpeaker(sys, u);
            sys = await _settleRead(sys, bar.ip!);
          }
        }
        // Strip the coordinator to bare first — AddHTSatellite rejects a map that
        // would drop currently-bonded speakers, so a rebuild must start clean.
        final cur = sys.allMembers
            .where((m) => m.uuid == bar!.uuid)
            .cast<ZoneGroupMember?>()
            .firstOrNull;
        if (cur != null && cur.channelAssignments.isNotEmpty) {
          note('clearing current layout');
          await _repo.stripHomeTheater(coordinator: bar!, member: cur);
          sys = await _settleRead(sys, bar.ip!);
        }
        // Re-bond the full saved layout in one converging call. From a bare bar
        // a single full map needs a few re-asserts to settle (Sonos drops then
        // re-accepts satellites mid-reshuffle); bondAndVerify retries through the
        // transient timeouts/UPnPErrors until every channel is present.
        note('bonding ${desired.length} channels');
        final fullTarget = front_layout.buildLayoutMap(
          soundbar: ZoneGroupMember(uuid: bar!.uuid, zoneName: ''),
          soundbarDevice: bar,
          desired: desired,
          preserveExisting: false,
        );
        sys = await _repo.bondAndVerify(
            coordinator: bar, target: fullTarget, previous: sys, onNote: note);
        await _repo.setRoomName(ip: bar.ip!, name: e.names[bar.uuid] ?? bar.roomName);
        return sys;
    }
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

  /// Parses a saved map string into channel → UUID, skipping the CC primary.
  Map<SonosChannel, String> _channelsOf(String mapSet) {
    final out = <SonosChannel, String>{};
    for (final entry in ChannelMap.parse(mapSet).entries.skip(1)) {
      for (final ch in entry.channels) {
        out[ch] = entry.uuid;
      }
    }
    return out;
  }

  Future<SonosSystem> _settleRead(SonosSystem sys, String ip) async {
    await Future<void>.delayed(const Duration(seconds: 4));
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
  }) async {
    final ip = soundbarDevice.ip;
    if (ip == null) throw Exception('Soundbar IP unknown; rescan and retry.');
    final uuids = <String>{
      for (final c in channels)
        if (soundbar.channelAssignments[c] != null) soundbar.channelAssignments[c]!,
    };
    if (uuids.isEmpty) return;

    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await _repo.removeHtSatellites(soundbarIp: ip, uuids: uuids);
      return _pollUntil(
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
    });
    state = result;
    if (result.hasError) rethrowLast(result);
  }

  Future<void> createStereoPair({
    required SonosDevice left,
    required SonosDevice right,
  }) async {
    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await _repo.createStereoPair(left: left, right: right);
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
      return system;
    });
    state = result;
    if (result.hasError) rethrowLast(result);
  }

  Future<void> separateStereoPair({
    required SonosDevice left,
    required SonosDevice right,
  }) async {
    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await _repo.separateStereoPair(left: left, right: right);
      return _pollUntil(
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
    });
    state = result;
    if (result.hasError) rethrowLast(result);
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
      await Future<void>.delayed(interval);
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
}
