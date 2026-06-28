import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
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
  }) async =>
      XmlDocument.parse(bodyXml).rootElement;
}

void main() {
  group('RoomCalibration SOAP envelopes', () {
    test('GetRoomCalibrationStatus', () {
      final xml = SonosSoapClient.buildEnvelope(
        serviceType: 'urn:schemas-upnp-org:service:RenderingControl:1',
        action: 'GetRoomCalibrationStatus',
        args: const {'InstanceID': '0'},
      );
      expect(
        xml,
        contains(
            '<u:GetRoomCalibrationStatus xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">'),
      );
      expect(xml, contains('<InstanceID>0</InstanceID>'));
    });

    test('SetRoomCalibrationStatus carries the enable flag', () {
      final on = SonosSoapClient.buildEnvelope(
        serviceType: 'urn:schemas-upnp-org:service:RenderingControl:1',
        action: 'SetRoomCalibrationStatus',
        args: const {'InstanceID': '0', 'RoomCalibrationEnabled': '1'},
      );
      expect(on, contains('<RoomCalibrationEnabled>1</RoomCalibrationEnabled>'));
    });
  });

  group('RoomCalibrationClient.getStatus parsing', () {
    Future<RoomCalibration> parse(String avail, String enabled) {
      final body = '<Body>'
          '<RoomCalibrationEnabled>$enabled</RoomCalibrationEnabled>'
          '<RoomCalibrationAvailable>$avail</RoomCalibrationAvailable>'
          '</Body>';
      return RoomCalibrationClient(_FakeSoap(body)).getStatus('1.2.3.4');
    }

    test('available + enabled ⇒ active', () async {
      final s = await parse('1', '1');
      expect(s.available, isTrue);
      expect(s.enabled, isTrue);
      expect(s.active, isTrue);
    });

    test('available but off ⇒ not active', () async {
      final s = await parse('1', '0');
      expect(s.available, isTrue);
      expect(s.enabled, isFalse);
      expect(s.active, isFalse);
    });

    test('no tuning ⇒ not available, not active', () async {
      final s = await parse('0', '0');
      expect(s.available, isFalse);
      expect(s.active, isFalse);
    });
  });
}
