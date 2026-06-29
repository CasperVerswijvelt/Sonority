import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/apply_progress.dart';
import '../data/sonos/front_layout.dart' as front_layout;
import '../data/sonos/identify_service.dart';
import '../data/sonos/led_identify.dart';
import '../data/sonos/sonos_repository.dart';

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

  Future<void> removeDedicatedFronts({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
  }) async {
    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await _repo.removeDedicatedFronts(
        soundbar: soundbar,
        soundbarDevice: soundbarDevice,
      );
      return _pollUntil(
        previous: previous,
        ip: soundbarDevice.ip ?? _lastIp,
        until: (s) => _memberHasFronts(s, soundbar.uuid, expected: false),
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

  bool _memberHasFronts(SonosSystem system, String uuid,
      {required bool expected}) {
    final member = system.allMembers
        .where((m) => m.uuid == uuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    if (member == null) return false;
    return member.hasDedicatedFronts == expected;
  }

  /// Surfaces the error to the caller (so the UI can show a SnackBar) while
  /// keeping it in `state` for inline display.
  void rethrowLast(AsyncValue<SonosSystem?> result) {
    final err = result.error;
    if (err != null) throw err;
  }
}
