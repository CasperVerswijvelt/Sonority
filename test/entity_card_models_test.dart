import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/widgets/entity_cards.dart';

void main() {
  List<String> chipLabels(EntityCardModel m) =>
      m.chips.map((c) => c.label).toList();

  // The one entity tile (overview home theaters/groups/singles + every profile
  // tile). Composition is carried as `chips`, not a `·`-joined string.
  group('EntityCardModel', () {
    test('home theater: part chips + the "not in the Sonos app" flag', () {
      final model = EntityCardModel.fromSnapshot(
        null,
        ZoneGroupMember(
            uuid: 'BAR',
            zoneName: 'Woonkamer',
            htSatChanMapSet: 'BAR:CC;L:LF;R:RF;SUB:SW'),
      );
      expect(model.icon, Icons.surround_sound);
      expect(model.title, 'Woonkamer');
      expect(model.subtitle, 'Soundbar'); // type falls back sans system
      // Surrounds absent → omitted; dedicated fronts → the unofficial flag.
      expect(chipLabels(model), ['Fronts', 'Subwoofer', 'Not in the Sonos app']);
    });

    test('home theater with no extras: placeholder chip, no flag', () {
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
      // Same model → not flagged as mixed.
      expect(chipLabels(pair), ['Stereo pair', '2 speakers']);
      expect(chipLabels(pair), isNot(contains('One'))); // types dropped

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
      expect(chipLabels(zone), ['Zone', '3 speakers']); // < warn size
    });

    test('mixed-model pair carries the unofficial flag', () {
      final system = SonosSystem(groups: const [], devicesByUuid: {
        'A': const SonosDevice(
            uuid: 'A', roomName: 'Office', modelName: 'Sonos One'),
        'B': const SonosDevice(
            uuid: 'B', roomName: 'Office', modelName: 'Sonos Play:1'),
      });
      final pair = EntityCardModel.fromMember(system,
          ZoneGroupMember(uuid: 'A', zoneName: 'Office', channelMapSet: 'A:LF,LF;B:RF,RF'));
      expect(chipLabels(pair), contains('Not in the Sonos app'));
    });

    test('a large zone warns it can drop out', () {
      final big = EntityCardModel.fromSnapshot(
          null,
          ZoneGroupMember(
              uuid: 'A',
              zoneName: 'Whole floor',
              channelMapSet:
                  'A:LF,RF;B:LF,RF;C:LF,RF;D:LF,RF;E:LF,RF')); // 5 ≥ kZoneWarnSize
      expect(chipLabels(big), contains('Can drop out'));
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

  group('unofficialConfigLabel', () {
    test('dedicated fronts on a home theater', () {
      expect(
        unofficialConfigLabel(
            null,
            ZoneGroupMember(
                uuid: 'BAR', zoneName: 'LR', htSatChanMapSet: 'BAR:CC;L:LF;R:RF')),
        'Dedicated fronts',
      );
    });

    test('custom L/R/Both group', () {
      // One single-sided + one full-range entry ⇒ neither pair nor zone ⇒ custom.
      expect(
        unofficialConfigLabel(
            null,
            ZoneGroupMember(
                uuid: 'A', zoneName: 'Mix', channelMapSet: 'A:LF,LF;B:LF,RF')),
        'Custom layout',
      );
    });

    test('ordinary same-model pair and plain HT are not flagged', () {
      final system = SonosSystem(groups: const [], devicesByUuid: {
        'A': const SonosDevice(uuid: 'A', roomName: 'O', modelName: 'Sonos One'),
        'B': const SonosDevice(uuid: 'B', roomName: 'O', modelName: 'Sonos One'),
      });
      expect(
          unofficialConfigLabel(system,
              ZoneGroupMember(uuid: 'A', zoneName: 'O', channelMapSet: 'A:LF,LF;B:RF,RF')),
          isNull);
      expect(
          unofficialConfigLabel(
              null,
              ZoneGroupMember(
                  uuid: 'BAR', zoneName: 'LR', htSatChanMapSet: 'BAR:CC')),
          isNull);
    });
  });
}
