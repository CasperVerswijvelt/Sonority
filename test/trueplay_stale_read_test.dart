import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/state/sonos_controller.dart';
import 'package:sonority/state/trueplay_controller.dart';

/// A re-read that FAULTS must not leave the previous reading behind.
///
/// `tunedCount` gates the destructive-enable confirm, so a stale
/// `available: true` suppresses the dialog that stops a user destroying the
/// tunings that are left. The flows seed the cache before they bond
/// (`loadTrueplayForPickers` reads every device) and bonding closes :1400 on
/// each member for ~20-30s, so the stale value is the value the app just
/// invalidated.
class _FlakyRepo extends SonosRepository {
  /// IPs that refuse the read, as a just-bonded speaker does.
  Set<String> refusing = {};

  /// IPs whose read never returns until the test completes them. Models the
  /// unreachable speaker that sits on the full 8s SOAP timeout.
  final hanging = <String, Completer<void>>{};
  RoomCalibration answer = const RoomCalibration(available: true, enabled: true);

  @override
  Future<RoomCalibration> roomCalibration(String ip) async {
    if (hanging.containsKey(ip)) await hanging[ip]!.future;
    if (refusing.contains(ip)) throw Exception('connection refused');
    return answer;
  }
}

void main() {
  const a = 'RINCON_A01400';
  const b = 'RINCON_B01400';
  const devA = SonosDevice(
      uuid: a, roomName: 'Bar', modelName: 'Sonos Beam', ip: '192.0.2.1');
  const devB = SonosDevice(
      uuid: b, roomName: 'Rear', modelName: 'Sonos One SL', ip: '192.0.2.2');

  ({ProviderContainer container, _FlakyRepo repo}) setup() {
    final repo = _FlakyRepo();
    final container = ProviderContainer(
      overrides: [sonosRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return (container: container, repo: repo);
  }

  test('a faulted re-read drops the speaker instead of keeping it tuned',
      () async {
    final s = setup();
    final tp = s.container.read(trueplayControllerProvider.notifier);

    // Pre-bond: both tuned. This is what a setup flow caches.
    await tp.load([devA, devB]);
    expect(s.container.read(trueplayControllerProvider).byUuid.length, 2);

    // Bond happens; the bar now refuses :1400 for ~20-30s.
    s.repo.refusing = {devA.ip!};
    await tp.load([devA, devB]);

    final byUuid = s.container.read(trueplayControllerProvider).byUuid;
    expect(byUuid.containsKey(a), isFalse,
        reason: 'unknown is honest; a stale "tuned" hides the enable warning');
    expect(byUuid[b]?.available, isTrue, reason: 'the reachable one still reads');
  });

  test('the set therefore reads as INCOMPLETE, which is what warns', () async {
    final s = setup();
    final tp = s.container.read(trueplayControllerProvider.notifier);
    await tp.load([devA, devB]);
    s.repo.refusing = {devA.ip!};
    await tp.load([devA, devB]);

    // What TrueplayControl computes: known ⊂ devices ⇒ tunedCount < total.
    final byUuid = s.container.read(trueplayControllerProvider).byUuid;
    final tuned = [devA, devB]
        .map((d) => byUuid[d.uuid])
        .whereType<RoomCalibration>()
        .where((c) => c.available)
        .length;
    expect(tuned < 2, isTrue,
        reason: 'an incomplete set is what keeps the destructive-enable confirm');
  });

  test('one slow speaker does not hold the others busy', () async {
    // `busy` suppresses every Trueplay cost claim in both setup flows, because
    // a speaker nobody has asked yet must not be described. Cleared as a batch,
    // one unreachable speaker kept the WHOLE household pending for its full
    // timeout, and a review card rendered during that window named nobody at
    // all: the one gate before Apply, silent.
    final s = setup();
    final tp = s.container.read(trueplayControllerProvider.notifier);
    s.repo.hanging[devA.ip!] = Completer<void>();

    final pending = tp.load([devA, devB]);
    await Future<void>.delayed(Duration.zero);

    final state = s.container.read(trueplayControllerProvider);
    expect(state.busy, {a}, reason: 'only the speaker still being read');
    expect(state.byUuid.containsKey(b), isTrue,
        reason: 'B answered, so B is available to be priced');

    s.repo.hanging[devA.ip!]!.complete();
    await pending;
    expect(s.container.read(trueplayControllerProvider).busy, isEmpty);
  });

  test('a speaker that was never asked is untouched', () async {
    final s = setup();
    final tp = s.container.read(trueplayControllerProvider.notifier);
    await tp.load([devA, devB]);
    // Only A is re-read, and it faults. B was not a target.
    s.repo.refusing = {devA.ip!};
    await tp.load([devA]);
    final byUuid = s.container.read(trueplayControllerProvider).byUuid;
    expect(byUuid.containsKey(a), isFalse);
    expect(byUuid.containsKey(b), isTrue,
        reason: 'eviction is scoped to the speakers this read targeted');
  });
}
