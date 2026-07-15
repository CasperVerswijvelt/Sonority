import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/widgets/entity_cards.dart';

void main() {
  // The rich HT card (overview only) keeps its composition chips.
  group('TheaterCardModel.fromMember', () {
    final emptySystem = const SonosSystem(groups: [], devicesByUuid: {});

    test('reads chip presence from the HT map; soundbar falls back sans device',
        () {
      final model = TheaterCardModel.fromMember(
        emptySystem,
        ZoneGroupMember(
          uuid: 'BAR',
          zoneName: 'Living Room',
          htSatChanMapSet: 'BAR:CC;L:LF;R:RF;RL:LR;RR:RR;SUB:SW',
        ),
      );
      expect(model.title, 'Living Room');
      expect(model.soundbarLabel, 'Soundbar');
      expect(model.hasFronts, isTrue);
      expect(model.hasSurrounds, isTrue);
      expect(model.hasSub, isTrue);
    });

    test('fronts-only HT has no surrounds/sub', () {
      final model = TheaterCardModel.fromMember(
        emptySystem,
        ZoneGroupMember(
            uuid: 'BAR', zoneName: 'LR', htSatChanMapSet: 'BAR:CC;L:LF;R:RF'),
      );
      expect(model.hasFronts, isTrue);
      expect(model.hasSurrounds, isFalse);
      expect(model.hasSub, isFalse);
    });
  });

  // The unified compact tile (overview group/single + every profile tile).
  group('EntityCardModel', () {
    test('home theater: surround icon + type · features text subtitle', () {
      final model = EntityCardModel.fromSnapshot(
        null,
        ZoneGroupMember(
            uuid: 'BAR',
            zoneName: 'Woonkamer',
            htSatChanMapSet: 'BAR:CC;L:LF;R:RF;SUB:SW'),
      );
      expect(model.icon, Icons.surround_sound);
      expect(model.title, 'Woonkamer');
      // Surrounds absent → omitted; soundbar type falls back sans system.
      expect(model.subtitle, 'Soundbar · Fronts · Subwoofer');
    });

    test('group: kind + count, sub flagged, NO per-speaker type list', () {
      final system = SonosSystem(groups: const [], devicesByUuid: {
        'A': const SonosDevice(uuid: 'A', roomName: 'Office', modelName: 'Sonos One'),
        'B': const SonosDevice(uuid: 'B', roomName: 'Office', modelName: 'Sonos One'),
      });
      final pair = EntityCardModel.fromMember(
          system,
          ZoneGroupMember(
              uuid: 'A', zoneName: 'Office', channelMapSet: 'A:LF,LF;B:RF,RF'));
      expect(pair.icon, Icons.speaker_group);
      expect(pair.subtitle, 'Stereo pair · 2 speakers');
      expect(pair.subtitle, isNot(contains('One'))); // types dropped

      final withSub = EntityCardModel.fromSnapshot(
          null,
          ZoneGroupMember(
              uuid: 'A', zoneName: 'Office', channelMapSet: 'A:LF,LF;B:RF,RF;S:SW'));
      expect(withSub.subtitle, 'Stereo pair · 2 speakers · Sub');

      final zone = EntityCardModel.fromSnapshot(
          null,
          ZoneGroupMember(
              uuid: 'A',
              zoneName: 'Upstairs',
              channelMapSet: 'A:LF,RF;B:LF,RF;C:LF,RF'));
      expect(zone.subtitle, 'Zone · 3 speakers');
    });

    group('single', () {
      final unreachableSystem = SonosSystem(groups: const [], devicesByUuid: {
        'X': const SonosDevice(
            uuid: 'X', roomName: 'Den', modelName: 'Sonos One', reachable: false),
      });
      final member = ZoneGroupMember(uuid: 'X', zoneName: 'Den');

      test('speaker icon; snapshot always reachable + label fallback', () {
        final m = EntityCardModel.fromSnapshot(null, member);
        expect(m.icon, Icons.speaker_outlined);
        expect(m.reachable, isTrue);
        expect(m.subtitle, 'Standalone speaker');
        expect(
            EntityCardModel.fromSnapshot(unreachableSystem, member).reachable,
            isTrue);
      });

      test('fromMember honours the live device reachability', () {
        expect(EntityCardModel.fromMember(unreachableSystem, member).reachable,
            isFalse);
      });
    });
  });
}
