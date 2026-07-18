import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/widgets/entity_cards.dart';

void main() {
  // The one entity tile (overview home theaters/groups/singles + every profile
  // tile). Composition is carried as `chips`, not a `·`-joined string.
  group('EntityCardModel', () {
    List<String> chipLabels(EntityCardModel m) =>
        m.chips.map((c) => c.label).toList();

    test('home theater: surround icon, soundbar-type subtitle, part chips', () {
      final model = EntityCardModel.fromSnapshot(
        null,
        ZoneGroupMember(
            uuid: 'BAR',
            zoneName: 'Woonkamer',
            htSatChanMapSet: 'BAR:CC;L:LF;R:RF;SUB:SW'),
      );
      expect(model.icon, Icons.surround_sound);
      expect(model.title, 'Woonkamer');
      // Soundbar type falls back sans system.
      expect(model.subtitle, 'Soundbar');
      // Surrounds absent → omitted from the chips.
      expect(chipLabels(model), ['Fronts', 'Subwoofer']);
    });

    test('home theater with no extras shows a single placeholder chip', () {
      final model = EntityCardModel.fromSnapshot(
        null,
        ZoneGroupMember(uuid: 'BAR', zoneName: 'LR', htSatChanMapSet: 'BAR:CC'),
      );
      expect(chipLabels(model), ['No extra speakers']);
    });

    test('group: kind + count chips, sub flagged, NO per-speaker type list', () {
      final system = SonosSystem(groups: const [], devicesByUuid: {
        'A': const SonosDevice(
            uuid: 'A', roomName: 'Office', modelName: 'Sonos One'),
        'B': const SonosDevice(
            uuid: 'B', roomName: 'Office', modelName: 'Sonos One'),
      });
      final pair = EntityCardModel.fromMember(
          system,
          ZoneGroupMember(
              uuid: 'A', zoneName: 'Office', channelMapSet: 'A:LF,LF;B:RF,RF'));
      expect(pair.icon, Icons.speaker_group);
      expect(chipLabels(pair), ['Stereo pair', '2 speakers']);
      // Types are never listed — tap through for details.
      expect(chipLabels(pair), isNot(contains('One')));

      final withSub = EntityCardModel.fromSnapshot(
          null,
          ZoneGroupMember(
              uuid: 'A',
              zoneName: 'Office',
              channelMapSet: 'A:LF,LF;B:RF,RF;S:SW'));
      expect(chipLabels(withSub), ['Stereo pair', '2 speakers', 'Sub']);

      final zone = EntityCardModel.fromSnapshot(
          null,
          ZoneGroupMember(
              uuid: 'A',
              zoneName: 'Upstairs',
              channelMapSet: 'A:LF,RF;B:LF,RF;C:LF,RF'));
      expect(chipLabels(zone), ['Zone', '3 speakers']);
    });

    group('single', () {
      final unreachableSystem = SonosSystem(groups: const [], devicesByUuid: {
        'X': const SonosDevice(
            uuid: 'X', roomName: 'Den', modelName: 'Sonos One', reachable: false),
      });
      final member = ZoneGroupMember(uuid: 'X', zoneName: 'Den');

      test('speaker icon, type subtitle, no chips; snapshot always reachable', () {
        final m = EntityCardModel.fromSnapshot(null, member);
        expect(m.icon, Icons.speaker_outlined);
        expect(m.reachable, isTrue);
        expect(m.subtitle, 'Standalone speaker');
        expect(m.chips, isEmpty);
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
