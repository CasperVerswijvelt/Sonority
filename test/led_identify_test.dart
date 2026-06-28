import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/led_identify.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:xml/xml.dart';

/// Records every SOAP call and lets a test feed a canned GetLEDState response
/// and force a failure on a chosen SetLEDState invocation.
class _FakeSoap extends SonosSoapClient {
  _FakeSoap({
    this.ledState = 'On',
    this.throwOnSetIndex,
    this.throwAllSets = false,
  });

  /// Value returned by GetLEDState ("On"/"Off"), or null to omit the element.
  final String? ledState;

  /// Zero-based index among SetLEDState calls that should throw, if any.
  final int? throwOnSetIndex;

  /// When true, every SetLEDState call throws (simulates an unreachable speaker).
  final bool throwAllSets;

  final List<({String action, Map<String, String> args})> calls = [];
  int _setCount = 0;

  List<({String action, Map<String, String> args})> get setCalls =>
      calls.where((c) => c.action == 'SetLEDState').toList();

  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    calls.add((action: action, args: args));
    if (action == 'SetLEDState') {
      final i = _setCount++;
      if (throwAllSets) throw Exception('unreachable on set #$i');
      if (i == throwOnSetIndex) throw Exception('boom on set #$i');
    }
    final body = action == 'GetLEDState'
        ? '<Body>${ledState == null ? '' : '<CurrentLEDState>$ledState</CurrentLEDState>'}</Body>'
        : '<Body></Body>';
    return XmlDocument.parse(body).rootElement;
  }
}

void main() {
  group('LED SOAP envelopes', () {
    test('SetLEDState carries the desired state', () {
      final on = SonosSoapClient.buildEnvelope(
        serviceType: 'urn:schemas-upnp-org:service:DeviceProperties:1',
        action: 'SetLEDState',
        args: const {'DesiredLEDState': 'On'},
      );
      expect(
        on,
        contains(
            '<u:SetLEDState xmlns:u="urn:schemas-upnp-org:service:DeviceProperties:1">'),
      );
      expect(on, contains('<DesiredLEDState>On</DesiredLEDState>'));
    });
  });

  group('getLedState parsing', () {
    test('"On" ⇒ true', () async {
      final s = await LedIdentifyClient(_FakeSoap(ledState: 'On'))
          .getLedState('1.2.3.4');
      expect(s, isTrue);
    });
    test('"Off" ⇒ false', () async {
      final s = await LedIdentifyClient(_FakeSoap(ledState: 'Off'))
          .getLedState('1.2.3.4');
      expect(s, isFalse);
    });
    test('missing element ⇒ null', () async {
      final s = await LedIdentifyClient(_FakeSoap(ledState: null))
          .getLedState('1.2.3.4');
      expect(s, isNull);
    });
  });

  group('blink is self-reverting', () {
    test('restores to ON when the light was on', () async {
      final fake = _FakeSoap(ledState: 'On');
      await LedIdentifyClient(fake)
          .blink('1.2.3.4', cycles: 2, interval: Duration.zero);
      // First call reads state, last call must restore it.
      expect(fake.calls.first.action, 'GetLEDState');
      expect(fake.setCalls.last.args['DesiredLEDState'], 'On');
    });

    test('restores to OFF when the light was off', () async {
      final fake = _FakeSoap(ledState: 'Off');
      await LedIdentifyClient(fake)
          .blink('1.2.3.4', cycles: 2, interval: Duration.zero);
      expect(fake.setCalls.last.args['DesiredLEDState'], 'Off');
    });

    test('tolerates a transient toggle failure and still restores', () async {
      // One failed toggle shouldn't abort the blink or throw — it keeps going
      // and the finally still restores the captured original ("On").
      final fake = _FakeSoap(ledState: 'On', throwOnSetIndex: 0);
      await LedIdentifyClient(fake)
          .blink('1.2.3.4', cycles: 2, interval: Duration.zero);
      expect(fake.setCalls.last.args['DesiredLEDState'], 'On');
    });

    test('throws when every toggle fails (speaker unreachable)', () async {
      final fake = _FakeSoap(ledState: 'On', throwAllSets: true);
      await expectLater(
        LedIdentifyClient(fake)
            .blink('1.2.3.4', cycles: 2, interval: Duration.zero),
        throwsA(isA<Exception>()),
      );
    });

    test('defaults restore to ON when the initial read fails', () async {
      final fake = _FakeSoap(ledState: null); // GetLEDState returns no element
      await LedIdentifyClient(fake)
          .blink('1.2.3.4', cycles: 1, interval: Duration.zero);
      expect(fake.setCalls.last.args['DesiredLEDState'], 'On');
    });
  });
}
