import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';

/// [SonosSystem.isStandalone] drives whether a speaker can be identified with the
/// audio chime (a standalone speaker plays on its own) vs LED-only (a bonded
/// satellite / group member, or a coordinator whose chime plays the whole bond).
void main() {
  const solo = 'RINCON_SOLO01400';
  const bar = 'RINCON_BAR01400';
  const sat = 'RINCON_SAT01400';
  const pairL = 'RINCON_PL01400';
  const pairR = 'RINCON_PR01400';
  const bareBar = 'RINCON_BAREBAR01400';

  final system = SonosSystem(
    groups: [
      // A standalone speaker.
      ZoneGroup(coordinatorUuid: solo, members: [
        const ZoneGroupMember(uuid: solo, zoneName: 'Kitchen'),
      ]),
      // A home theater: soundbar coordinator + one satellite.
      ZoneGroup(coordinatorUuid: bar, members: [
        ZoneGroupMember(
          uuid: bar,
          zoneName: 'Living',
          htSatChanMapSet: '$bar:CC;$sat:LF',
          satellites: const [
            SonosSatellite(
                uuid: sat, zoneName: 'Living', channels: [SonosChannel.leftFront]),
          ],
        ),
      ]),
      // A stereo pair: visible primary + Invisible secondary.
      ZoneGroup(coordinatorUuid: pairL, members: [
        const ZoneGroupMember(
            uuid: pairL,
            zoneName: 'Office',
            channelMapSet: '$pairL:LF,LF;$pairR:RF,RF'),
        const ZoneGroupMember(
            uuid: pairR,
            zoneName: 'Office',
            invisible: true,
            channelMapSet: '$pairL:LF,LF;$pairR:RF,RF'),
      ]),
      // A bare soundbar (no satellites) still plays on its own → standalone.
      ZoneGroup(coordinatorUuid: bareBar, members: [
        const ZoneGroupMember(uuid: bareBar, zoneName: 'Den'),
      ]),
    ],
    devicesByUuid: const {},
  );

  test('standalone speakers (incl. a bare soundbar) can chime', () {
    expect(system.isStandalone(solo), isTrue);
    expect(system.isStandalone(bareBar), isTrue);
  });

  test('bonded speakers are LED-only', () {
    expect(system.isStandalone(bar), isFalse, reason: 'HT coordinator');
    expect(system.isStandalone(sat), isFalse, reason: 'HT satellite');
    expect(system.isStandalone(pairL), isFalse, reason: 'pair primary');
    expect(system.isStandalone(pairR), isFalse, reason: 'pair secondary');
  });
}
