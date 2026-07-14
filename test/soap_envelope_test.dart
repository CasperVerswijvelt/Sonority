import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:xml/xml.dart';

void main() {
  group('SoapBodyText.childText', () {
    final body = XmlDocument.parse(
      '<Body><CurrentVolume> 30 </CurrentVolume>'
      '<CurrentMute>1</CurrentMute><Empty></Empty></Body>',
    ).rootElement;

    test('returns first match, trimmed', () {
      expect(body.childText('CurrentVolume'), '30');
      expect(body.childText('CurrentMute'), '1');
    });
    test('empty element trims to empty string, missing tag is null', () {
      expect(body.childText('Empty'), '');
      expect(body.childText('Nope'), isNull);
    });
    test('composes for int/bool parsing like the call sites', () {
      expect(int.tryParse(body.childText('CurrentVolume') ?? ''), 30);
      expect(int.tryParse(body.childText('Nope') ?? ''), isNull);
      expect(body.childText('CurrentMute') == '1', isTrue);
    });
  });


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

  group('SonosSoapClient.call error handling', () {
    Future<XmlElement> callWith(int status, String body) {
      final client = MockClient((_) async => http.Response(body, status));
      return SonosSoapClient(client).call(
        ip: '1.2.3.4',
        controlPath: '/x/Control',
        serviceType: 'svc',
        action: 'DoThing',
      );
    }

    test('non-200 with a non-XML body throws SonosSoapException, not XmlException',
        () async {
      // Regression: the body used to be parsed before the status check, so a
      // truncated/empty error body threw XmlParserException and callers keyed on
      // SonosSoapException never ran.
      await expectLater(
        callWith(500, 'gateway timeout - not xml'),
        throwsA(isA<SonosSoapException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('non-200 with a SOAP fault body extracts the fault code', () async {
      await expectLater(
        callWith(500,
            '<Body><faultstring>UPnPError</faultstring><errorCode>402</errorCode></Body>'),
        throwsA(isA<SonosSoapException>()
            .having((e) => e.faultCode, 'faultCode', '402')),
      );
    });
  });
}
