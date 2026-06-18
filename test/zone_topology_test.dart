import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

const _sample = '''
<ZoneGroupState>
  <ZoneGroups>
    <ZoneGroup Coordinator="RINCON_BAR01400" ID="RINCON_BAR01400:1">
      <ZoneGroupMember UUID="RINCON_BAR01400" ZoneName="Living Room"
        Location="http://192.168.1.10:1400/xml/device_description.xml"
        HTSatChanMapSet="RINCON_BAR01400:LF,RF;RINCON_S101400:LR;RINCON_S201400:RR">
        <Satellite UUID="RINCON_S101400" ZoneName="Living Room (LS)"
          Location="http://192.168.1.11:1400/xml/device_description.xml" Invisible="1"/>
        <Satellite UUID="RINCON_S201400" ZoneName="Living Room (RS)"
          Location="http://192.168.1.12:1400/xml/device_description.xml" Invisible="1"/>
      </ZoneGroupMember>
    </ZoneGroup>
    <ZoneGroup Coordinator="RINCON_KIT01400" ID="RINCON_KIT01400:2">
      <ZoneGroupMember UUID="RINCON_KIT01400" ZoneName="Kitchen"
        Location="http://192.168.1.20:1400/xml/device_description.xml"/>
    </ZoneGroup>
  </ZoneGroups>
</ZoneGroupState>
''';

void main() {
  test('parses groups, members, and satellites with channel mapping', () {
    final groups = ZoneTopologyClient.parseZoneGroupState(_sample);
    expect(groups, hasLength(2));

    final ht = groups.first.coordinator!;
    expect(ht.zoneName, 'Living Room');
    expect(ht.isHomeTheater, isTrue);
    expect(ht.satellites, hasLength(2));

    final ls = ht.satellites.firstWhere((s) => s.uuid == 'RINCON_S101400');
    expect(ls.channels, [SonosChannel.leftRear]);
    expect(ls.isRear, isTrue);
    expect(ht.hasDedicatedFronts, isFalse);
    expect(ht.ip, '192.168.1.10');

    final kitchen = groups[1].coordinator!;
    expect(kitchen.isHomeTheater, isFalse);
  });

  test('detects dedicated fronts when satellites carry LF/RF', () {
    const raw = '''
<ZoneGroupState><ZoneGroups>
  <ZoneGroup Coordinator="RINCON_BAR01400" ID="x">
    <ZoneGroupMember UUID="RINCON_BAR01400" ZoneName="LR"
      Location="http://192.168.1.10:1400/xml/device_description.xml"
      HTSatChanMapSet="RINCON_BAR01400:LF,RF;RINCON_FL01400:LF;RINCON_FR01400:RF">
      <Satellite UUID="RINCON_FL01400" ZoneName="LR (L)" Invisible="1"/>
      <Satellite UUID="RINCON_FR01400" ZoneName="LR (R)" Invisible="1"/>
    </ZoneGroupMember>
  </ZoneGroup>
</ZoneGroups></ZoneGroupState>''';
    final groups = ZoneTopologyClient.parseZoneGroupState(raw);
    expect(groups.first.coordinator!.hasDedicatedFronts, isTrue);
  });
}
