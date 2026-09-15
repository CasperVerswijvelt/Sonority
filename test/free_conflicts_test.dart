import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/cancellation.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/state/sonos_controller.dart';

/// `SonosController._freeConflicts` must issue at most ONE destructive write per
/// source bond.
///
/// Freeing a member of a bonded group DISSOLVES the whole group, so its siblings
/// are already free. The settle poll can't be relied on to notice: `_pollUntil`
/// returns its last read whether or not the condition held, and the read it
/// falls back to routinely comes from the coordinator whose bond just changed —
/// i.e. the speaker inside the ~20-30s window where :1400 refuses connections.
/// A stale read then sent a second `SeparateStereoPair` against a map that no
/// longer exists.
const _zoneA = 'RINCON_ZONEA01400';
const _zoneB = 'RINCON_ZONEB01400';

const _devA = SonosDevice(
    uuid: _zoneA, roomName: 'Keuken', modelName: 'Sonos One', ip: '192.0.2.1');
const _devB = SonosDevice(
    uuid: _zoneB, roomName: 'Keuken', modelName: 'Sonos Play:1', ip: '192.0.2.2');

const _zone = ZoneGroupMember(
  uuid: _zoneA,
  zoneName: 'Keuken',
  channelMapSet: '$_zoneA:LF,RF;$_zoneB:LF,RF',
);

const _system = SonosSystem(
  groups: [
    ZoneGroup(coordinatorUuid: _zoneA, members: [_zone]),
  ],
  devicesByUuid: {_zoneA: _devA, _zoneB: _devB},
);

/// The two rooms the zone becomes once it is dissolved.
const _apart = SonosSystem(
  groups: [
    ZoneGroup(coordinatorUuid: _zoneA, members: [
      ZoneGroupMember(uuid: _zoneA, zoneName: 'Keuken'),
      ZoneGroupMember(uuid: _zoneB, zoneName: 'Keuken 2'),
    ]),
  ],
  devicesByUuid: {_zoneA: _devA, _zoneB: _devB},
);

/// [stale] keeps every topology read answering with the LIVE zone, exactly as a
/// stale/refused read does mid-dissolve; [throwOnFree] makes the unbond write
/// fail the way a real one does (8s timeout, or 800 mid-reshuffle) while still
/// having applied.
class _StaleRepo extends SonosRepository {
  final bool stale;
  final Object? throwOnFree;
  final freed = <String>[];
  var created = 0;

  _StaleRepo({this.stale = true, this.throwOnFree});

  @override
  Future<SonosSystem> discover() async => _system;

  @override
  Future<SonosSystem> refresh(SonosSystem previous, String ip) async =>
      stale ? _system : _apart;

  @override
  Future<void> freeSpeaker(SonosSystem system, String uuid,
      {CancellationToken? cancel}) async {
    freed.add(uuid);
    if (throwOnFree != null) throw throwOnFree!;
  }

  @override
  Future<SonosSystem> createGroup({
    required List<({SonosDevice device, GroupChannel channel})> members,
    SonosDevice? sub,
    required SonosSystem? previous,
    Set<String> skipNameSnapshot = const {},
    void Function(String note)? onNote,
    CancellationToken? cancel,
  }) async {
    created++;
    return _apart;
  }
}

void main() {
  /// A stereo pair out of BOTH zone members — the shape that double-freed.
  Future<_StaleRepo> pair(WidgetTester tester, _StaleRepo repo) async {
    final container = ProviderContainer(
      overrides: [sonosRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(sonosControllerProvider.future);

    final done = container.read(sonosControllerProvider.notifier).createGroup(
      members: const [
        (device: _devA, channel: GroupChannel.left),
        (device: _devB, channel: GroupChannel.right),
      ],
    );
    // Drive the fake clock past every settle poll (250ms slices).
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await done;
    return repo;
  }

  testWidgets('both members of one zone are freed by ONE write', (tester) async {
    final repo = await pair(tester, _StaleRepo());
    expect(repo.freed, [_zoneA],
        reason: 'the dissolve freed both; a second write hits a dead map');
  });

  // An unbond is a bond write, so it obeys the same rule as the rest: an 8s
  // timeout very often STILL APPLIED. Aborting the apply here left the source
  // bond a speaker short and the destination untouched, on a write a retry —
  // or just the poll two lines down — would have completed.
  testWidgets('a timed-out free is verified, not treated as failure',
      (tester) async {
    final repo = await pair(tester,
        _StaleRepo(stale: false, throwOnFree: TimeoutException('free')));
    expect(repo.created, 1, reason: 'the apply carried on to the bond');
  });
}
