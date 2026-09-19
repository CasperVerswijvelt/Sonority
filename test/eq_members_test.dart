import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/speaker_eq/speaker_eq_screen.dart';

ZoneGroupMember _ht(String map) =>
    ZoneGroupMember(uuid: 'BAR', zoneName: 'Living', htSatChanMapSet: map);
ZoneGroupMember _group(String map) =>
    ZoneGroupMember(uuid: 'A', zoneName: 'Office', channelMapSet: map);

void main() {
  // A spectral-tuning apply that omits a bonded member stores NOTHING, with an
  // HTTP 200 and no error — so "which speakers is this entity?" has to be right
  // for every bond shape, not just the one the feature was built against.
  group('bondedUuids', () {
    test('a home theater carries the bar and every satellite', () {
      expect(
        _ht('BAR:CC;L:LF;R:RF;LS:LR;RS:RR;SUB:SW').bondedUuids,
        ['BAR', 'L', 'R', 'LS', 'RS', 'SUB'],
      );
    });

    test('a dual-sub home theater keeps BOTH subs', () {
      // Two SW entries collapse to one in a channel-keyed map, which silently
      // drops a sub from the batch and makes the whole apply a no-op.
      expect(
        _ht('BAR:CC;SUB1:SW;SUB2:SW').bondedUuids,
        ['BAR', 'SUB1', 'SUB2'],
      );
    });

    test('a stereo pair carries both speakers, not just the coordinator', () {
      expect(_group('A:LF,LF;B:RF,RF').bondedUuids, ['A', 'B']);
    });

    test('a zone carries every member', () {
      expect(_group('A:LF,RF;B:LF,RF;C:LF,RF').bondedUuids, ['A', 'B', 'C']);
    });

    test('a group with a sub carries the sub', () {
      expect(_group('A:LF,LF;B:RF,RF;SUB:SW').bondedUuids, ['A', 'B', 'SUB']);
    });

    test('a standalone speaker is just itself', () {
      expect(
        const ZoneGroupMember(uuid: 'ONE', zoneName: 'Kitchen').bondedUuids,
        ['ONE'],
      );
    });

    test('the coordinator is never duplicated', () {
      // A group map lists the coordinator as its first entry.
      final b = _group('A:LF,LF;B:RF,RF').bondedUuids;
      expect(b.where((u) => u == 'A'), hasLength(1));
    });
  });

  // A line-out box has no drivers to author for, so it is not in the batch —
  // and a batch missing a bonded member stores NOTHING (HTTP 200, no error).
  // The apply could only ever fail its poll and tell the user to check that
  // every speaker is reachable, which can never help. CLAUDE.md lists
  // Playbase + Connect:Amp as a confirmed-working layout, so this is reachable.
  group('eqBlockedByLineOut', () {
    SonosSystem systemOf(ZoneGroupMember member, List<SonosDevice> devices) =>
        SonosSystem(
          groups: [ZoneGroup(coordinatorUuid: member.uuid, members: [member])],
          devicesByUuid: {for (final d in devices) d.uuid: d},
        );

    test('an Amp driving the fronts blocks the whole home theater', () {
      final system = systemOf(_ht('BAR:CC;AMP:LF,RF;SUB:SW'), const [
        SonosDevice(uuid: 'BAR', roomName: 'Living', modelName: 'Sonos Beam'),
        SonosDevice(uuid: 'AMP', roomName: 'Living', modelName: 'Sonos Amp'),
        SonosDevice(uuid: 'SUB', roomName: 'Living', modelName: 'Sonos Sub'),
      ]);
      expect(eqBlockedByLineOut(system, 'BAR'), isTrue);
      expect(eqMembers(system, 'BAR').map((d) => d.uuid), ['BAR', 'SUB'],
          reason: 'the Amp is dropped, which is exactly why the set is short');
    });

    test('a home theater of native speakers is tunable', () {
      final system = systemOf(_ht('BAR:CC;L:LF;R:RF'), const [
        SonosDevice(uuid: 'BAR', roomName: 'Living', modelName: 'Sonos Beam'),
        SonosDevice(uuid: 'L', roomName: 'Living', modelName: 'Sonos Era 100'),
        SonosDevice(uuid: 'R', roomName: 'Living', modelName: 'Sonos Era 100'),
      ]);
      expect(eqBlockedByLineOut(system, 'BAR'), isFalse);
    });

    test('a standalone line-out box is blocked too — it is its own bond', () {
      final system = systemOf(
        const ZoneGroupMember(uuid: 'PORT', zoneName: 'Study'),
        const [
          SonosDevice(uuid: 'PORT', roomName: 'Study', modelName: 'Sonos Port'),
        ],
      );
      expect(eqBlockedByLineOut(system, 'PORT'), isTrue);
      expect(eqMembers(system, 'PORT'), isEmpty);
    });

    test('a standalone speaker is tunable', () {
      final system = systemOf(
        const ZoneGroupMember(uuid: 'ONE', zoneName: 'Kitchen'),
        const [
          SonosDevice(uuid: 'ONE', roomName: 'Kitchen', modelName: 'Sonos One'),
        ],
      );
      expect(eqBlockedByLineOut(system, 'ONE'), isFalse);
    });
  });
}
