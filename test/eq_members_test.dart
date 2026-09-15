import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';

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
}
