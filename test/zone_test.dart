import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/zone_topology.dart';
import 'package:sonority/features/profiles/profile.dart';

// Mirrors the real GetZoneGroupState for a Sonos "zone" — captured from hardware
// via tool/zone_probe.dart: the coordinator stays visible carrying a
// ChannelMapSet where EVERY member is full-range (LF,RF); the other members are
// separate Invisible members (names absorbed into the coordinator).
const _zoned = '''
<ZoneGroupState><ZoneGroups>
  <ZoneGroup Coordinator="RINCON_KEUKEN01400" ID="x">
    <ZoneGroupMember UUID="RINCON_KEUKEN01400" ZoneName="Keuken"
      Location="http://192.168.1.22:1400/xml/device_description.xml"
      ChannelMapSet="RINCON_KEUKEN01400:LF,RF;RINCON_ZOLDER01400:LF,RF;RINCON_GYM01400:LF,RF"/>
    <ZoneGroupMember UUID="RINCON_ZOLDER01400" ZoneName="Keuken" Invisible="1"
      Location="http://192.168.1.24:1400/xml/device_description.xml"
      ChannelMapSet="RINCON_KEUKEN01400:LF,RF;RINCON_ZOLDER01400:LF,RF;RINCON_GYM01400:LF,RF"/>
    <ZoneGroupMember UUID="RINCON_GYM01400" ZoneName="Keuken" Invisible="1"
      Location="http://192.168.1.23:1400/xml/device_description.xml"
      ChannelMapSet="RINCON_KEUKEN01400:LF,RF;RINCON_ZOLDER01400:LF,RF;RINCON_GYM01400:LF,RF"/>
  </ZoneGroup>
</ZoneGroups></ZoneGroupState>''';

// A genuine stereo pair — single-sided entries (LF,LF / RF,RF) — must NOT be
// mistaken for a zone now that isStereoPair is narrowed.
const _paired = '''
<ZoneGroupState><ZoneGroups>
  <ZoneGroup Coordinator="RINCON_L01400" ID="x">
    <ZoneGroupMember UUID="RINCON_L01400" ZoneName="Bureau"
      Location="http://192.168.1.30:1400/xml/device_description.xml"
      ChannelMapSet="RINCON_L01400:LF,LF;RINCON_R01400:RF,RF"/>
    <ZoneGroupMember UUID="RINCON_R01400" ZoneName="Bureau" Invisible="1"
      Location="http://192.168.1.31:1400/xml/device_description.xml"
      ChannelMapSet="RINCON_L01400:LF,LF;RINCON_R01400:RF,RF"/>
  </ZoneGroup>
</ZoneGroups></ZoneGroupState>''';

SonosDevice _dev(String uuid, String room) =>
    SonosDevice(uuid: uuid, roomName: room, modelName: 'Sonos One', ip: '1.2.3.4');

