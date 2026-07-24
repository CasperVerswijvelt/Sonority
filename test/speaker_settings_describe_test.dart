import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/speaker_settings.dart';

void main() {
  group('SpeakerSettings.describe', () {
    test('empty settings produce no rows', () {
      expect(const SpeakerSettings().describe(), isEmpty);
    });

    test('bass/treble are signed levels, loudness an On/Off toggle', () {
      final rows = const SpeakerSettings(
        bass: 3,
        treble: -2,
        loudness: true,
      ).describe();
      expect(rows, [
        (label: SettingLabel.bass, kind: SettingValueKind.signed, raw: 3),
        (label: SettingLabel.treble, kind: SettingValueKind.signed, raw: -2),
        (label: SettingLabel.loudness, kind: SettingValueKind.onOff, raw: 1),
      ]);
    });

    test('maps EQ tokens to labels + kinds, booleans as onOff raw 1/0', () {
      final rows = const SpeakerSettings(
        eq: {
          'NightMode': 1,
          'SubEnable': 0,
          'SubGain': -4,
          'SurroundLevel': 5,
        },
      ).describe();
      // Emitted in eqTypes order (SubGain precedes SubEnable), not map order.
      expect(rows, [
        (label: SettingLabel.nightMode, kind: SettingValueKind.onOff, raw: 1),
        (label: SettingLabel.subGain, kind: SettingValueKind.signed, raw: -4),
        (label: SettingLabel.subEnable, kind: SettingValueKind.onOff, raw: 0),
        (label: SettingLabel.surroundLevel, kind: SettingValueKind.signed, raw: 5),
      ]);
    });

    test('EQ rows follow eqTypes order regardless of map order', () {
      final rows = const SpeakerSettings(
        eq: {'SurroundLevel': 5, 'NightMode': 1},
      ).describe();
      expect(rows.map((r) => r.label).toList(),
          [SettingLabel.nightMode, SettingLabel.surroundLevel]);
    });

    test('every eqTypes token resolves to a SettingLabel (no token leaks)', () {
      final rows = SpeakerSettings(
        eq: {for (final t in eqTypes) t: 0},
      ).describe();
      expect(rows.length, eqTypes.length);
      // A record's fields are strongly typed — the label is always a SettingLabel,
      // so a raw token can't leak; assert every token produced a row.
      expect(rows.map((r) => r.label).toSet().length, eqTypes.length);
    });

    test('SubPolarity is a phase kind (UI renders 0°/180°), not a toggle', () {
      final row =
          SpeakerSettings(eq: {'SubPolarity': 1}).describe().single;
      expect(row.kind, SettingValueKind.polarity);
      expect(row.raw, 1);
    });

    test('signed levels: sub gain, surround levels, height', () {
      final rows = const SpeakerSettings(
        eq: {
          'SubGain': 5,
          'SurroundLevel': -3,
          'MusicSurroundLevel': 0,
          'HeightChannelLevel': 2,
          'SubCrossover': 90, // a frequency — a plain int, not signed
        },
      ).describe();
      expect(rows, [
        (label: SettingLabel.subGain, kind: SettingValueKind.signed, raw: 5),
        (label: SettingLabel.subCrossover, kind: SettingValueKind.raw, raw: 90),
        (label: SettingLabel.surroundLevel, kind: SettingValueKind.signed, raw: -3),
        (
          label: SettingLabel.musicSurroundLevel,
          kind: SettingValueKind.signed,
          raw: 0
        ),
        (
          label: SettingLabel.heightChannelLevel,
          kind: SettingValueKind.signed,
          raw: 2
        ),
      ]);
    });

    test('SurroundMode and DialogLevel carry their own kind + raw value', () {
      // The UI maps 0/1 to words and falls back to the raw int for anything else,
      // so describe() must preserve the raw value for that fallback.
      final mode = SpeakerSettings(eq: {'SurroundMode': 2}).describe().single;
      expect(mode.kind, SettingValueKind.surroundMode);
      expect(mode.raw, 2);
      final dialog = SpeakerSettings(eq: {'DialogLevel': 3}).describe().single;
      expect(dialog.kind, SettingValueKind.dialogLevel);
      expect(dialog.raw, 3);
    });

    test('volume is a percent kind, mute an On/Off toggle', () {
      final rows = const SpeakerSettings(volume: 22, mute: true).describe();
      expect(rows, [
        (label: SettingLabel.volume, kind: SettingValueKind.percent, raw: 22),
        (label: SettingLabel.muted, kind: SettingValueKind.onOff, raw: 1),
      ]);
    });
  });
}
