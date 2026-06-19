import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/identify_service.dart';
import '../data/sonos/sonos_repository.dart';

final sonosRepositoryProvider =
    Provider<SonosRepository>((ref) => SonosRepository());

/// Plays a chime on a speaker to help identify Left vs Right. Holds a local
/// HTTP server, so it's torn down when the provider is disposed.
final identifyServiceProvider = Provider<IdentifyService>((ref) {
  final service = IdentifyService();
  ref.onDispose(service.dispose);
  return service;
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

  Future<void> applyDedicatedFronts({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required SonosDevice leftSpeaker,
    required SonosDevice rightSpeaker,
  }) async {
    final previous = state.value;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await _repo.applyDedicatedFronts(
        soundbar: soundbar,
        soundbarDevice: soundbarDevice,
        leftSpeaker: leftSpeaker,
        rightSpeaker: rightSpeaker,
      );
      return _pollUntil(
        previous: previous,
        ip: soundbarDevice.ip ?? _lastIp,
        until: (s) => _memberHasFronts(s, soundbar.uuid, expected: true),
      );
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
        until: (s) => _isPaired(s, left.uuid, right.uuid),
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
        until: (s) => !_isPaired(s, left.uuid, right.uuid),
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
