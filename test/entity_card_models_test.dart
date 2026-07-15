import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/widgets/entity_cards.dart';

void main() {
  group('TheaterCardModel.fromSnapshot', () {
    test('reads chip presence from the HT map; soundbar falls back sans system',
        () {
      final m = ZoneGroupMember(
        uuid: 'BAR',
        zoneName: 'Living Room',
        htSatChanMapSet: 'BAR:CC;L:LF;R:RF;RL:LR;RR:RR;SUB:SW',
      );
      final model = TheaterCardModel.fromSnapshot(null, m);
      expect(model.title, 'Living Room');
      expect(model.soundbarLabel, 'Soundbar');
      expect(model.hasFronts, isTrue);
      expect(model.hasSurrounds, isTrue);
      expect(model.hasSub, isTrue);
    });

    test('fronts-only HT has no surrounds/sub', () {
      final model = TheaterCardModel.fromSnapshot(
        null,
        ZoneGroupMember(
            uuid: 'BAR', zoneName: 'LR', htSatChanMapSet: 'BAR:CC;L:LF;R:RF'),
      );
      expect(model.hasFronts, isTrue);
      expect(model.hasSurrounds, isFalse);
      expect(model.hasSub, isFalse);
    });
  });

  group('GroupCardModel.fromSnapshot', () {
    test('stereo pair: kind + count, sub excluded from count but flagged', () {
      final pair = GroupCardModel.fromSnapshot(null,
          ZoneGroupMember(uuid: 'A', zoneName: 'Office', channelMapSet: 'A:LF,LF;B:RF,RF'));
      expect(pair.title, 'Office');
      expect(pair.subtitle, 'Stereo pair · 2 speakers');

      final withSub = GroupCardModel.fromSnapshot(
          null,
          ZoneGroupMember(
              uuid: 'A', zoneName: 'Office', channelMapSet: 'A:LF,LF;B:RF,RF;S:SW'));
      expect(withSub.subtitle, 'Stereo pair · 2 speakers · Sub');
    });

    test('zone: N full-range speakers', () {
      final zone = GroupCardModel.fromSnapshot(
          null,
          ZoneGroupMember(
              uuid: 'A',
              zoneName: 'Upstairs',
              channelMapSet: 'A:LF,RF;B:LF,RF;C:LF,RF'));
      expect(zone.subtitle, 'Zone · 3 speakers');
    });
  });

  group('SingleCardModel reachability', () {
    final unreachableSystem = SonosSystem(
      groups: const [],
      devicesByUuid: {
        'X': const SonosDevice(
            uuid: 'X', roomName: 'Den', modelName: 'Sonos One', reachable: false),
      },
    );
    final member = ZoneGroupMember(uuid: 'X', zoneName: 'Den');

    test('fromSnapshot is always reachable (openable) regardless of system', () {
      expect(SingleCardModel.fromSnapshot(unreachableSystem, member).reachable,
          isTrue);
      expect(SingleCardModel.fromSnapshot(null, member).reachable, isTrue);
    });

    test('fromSnapshot falls back to a label when the device is not on the LAN',
        () {
      expect(SingleCardModel.fromSnapshot(null, member).typeLabel,
          'Standalone speaker');
    });

    test('fromMember honours the live device reachability', () {
      expect(
          SingleCardModel.fromMember(unreachableSystem, member).reachable, isFalse);
    });
  });
}
