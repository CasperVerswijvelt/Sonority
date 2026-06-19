import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

// Mirrors the real GetZoneGroupState representation captured from hardware:
// the left speaker stays visible with a ChannelMapSet; the right speaker is a
// separate member flagged Invisible="1" (name absorbed into the pair).
const _paired = '''
<ZoneGroupState><ZoneGroups>
  <ZoneGroup Coordinator="RINCON_KEUKEN01400" ID="x">
    <ZoneGroupMember UUID="RINCON_KEUKEN01400" ZoneName="Keuken"
      Location="http://192.168.1.22:1400/xml/device_description.xml"
      ChannelMapSet="RINCON_KEUKEN01400:LF,LF;RINCON_GYM01400:RF,RF"/>
    <ZoneGroupMember UUID="RINCON_GYM01400" ZoneName="Keuken" Invisible="1"
      Location="http://192.168.1.23:1400/xml/device_description.xml"
      ChannelMapSet="RINCON_KEUKEN01400:LF,LF;RINCON_GYM01400:RF,RF"/>
  </ZoneGroup>
  <ZoneGroup Coordinator="RINCON_ZOLDER01400" ID="y">
    <ZoneGroupMember UUID="RINCON_ZOLDER01400" ZoneName="Zolder"
      Location="http://192.168.1.24:1400/xml/device_description.xml"/>
  </ZoneGroup>
</ZoneGroups></ZoneGroupState>''';

SonosDevice _dev(String uuid, String room) =>
    SonosDevice(uuid: uuid, roomName: room, modelName: 'Sonos One', ip: '1.2.3.4');

void main() {
  test('parses a stereo pair: detects pair + flags the hidden right member', () {
    final groups = ZoneTopologyClient.parseZoneGroupState(_paired);
    final keuken = groups.first.members.firstWhere((m) => m.uuid == 'RINCON_KEUKEN01400');
    final gym = groups.first.members.firstWhere((m) => m.uuid == 'RINCON_GYM01400');

    expect(keuken.isStereoPair, isTrue);
    expect(keuken.invisible, isFalse);
    expect(keuken.stereoPairUuids, ['RINCON_KEUKEN01400', 'RINCON_GYM01400']);
    expect(gym.invisible, isTrue);
  });

  test('SonosSystem hides invisible members and excludes paired from bondable', () {
    final system = SonosSystem(
      groups: ZoneTopologyClient.parseZoneGroupState(_paired),
      devicesByUuid: {
        'RINCON_KEUKEN01400': _dev('RINCON_KEUKEN01400', 'Keuken'),
        'RINCON_GYM01400': _dev('RINCON_GYM01400', 'Gym'),
        'RINCON_ZOLDER01400': _dev('RINCON_ZOLDER01400', 'Zolder'),
      },
    );

    // The hidden right speaker is not a visible room.
    expect(system.allMembers.map((m) => m.uuid), isNot(contains('RINCON_GYM01400')));
    expect(system.stereoPairs.map((m) => m.uuid), ['RINCON_KEUKEN01400']);

    // Both paired speakers are excluded from bondable; the free one remains.
    final bondable = system.bondableSpeakers.map((d) => d.uuid).toSet();
    expect(bondable, contains('RINCON_ZOLDER01400'));
    expect(bondable, isNot(contains('RINCON_KEUKEN01400')));
    expect(bondable, isNot(contains('RINCON_GYM01400')));
  });
}
