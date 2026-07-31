import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/speaker_settings.dart';
import 'package:xml/xml.dart';

/// Records write calls and answers reads from a per-action table. A read whose
/// action/EQType isn't in the table throws — simulating a speaker that doesn't
/// support that setting, which the client must turn into an absent field (not
/// a failure).
class _FakeSoap extends SonosSoapClient {
  final Map<String, String> reads; // key: action or "GetEQ:EQType" → out element text
  final List<String> writes = [];
  final List<String> readCalls = [];

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
    readCalls.add(action == 'GetEQ' ? 'GetEQ:${args['EQType']}' : action);
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
  test('read parses supported fields and skips unsupported EQ types', () async {
    final fake = _FakeSoap({
      'GetBass': '5',
      'GetTreble': '-3',
      'GetLoudness': '1',
      'GetEQ:NightMode': '1',
      'GetEQ:SurroundMode': '1',
      'GetEQ:AudioDelayLeftRear': '2',
      // No DialogLevel/SubGain/… → those throw → absent from the map.
      'GetVolume': '22',
      'GetMute': '0',
    });
    final s = await SpeakerSettingsClient(fake).read('1.2.3.4', volume: true);
    expect(s.bass, 5);
    expect(s.treble, -3);
    expect(s.loudness, isTrue);
    expect(s.eq,
        {'NightMode': 1, 'SurroundMode': 1, 'AudioDelayLeftRear': 2});
    expect(s.volume, 22);
    expect(s.mute, isFalse);
  });

  test('read skips audio when audio:false, volume when volume:false', () async {
    final fake = _FakeSoap({'GetBass': '5', 'GetVolume': '22'});
    final volOnly = await SpeakerSettingsClient(fake).read('1.2.3.4',
        audio: false, volume: true);
    expect(volOnly.bass, isNull);
    expect(volOnly.eq, isEmpty);
    expect(volOnly.volume, 22);
    expect(volOnly.hasAudioSettings, isFalse);

    final eqOnly = await SpeakerSettingsClient(fake).read('1.2.3.4');
    expect(eqOnly.bass, 5);
    expect(eqOnly.volume, isNull);
    expect(eqOnly.hasVolume, isFalse);
  });

  test('apply writes only captured fields', () async {
    final fake = _FakeSoap(const {});
    await SpeakerSettingsClient(fake).apply(
      '1.2.3.4',
      const SpeakerSettings(
          bass: 4, eq: {'NightMode': 1, 'SubPolarity': 2}, volume: 30),
    );
    expect(
        fake.writes,
        containsAll(
            ['SetBass=4', 'SetEQ:NightMode=1', 'SetEQ:SubPolarity=2', 'SetVolume=30']));
    expect(fake.writes.any((w) => w.startsWith('SetTreble')), isFalse);
    expect(fake.writes.any((w) => w.startsWith('SetLoudness')), isFalse);
    expect(fake.writes.length, 4);
  });

  // apply() probes the speaker first (it may have just been bonded and still be
  // refusing :1400). A probe that FAULTS means the speaker answered, so writes
  // must proceed immediately — no waiting. `_FakeSoap(const {})` faults every
  // read, so this is the path the tests above take too; asserted here so it's
  // covered on purpose rather than by accident. The refused-then-recovers path is
  // covered by the retryUnreachable tests in soap_envelope_test.dart; exercising
  // it through apply() would mean a real ~16s wait, so it isn't tested here.
  test('a probe answered with a fault does not block the writes', () async {
    final fake = _FakeSoap(const {});
    final failed = await SpeakerSettingsClient(fake)
        .apply('1.2.3.4', const SpeakerSettings(volume: 22));
    expect(fake.writes, ['SetVolume=22']);
    expect(failed, 0);
    // Exactly ONE probe: a fault means the speaker answered, so it must not be
    // retried. Without this assertion a regression that retried faults would
    // still pass, just 20s slower per speaker.
    expect(fake.readCalls, ['GetVolume']);
  });

  test('empty settings write nothing', () async {
    final fake = _FakeSoap(const {});
    await SpeakerSettingsClient(fake).apply('1.2.3.4', SpeakerSettings.empty);
    expect(fake.writes, isEmpty);
  });

  test('JSON round-trip keeps the eq map; empty eq omitted', () {
    const s = SpeakerSettings(bass: 1, eq: {'AudioDelay': 3, 'SubEnable': 1});
    final back = SpeakerSettings.fromJson(s.toJson());
    expect(back.eq, {'AudioDelay': 3, 'SubEnable': 1});
    expect(const SpeakerSettings(bass: 1).toJson().containsKey('eq'), isFalse);
  });
}
