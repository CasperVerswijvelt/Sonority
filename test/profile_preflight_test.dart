import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/profiles/profile.dart';
import 'package:sonority/features/profiles/profile_controller.dart';

/// Regression: a speaker bonded to the profile entity's OWN coordinator is not
/// a conflict — the apply path no-ops for it, so pre-flight must not report
/// "Will free" (it did, for every satellite / pair half / zone member).
void main() {
  const beam = 'RINCON_BEAM01400';
  const fl = 'RINCON_FL01400';
  const sub = 'RINCON_SUB01400';
  const pairL = 'RINCON_PL01400';
  const pairR = 'RINCON_PR01400';

  SonosDevice dev(String uuid, String name) =>
      SonosDevice(uuid: uuid, roomName: name, modelName: 'x', ip: '1.2.3.4');

  final devices = {
    beam: dev(beam, 'Woonkamer'),
    fl: dev(fl, 'Woonkamer'),
    sub: dev(sub, 'Sub'),
    pairL: dev(pairL, 'Zolder'),
    pairR: dev(pairR, 'Zolder'),
  };

  Profile profileOf(EntitySnapshot e) =>
      Profile(id: 'p', name: 'P', entities: [e]);

  test('already-formed HT: satellites are NOT conflicts', () {
    const map = '$beam:CC;$fl:LF;$sub:SW';
    final system = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: beam, members: [
          ZoneGroupMember(uuid: beam, zoneName: 'Woonkamer', htSatChanMapSet: map),
        ]),
      ],
      devicesByUuid: devices,
    );
    final snap = EntitySnapshot.fromMember(system.groups.first.members.first);
    final issues = preflightProfile(profileOf(snap), system);
    expect(issues.single.conflicts, isEmpty);
    expect(issues.single.blocked, isFalse);
  });

  test('already-formed pair: hidden half is NOT a conflict', () {
    const map = '$pairL:LF,LF;$pairR:RF,RF';
    final system = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: pairL, members: [
          ZoneGroupMember(uuid: pairL, zoneName: 'Zolder', channelMapSet: map),
          const ZoneGroupMember(uuid: pairR, zoneName: 'Zolder', invisible: true),
        ]),
      ],
      devicesByUuid: devices,
    );
    final snap = EntitySnapshot.fromMember(system.groups.first.members.first);
    final issues = preflightProfile(profileOf(snap), system);
    expect(issues.single.conflicts, isEmpty);
  });

  test('speaker bonded to a DIFFERENT entity IS a conflict', () {
    // Profile wants pairL+pairR, but pairR is currently an HT satellite.
    const wantedMap = '$pairL:LF,LF;$pairR:RF,RF';
    final system = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: pairL, members: [
          ZoneGroupMember(uuid: pairL, zoneName: 'Zolder'),
        ]),
        ZoneGroup(coordinatorUuid: beam, members: [
          ZoneGroupMember(
              uuid: beam,
              zoneName: 'Woonkamer',
              htSatChanMapSet: '$beam:CC;$pairR:RF'),
        ]),
      ],
      devicesByUuid: devices,
    );
    const snap = EntitySnapshot(
      kind: EntityKind.stereoPair,
      primaryUuid: pairL,
      mapSet: wantedMap,
      names: {pairL: 'Zolder'},
    );
    final issues = preflightProfile(profileOf(snap), system);
    expect(issues.single.conflicts, [devices[pairR]!.roomName]);
  });
}
