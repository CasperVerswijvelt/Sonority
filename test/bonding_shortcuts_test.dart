import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/room/bonding_shortcuts.dart';

/// Builds a system of standalone rooms from [devices] (each its own group).
SonosSystem _standalone(List<SonosDevice> devices) => SonosSystem(
      groups: [
        for (final d in devices)
          ZoneGroup(coordinatorUuid: d.uuid, members: [
            ZoneGroupMember(uuid: d.uuid, zoneName: d.roomName),
          ]),
      ],
      devicesByUuid: {for (final d in devices) d.uuid: d},
    );

const _one = SonosDevice(uuid: 'A', roomName: 'Kitchen', modelName: 'Sonos One');
const _two = SonosDevice(uuid: 'B', roomName: 'Office', modelName: 'Sonos One');
const _bar =
    SonosDevice(uuid: 'BAR', roomName: 'Living', modelName: 'Sonos Beam');
const _sub = SonosDevice(uuid: 'SUB', roomName: 'Sub', modelName: 'Sonos Sub');

void main() {
  group('canGroupSpeaker', () {
    test('false when it is the only groupable speaker (would dead-end)', () {
      expect(canGroupSpeaker(_standalone([_one]), 'A'), isFalse);
    });

    test('true when another groupable speaker exists', () {
      final sys = _standalone([_one, _two]);
      expect(canGroupSpeaker(sys, 'A'), isTrue);
      expect(canGroupSpeaker(sys, 'B'), isTrue);
    });

    test('false for a speaker that cannot be grouped (a soundbar)', () {
      // Two Ones exist, but a soundbar itself can't join a zone.
      expect(canGroupSpeaker(_standalone([_bar, _one, _two]), 'BAR'), isFalse);
    });
  });

  group('canGroupSub', () {
    test('false with fewer than two groupable speakers', () {
      expect(canGroupSub(_standalone([_sub])), isFalse);
      expect(canGroupSub(_standalone([_sub, _one])), isFalse);
    });

    test('true once two speakers are available to bond with', () {
      expect(canGroupSub(_standalone([_sub, _one, _two])), isTrue);
    });

    test('a soundbar does not count toward the two speakers', () {
      expect(canGroupSub(_standalone([_sub, _bar, _one])), isFalse);
    });
  });
}
