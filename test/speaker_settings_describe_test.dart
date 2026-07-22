import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/speaker_settings.dart';

void main() {
  group('SpeakerSettings.describe', () {
    test('empty settings produce no rows', () {
      expect(const SpeakerSettings().describe(), isEmpty);
    });

    test('signs bass/treble and formats loudness as On/Off', () {
      final rows = const SpeakerSettings(
        bass: 3,
        treble: -2,
        loudness: true,
      ).describe();
      expect(rows, [
        (label: 'Bass', value: '+3'),
        (label: 'Treble', value: '-2'),
        (label: 'Loudness', value: 'On'),
      ]);
    });

    test(
      'maps EQ tokens to human labels; toggles as On/Off, levels as ints',
      () {
        final rows = const SpeakerSettings(
          eq: {
            'NightMode': 1,
            'SubEnable': 0,
            'SubGain': -4,
            'SurroundLevel': 5,
          },
        ).describe();
        // Emitted in eqTypes order (SubGain precedes SubEnable), not map order.
        // Sub level / surround level are signed (like bass/treble).
        expect(rows, [
          (label: 'Night sound', value: 'On'),
          (label: 'Sub level', value: '-4'),
          (label: 'Sub', value: 'Off'),
          (label: 'Surround level (TV)', value: '+5'),
        ]);
      },
    );

    test('EQ rows follow eqTypes order regardless of map order', () {
      final rows = const SpeakerSettings(
        eq: {'SurroundLevel': 5, 'NightMode': 1},
      ).describe();
      expect(rows.map((r) => r.label).toList(), [
        'Night sound',
        'Surround level (TV)',
      ]);
    });

    test(
      'every eqTypes token resolves to a human label (no raw token leaks)',
      () {
        final rows = SpeakerSettings(
          eq: {for (final t in eqTypes) t: 0},
        ).describe();
        expect(rows.length, eqTypes.length);
        for (final r in rows) {
          expect(
            eqTypes.contains(r.label),
            isFalse,
            reason: 'raw token leaked as a label: ${r.label}',
          );
        }
      },
    );

    test('SubPolarity renders as a sub phase (0°/180°), not On/Off', () {
      String phase(int v) =>
          (SpeakerSettings(eq: {'SubPolarity': v}).describe()).single.value;
      expect(phase(0), '0°');
      expect(phase(1), '180°');
    });

    test('signed levels (sub/surround/height) show an explicit + sign', () {
      final rows = const SpeakerSettings(
        eq: {
          'SubGain': 5,
          'SurroundLevel': -3,
          'MusicSurroundLevel': 0,
          'HeightChannelLevel': 2,
          'SubCrossover': 90, // a frequency — stays unsigned
        },
      ).describe();
      expect(rows, [
        (label: 'Sub level', value: '+5'),
        (label: 'Sub crossover', value: '90'),
        (label: 'Surround level (TV)', value: '-3'),
        (label: 'Surround level (music)', value: '0'),
        (label: 'Height level', value: '+2'),
      ]);
    });

    test('SurroundMode maps 0→Ambient, 1→Full, else raw', () {
      String mode(int v) =>
          SpeakerSettings(eq: {'SurroundMode': v}).describe().single.value;
      expect(mode(0), 'Ambient');
      expect(mode(1), 'Full');
      expect(mode(2), '2'); // unexpected value falls back to the raw int
    });

    test('DialogLevel maps 0→Off, 1→On, else raw', () {
      String level(int v) =>
          SpeakerSettings(eq: {'DialogLevel': v}).describe().single.value;
      expect(level(0), 'Off');
      expect(level(1), 'On');
      expect(level(3), '3'); // a level rather than a toggle falls back to raw
    });

    test('volume as percent and mute as On/Off', () {
      final rows = const SpeakerSettings(volume: 22, mute: true).describe();
      expect(rows, [
        (label: 'Volume', value: '22%'),
        (label: 'Muted', value: 'On'),
      ]);
    });
  });
}
