import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:xml/xml.dart';

/// Returns a canned SOAP Body so we can exercise parsing without a network.
class _FakeSoap extends SonosSoapClient {
  final String bodyXml;
  _FakeSoap(this.bodyXml);

  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async =>
      XmlDocument.parse(bodyXml).rootElement;
}

void main() {
  group('DevicePropertiesClient.getZoneAttributes parsing', () {
    Future<ZoneAttributes> parse(String innerBody) =>
        DevicePropertiesClient(_FakeSoap('<Body>$innerBody</Body>'))
            .getZoneAttributes('1.2.3.4');

    test('maps all three fields', () async {
      final a = await parse('<CurrentZoneName>Living Room</CurrentZoneName>'
          '<CurrentIcon>x-rincon-roomicon:living</CurrentIcon>'
          '<CurrentConfiguration>1</CurrentConfiguration>');
      expect(a.zoneName, 'Living Room');
      expect(a.icon, 'x-rincon-roomicon:living');
      expect(a.configuration, '1');
    });

    test('missing elements default to empty string, never null-crash', () async {
      final a = await parse('<CurrentZoneName>Kitchen</CurrentZoneName>');
      expect(a.zoneName, 'Kitchen');
      expect(a.icon, '');
      expect(a.configuration, '');
    });
  });
}
