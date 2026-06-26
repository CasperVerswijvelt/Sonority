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

  test('detects a single Amp that takes both fronts (AMP:LF,RF)', () {
    const map =
        'RINCON_BEAM:CC;RINCON_LR:LR;RINCON_RR:RR;RINCON_SUB:SW;RINCON_AMP:LF,RF';
    const member = ZoneGroupMember(
      uuid: 'RINCON_BEAM',
      zoneName: 'Woonkamer',
      htSatChanMapSet: map,
    );

    // The Amp is the only front satellite — removal targets just this one UUID.
    expect(member.frontSatelliteUuids, ['RINCON_AMP']);
    expect(member.hasDedicatedFronts, isTrue);
    expect(member.channelAssignments[SonosChannel.leftFront], 'RINCON_AMP');
    expect(member.channelAssignments[SonosChannel.rightFront], 'RINCON_AMP');
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
