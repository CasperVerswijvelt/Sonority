import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';

void main() {
  // Regression: right after a bonding change the <Satellite> elements vanish
  // from the topology for ~15s, but the HTSatChanMapSet is authoritative.
  test('detects fronts from the map even with no Satellite elements', () {
    const map =
        'RINCON_BEAM:CC;RINCON_LR:LR;RINCON_RR:RR;RINCON_SUB:SW;RINCON_FL:LF;RINCON_FR:RF';
    const member = ZoneGroupMember(
      uuid: 'RINCON_BEAM',
      zoneName: 'Woonkamer',
      htSatChanMapSet: map,
      satellites: [], // transient: not yet re-enumerated
    );

    expect(member.frontSatelliteUuids, ['RINCON_FL', 'RINCON_FR']);
    expect(member.hasDedicatedFronts, isTrue);
  });

  test('no fronts for a stock home theater (bar CC + rears + sub)', () {
    const member = ZoneGroupMember(
      uuid: 'RINCON_BEAM',
      zoneName: 'Woonkamer',
      htSatChanMapSet: 'RINCON_BEAM:CC;RINCON_LR:LR;RINCON_RR:RR;RINCON_SUB:SW',
    );
    expect(member.frontSatelliteUuids, isEmpty);
    expect(member.hasDedicatedFronts, isFalse);
  });

  test('skips the primary even if the bar carries LF/RF tokens', () {
    const member = ZoneGroupMember(
      uuid: 'RINCON_BAR',
      zoneName: 'LR',
      htSatChanMapSet: 'RINCON_BAR:LF,RF;RINCON_S1:LR;RINCON_S2:RR',
    );
    // Only the bar has front tokens, and it's the primary → no dedicated fronts.
    expect(member.frontSatelliteUuids, isEmpty);
    expect(member.hasDedicatedFronts, isFalse);
  });
}
