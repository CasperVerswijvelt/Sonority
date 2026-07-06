import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/speaker_settings.dart';
import 'package:xml/xml.dart';

/// Records write calls and answers reads from a per-action table. A read whose
/// action/EQType isn't in the table throws — simulating a speaker that doesn't
/// support that setting, which the client must turn into `null` (not a failure).
class _FakeSoap extends SonosSoapClient {
  final Map<String, String> reads; // key: action or "GetEQ:EQType" → out element text
  final List<String> writes = [];

  _FakeSoap(this.reads);

  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (action.startsWith('Set')) {
      writes.add(action == 'SetEQ'
          ? 'SetEQ:${args['EQType']}=${args['DesiredValue']}'
          : '$action=${args.values.last}');
      return XmlDocument.parse('<Body/>').rootElement;
    }
    final key = action == 'GetEQ' ? 'GetEQ:${args['EQType']}' : action;
    final v = reads[key];
    if (v == null) throw SonosSoapException(action, faultString: 'unsupported');
    // Every Get* returns its value in a matching Current* element; GetEQ uses
    // CurrentValue.
    final el = action == 'GetEQ' ? 'CurrentValue' : action.replaceFirst('Get', 'Current');
    return XmlDocument.parse('<Body><$el>$v</$el></Body>').rootElement;
  }
}

void main() {
  test('read parses supported fields and nulls unsupported ones', () async {
    final fake = _FakeSoap({
      'GetBass': '5',
      'GetTreble': '-3',
      'GetLoudness': '1',
      'GetEQ:NightMode': '1',
      // No DialogLevel/SubGain/SurroundLevel → those throw → null.
      'GetVolume': '22',
      'GetMute': '0',
    });
    final s = await SpeakerSettingsClient(fake).read('1.2.3.4', volume: true);
    expect(s.bass, 5);
    expect(s.treble, -3);
    expect(s.loudness, isTrue);
    expect(s.nightMode, isTrue);
    expect(s.dialogLevel, isNull);
    expect(s.subGain, isNull);
    expect(s.volume, 22);
    expect(s.mute, isFalse);
  });

  test('read skips EQ when eq:false, volume when volume:false', () async {
    final fake = _FakeSoap({'GetBass': '5', 'GetVolume': '22'});
    final volOnly = await SpeakerSettingsClient(fake).read('1.2.3.4',
        eq: false, volume: true);
    expect(volOnly.bass, isNull);
    expect(volOnly.volume, 22);
    expect(volOnly.hasEq, isFalse);

    final eqOnly = await SpeakerSettingsClient(fake).read('1.2.3.4');
    expect(eqOnly.bass, 5);
    expect(eqOnly.volume, isNull);
    expect(eqOnly.hasVolume, isFalse);
  });

  test('apply writes only non-null fields', () async {
    final fake = _FakeSoap(const {});
    await SpeakerSettingsClient(fake).apply(
      '1.2.3.4',
      const SpeakerSettings(bass: 4, nightMode: true, volume: 30),
    );
    expect(fake.writes, containsAll(['SetBass=4', 'SetEQ:NightMode=1', 'SetVolume=30']));
    expect(fake.writes.any((w) => w.startsWith('SetTreble')), isFalse);
    expect(fake.writes.any((w) => w.startsWith('SetLoudness')), isFalse);
    expect(fake.writes.length, 3);
  });

  test('empty settings write nothing', () async {
    final fake = _FakeSoap(const {});
    await SpeakerSettingsClient(fake).apply('1.2.3.4', SpeakerSettings.empty);
    expect(fake.writes, isEmpty);
  });
}
