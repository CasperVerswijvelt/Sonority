import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/channel_map.dart';

void main() {
  group('ChannelMap.parse', () {
    test('parses a full home-theater map set', () {
      const raw =
          'RINCON_BAR01400:LF,RF;RINCON_S101400:LR;RINCON_S201400:RR;RINCON_SUB01400:SW';
      final map = ChannelMap.parse(raw);

      expect(map.entries, hasLength(4));
      expect(map.primary!.uuid, 'RINCON_BAR01400');
      expect(map.primary!.channels,
          [SonosChannel.leftFront, SonosChannel.rightFront]);
      expect(map.entries[1].channels, [SonosChannel.leftRear]);
      expect(map.entries[3].channels, [SonosChannel.sub]);
    });

    test('skips empty entries but preserves unknown tokens raw', () {
      final map = ChannelMap.parse('RINCON_A:LF,XX;;RINCON_B:;RINCON_C:RR');
      expect(map.entries.map((e) => e.uuid), ['RINCON_A', 'RINCON_C']);
      // Typed view drops the unknown token...
      expect(map.entries.first.channels, [SonosChannel.leftFront]);
      // ...but the raw token survives so round-trips never corrupt the map.
      expect(map.entries.first.tokens, ['LF', 'XX']);
    });

    test('preserves the soundbar CC entry (real Beam layout)', () {
      // Regression: CC was previously dropped, corrupting AddHTSatellite maps.
      const raw = 'RINCON_BEAM:CC;RINCON_S1:LR;RINCON_S2:RR;RINCON_SUB:SW';
      final map = ChannelMap.parse(raw);
      expect(map.primary!.uuid, 'RINCON_BEAM');
      expect(map.primary!.channels, [SonosChannel.center]);
      expect(map.encode(), raw);
    });

    test('round-trips encode/parse', () {
      const raw = 'RINCON_BAR01400:LF,RF;RINCON_S101400:LR;RINCON_S201400:RR';
      expect(ChannelMap.parse(raw).encode(), raw);
    });
  });

  test('withoutUuid removes the matching entry', () {
    final map = ChannelMap.parse('RINCON_BAR:LF,RF;RINCON_FL:LF')
        .withoutUuid('RINCON_FL');
    expect(map.entries, hasLength(1));
    expect(map.entries.single.uuid, 'RINCON_BAR');
  });
}
