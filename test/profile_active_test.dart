import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/profiles/profile.dart';
import 'package:sonority/features/profiles/profile_controller.dart';

/// `profileIsActive` — does the live system already carry this snapshot? Layout
/// + room name only (EQ/volume needs SOAP reads), and channel-aware for groups.
void main() {
  const beam = 'RINCON_BEAM01400';
  const fl = 'RINCON_FL01400';
  const fr = 'RINCON_FR01400';
  const sub = 'RINCON_SUB01400';
  const pairL = 'RINCON_PL01400';
  const pairR = 'RINCON_PR01400';
  const kitchen = 'RINCON_KIT01400';

  SonosDevice dev(String uuid, String name) =>
      SonosDevice(uuid: uuid, roomName: name, modelName: 'x', ip: '1.2.3.4');

  final devices = {
    for (final e in {
      beam: 'Living room',
      fl: 'Living room',
      fr: 'Living room',
      sub: 'Sub',
      pairL: 'Office',
      pairR: 'Office',
      kitchen: 'Kitchen',
    }.entries)
      e.key: dev(e.key, e.value),
  };

  SonosSystem systemOf(List<ZoneGroupMember> members) => SonosSystem(
        groups: [
          for (final m in members)
            ZoneGroup(coordinatorUuid: m.uuid, members: [m]),
        ],
        devicesByUuid: devices,
      );

  Profile profileOf(List<EntitySnapshot> e) =>
      Profile(id: 'p', name: 'P', entities: e);

  const htMap = '$beam:CC;$fl:LF;$fr:RF;$sub:SW';
  const liveHt =
      ZoneGroupMember(uuid: beam, zoneName: 'Living room', htSatChanMapSet: htMap);
  const pairMap = '$pairL:LF,LF;$pairR:RF,RF';
  const livePair =
      ZoneGroupMember(uuid: pairL, zoneName: 'Office', channelMapSet: pairMap);
  const liveKitchen = ZoneGroupMember(uuid: kitchen, zoneName: 'Kitchen');

  test('a snapshot of the live system is active', () {
    final system = systemOf([liveHt, livePair, liveKitchen]);
    final profile = profileOf([
      for (final m in system.allMembers) EntitySnapshot.fromMember(m),
    ]);
    expect(profileIsActive(profile, system), isTrue);
  });

  test('a moved HT satellite is not active', () {
    final snap = EntitySnapshot.fromMember(liveHt);
    // Same speakers, but fl now plays the left REAR.
    final system = systemOf([
      const ZoneGroupMember(
          uuid: beam,
          zoneName: 'Living room',
          htSatChanMapSet: '$beam:CC;$fl:LR;$fr:RF;$sub:SW'),
    ]);
    expect(profileIsActive(profileOf([snap]), system), isFalse);
  });

  test('a dropped HT sub is not active', () {
    final snap = EntitySnapshot.fromMember(liveHt);
    final system = systemOf([
      const ZoneGroupMember(
          uuid: beam,
          zoneName: 'Living room',
          htSatChanMapSet: '$beam:CC;$fl:LF;$fr:RF'),
    ]);
    expect(profileIsActive(profileOf([snap]), system), isFalse);
  });

  test('same group members on swapped channels are NOT active', () {
    final snap = EntitySnapshot.fromMember(livePair);
    final system = systemOf([
      const ZoneGroupMember(
          uuid: pairL,
          zoneName: 'Office',
          channelMapSet: '$pairL:RF,RF;$pairR:LF,LF'),
    ]);
    expect(profileIsActive(profileOf([snap]), system), isFalse);
  });

  test('a pair reconfigured into a full-range zone is not active', () {
    final snap = EntitySnapshot.fromMember(livePair);
    final system = systemOf([
      const ZoneGroupMember(
          uuid: pairL,
          zoneName: 'Office',
          channelMapSet: '$pairL:LF,RF;$pairR:LF,RF'),
    ]);
    expect(profileIsActive(profileOf([snap]), system), isFalse);
  });

  test('a renamed room is not active', () {
    final snap = EntitySnapshot.fromMember(liveKitchen);
    final system =
        systemOf([const ZoneGroupMember(uuid: kitchen, zoneName: 'Cooking')]);
    expect(profileIsActive(profileOf([snap]), system), isFalse);
  });

  test('a single speaker is active standalone, inactive once bonded away', () {
    final snap = EntitySnapshot.fromMember(liveKitchen);
    expect(profileIsActive(profileOf([snap]), systemOf([liveKitchen])), isTrue);
    // Now bonded as an HT satellite: no longer a visible room of its own.
    final bonded = systemOf([
      const ZoneGroupMember(
          uuid: beam,
          zoneName: 'Living room',
          htSatChanMapSet: '$beam:CC;$kitchen:LF'),
    ]);
    expect(profileIsActive(profileOf([snap]), bonded), isFalse);
  });

  test('one non-matching entity makes the whole profile inactive', () {
    final system = systemOf([liveHt, liveKitchen]);
    final profile = profileOf([
      EntitySnapshot.fromMember(liveHt),
      // A pair whose speakers aren't bonded at all right now.
      const EntitySnapshot(
          kind: EntityKind.stereoPair,
          primaryUuid: pairL,
          mapSet: pairMap,
          names: {pairL: 'Office'}),
    ]);
    expect(profileIsActive(profile, system), isFalse);
  });

  test('an empty profile is never active', () {
    expect(profileIsActive(profileOf([]), systemOf([liveKitchen])), isFalse);
  });
}
