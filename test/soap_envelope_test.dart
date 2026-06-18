import 'package:flutter_test/flutter_test.dart';
import 'package:soyes/data/sonos/soap_client.dart';

void main() {
  test('builds a valid AddHTSatellite envelope with escaped args', () {
    final xml = SonosSoapClient.buildEnvelope(
      serviceType: 'urn:schemas-upnp-org:service:DeviceProperties:1',
      action: 'AddHTSatellite',
      args: {'HTSatChanMapSet': 'RINCON_BAR:LF,RF;RINCON_FL:LF'},
    );

    expect(xml, contains('<s:Envelope'));
    expect(
        xml,
        contains(
            '<u:AddHTSatellite xmlns:u="urn:schemas-upnp-org:service:DeviceProperties:1">'));
    expect(xml, contains('<HTSatChanMapSet>RINCON_BAR:LF,RF;RINCON_FL:LF</HTSatChanMapSet>'));
    expect(xml, contains('</s:Envelope>'));
  });

  test('escapes XML-sensitive characters in argument values', () {
    final xml = SonosSoapClient.buildEnvelope(
      serviceType: 'svc',
      action: 'SetZoneAttributes',
      args: {'DesiredZoneName': 'Living & <Room>'},
    );
    expect(xml, contains('Living &amp; &lt;Room&gt;'));
    expect(xml, isNot(contains('Living & <Room>')));
  });
}
