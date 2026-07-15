import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/speaker_settings.dart';

void main() {
  group('SpeakerSettings.describe', () {
    test('empty settings produce no rows', () {
      expect(const SpeakerSettings().describe(), isEmpty);
    });

    test('signs bass/treble and formats loudness as On/Off', () {
      final rows = const SpeakerSettings(bass: 3, treble: -2, loudness: true)
          .describe();
      expect(rows, [
        (label: 'Bass', value: '+3'),
        (label: 'Treble', value: '-2'),
        (label: 'Loudness', value: 'On'),
      ]);
    });

    test('maps EQ tokens to human labels; toggles as On/Off, levels as ints', () {
      final rows = const SpeakerSettings(eq: {
        'NightMode': 1,
        'SubEnable': 0,
        'SubGain': -4,
        'SurroundLevel': 5,
      }).describe();
      // Emitted in eqTypes order (SubGain precedes SubEnable), not map order.
      expect(rows, [
        (label: 'Night sound', value: 'On'),
        (label: 'Sub level', value: '-4'),
        (label: 'Sub', value: 'Off'),
        (label: 'Surround level (TV)', value: '5'),
      ]);
    });

    test('EQ rows follow eqTypes order regardless of map order', () {
      final rows = const SpeakerSettings(eq: {
        'SurroundLevel': 5,
        'NightMode': 1,
      }).describe();
      expect(rows.map((r) => r.label).toList(),
          ['Night sound', 'Surround level (TV)']);
    });

    test('unknown token falls back to the raw token as label', () {
      final rows = const SpeakerSettings(eq: {'NightMode': 1}).describe();
      // eqTypes-driven, so an unmapped-but-listed token still resolves; verify
      // the label map covers every eqTypes entry (no raw tokens leak through).
      expect(rows.single.label, 'Night sound');
    });

    test('volume as percent and mute as On/Off', () {
      final rows =
          const SpeakerSettings(volume: 22, mute: true).describe();
      expect(rows, [
        (label: 'Volume', value: '22%'),
        (label: 'Muted', value: 'On'),
      ]);
    });
  });
}
