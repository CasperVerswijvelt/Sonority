import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/zone_layout.dart';
import 'package:sonority/features/profiles/profile.dart';

ZoneGroupMember _m(String cms) =>
    ZoneGroupMember(uuid: 'A', zoneName: 'Group', channelMapSet: cms);

void main() {
  group('buildGroupMap', () {
    test('encodes per-speaker channels + optional sub', () {
      expect(
        buildGroupMap([
          (uuid: 'A', channel: GroupChannel.left),
          (uuid: 'B', channel: GroupChannel.right),
        ]),
        'A:LF,LF;B:RF,RF',
      );
      expect(
        buildGroupMap([
          (uuid: 'A', channel: GroupChannel.both),
          (uuid: 'B', channel: GroupChannel.both),
        ], subUuid: 'SUB'),
        'A:LF,RF;B:LF,RF;SUB:SW',
      );
    });

    test('buildZoneMap == all-both buildGroupMap', () {
      expect(buildZoneMap(['A', 'B', 'C']),
          'A:LF,RF;B:LF,RF;C:LF,RF');
    });
  });

  group('groupKind / subUuid (Sub ignored for classification)', () {
    test('stereo pair, with and without a sub', () {
      expect(_m('A:LF,LF;B:RF,RF').groupKind, GroupKind.stereoPair);
      final withSub = _m('A:LF,LF;B:RF,RF;SUB:SW');
      expect(withSub.groupKind, GroupKind.stereoPair);
      expect(withSub.subUuid, 'SUB');
      expect(withSub.isStereoPair, isTrue);
    });

    test('zone, with and without a sub', () {
      expect(_m('A:LF,RF;B:LF,RF').groupKind, GroupKind.zone);
      final withSub = _m('A:LF,RF;B:LF,RF;SUB:SW');
      expect(withSub.groupKind, GroupKind.zone);
      expect(withSub.subUuid, 'SUB');
    });

    test('custom (2L+1R) is neither pair nor zone', () {
      final c = _m('A:LF,LF;B:LF,LF;C:RF,RF');
      expect(c.groupKind, GroupKind.custom);
      expect(c.isStereoPair, isFalse);
      expect(c.isZone, isFalse);
      expect(c.subUuid, isNull);
      expect(c.groupChannels, {
        'A': GroupChannel.left,
        'B': GroupChannel.left,
        'C': GroupChannel.right,
      });
    });

    test('isGroup + channelMapUuids include the sub', () {
      final c = _m('A:LF,RF;B:LF,RF;SUB:SW');
      expect(c.isGroup, isTrue);
      expect(c.channelMapUuids, ['A', 'B', 'SUB']);
      expect(c.groupChannels.keys, ['A', 'B']); // audio only
    });
  });

  group('EntitySnapshot for groups', () {
    test('custom group: kind + involved uuids + JSON round-trip', () {
      final snap = EntitySnapshot.fromMember(_m('A:LF,LF;B:LF,LF;C:RF,RF'));
      expect(snap.kind, EntityKind.custom);
      expect(snap.involvedUuids, {'A', 'B', 'C'});
      final back = EntitySnapshot.fromJson(
          jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>);
      expect(back.kind, EntityKind.custom);
      expect(back.mapSet, 'A:LF,LF;B:LF,LF;C:RF,RF');
    });

    test('zone + sub stays kind zone, sub in involved uuids', () {
      final snap = EntitySnapshot.fromMember(_m('A:LF,RF;B:LF,RF;SUB:SW'));
      expect(snap.kind, EntityKind.zone);
      expect(snap.involvedUuids, {'A', 'B', 'SUB'});
    });
  });
}