void main() {
  test('parses a zone: isZone, members, and hidden flags', () {
    final groups = ZoneTopologyClient.parseZoneGroupState(_zoned);
    final coord = groups.first.members
        .firstWhere((m) => m.uuid == 'RINCON_KEUKEN01400');

    expect(coord.isZone, isTrue);
    expect(coord.isStereoPair, isFalse, reason: 'a zone is not a stereo pair');
    expect(coord.isHomeTheater, isFalse);
    expect(coord.zoneMemberUuids,
        ['RINCON_KEUKEN01400', 'RINCON_ZOLDER01400', 'RINCON_GYM01400']);

    final hidden = groups.first.members.where((m) => m.invisible).map((m) => m.uuid);
    expect(hidden, containsAll(['RINCON_ZOLDER01400', 'RINCON_GYM01400']));
  });

  test('a real stereo pair stays a pair, not a zone', () {
    final groups = ZoneTopologyClient.parseZoneGroupState(_paired);
    final left = groups.first.members.firstWhere((m) => m.uuid == 'RINCON_L01400');
    expect(left.isStereoPair, isTrue);
    expect(left.isZone, isFalse);
    expect(left.zoneMemberUuids, isEmpty);
  });

  test('SonosSystem.zones + bondable/zoneable exclusions', () {
    final system = SonosSystem(
      groups: ZoneTopologyClient.parseZoneGroupState(_zoned),
      devicesByUuid: {
        'RINCON_KEUKEN01400': _dev('RINCON_KEUKEN01400', 'Keuken'),
        'RINCON_ZOLDER01400': _dev('RINCON_ZOLDER01400', 'Zolder'),
        'RINCON_GYM01400': _dev('RINCON_GYM01400', 'Gym'),
      },
    );

    // Only the coordinator is a visible room; the zone surfaces once.
    expect(system.zones.map((m) => m.uuid), ['RINCON_KEUKEN01400']);
    expect(system.allMembers.map((m) => m.uuid), ['RINCON_KEUKEN01400']);

    // Every zone member is committed — none offered as bondable/zoneable.
    final bondable = system.bondableSpeakers.map((d) => d.uuid).toSet();
    expect(bondable, isEmpty);
    expect(system.zoneableSpeakers, isEmpty);
  });

  test('ownerOf catches zone/custom group members (not just HT/pairs)', () {
    final system = SonosSystem(
      groups: ZoneTopologyClient.parseZoneGroupState(_zoned),
      devicesByUuid: {
        'RINCON_KEUKEN01400': _dev('RINCON_KEUKEN01400', 'Keuken'),
        'RINCON_ZOLDER01400': _dev('RINCON_ZOLDER01400', 'Zolder'),
        'RINCON_GYM01400': _dev('RINCON_GYM01400', 'Gym'),
        'standalone': _dev('standalone', 'Spare'),
      },
    );
    // A non-coordinator zone member is owned by the coordinator — the case the
    // profile pre-flight previously missed (it only checked HT/stereo pairs).
    expect(system.ownerOf('RINCON_ZOLDER01400'), 'RINCON_KEUKEN01400');
    expect(system.ownerOf('RINCON_GYM01400'), 'RINCON_KEUKEN01400');
    // A speaker that isn't in any group is unowned.
    expect(system.ownerOf('standalone'), isNull);
  });

  test('zoneableSpeakers excludes amps, subs, soundbars; offers free speakers', () {
    final system = SonosSystem(
      groups: const [],
      devicesByUuid: {
        'one': SonosDevice(uuid: 'one', roomName: 'A', modelName: 'Sonos One', ip: '1'),
        'amp': SonosDevice(uuid: 'amp', roomName: 'B', modelName: 'Sonos Amp', ip: '2'),
        'sub': SonosDevice(uuid: 'sub', roomName: 'C', modelName: 'Sonos Sub', ip: '3'),
        'bar': SonosDevice(uuid: 'bar', roomName: 'D', modelName: 'Sonos Beam', ip: '4'),
        'play': SonosDevice(uuid: 'play', roomName: 'E', modelName: 'Sonos Play:1', ip: '5'),
      },
    );
    expect(system.zoneableSpeakers.map((d) => d.uuid).toSet(), {'one', 'play'});
  });

  test('EntitySnapshot captures a zone and round-trips through JSON', () {
    final m = ZoneGroupMember(
      uuid: 'RINCON_KEUKEN01400',
      zoneName: 'Downstairs',
      channelMapSet:
          'RINCON_KEUKEN01400:LF,RF;RINCON_ZOLDER01400:LF,RF;RINCON_GYM01400:LF,RF',
    );
    final snap = EntitySnapshot.fromMember(m);
    expect(snap.kind, EntityKind.zone);
    expect(snap.primaryUuid, 'RINCON_KEUKEN01400');
    expect(snap.involvedUuids,
        {'RINCON_KEUKEN01400', 'RINCON_ZOLDER01400', 'RINCON_GYM01400'});

    final back = EntitySnapshot.fromJson(
        jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>);
    expect(back.kind, EntityKind.zone);
    expect(back.mapSet, m.channelMapSet);
    expect(back.names['RINCON_KEUKEN01400'], 'Downstairs');
  });
}
