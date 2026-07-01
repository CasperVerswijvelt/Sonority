import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/front_surrounds/front_surrounds_flow.dart';

/// The configure-HT flow pre-seeds its selectors from the live bond so already-
/// bonded speakers show selected (WYSIWYG). These lock the seeding shape.
void main() {
  const beam = 'RINCON_BEAM01400';
  const fl = 'RINCON_FL01400';
  const fr = 'RINCON_FR01400';
  const lr = 'RINCON_LR01400';
  const rr = 'RINCON_RR01400';
  const sub = 'RINCON_SUB01400';
  const sub2 = 'RINCON_SUB201400';
  const amp = 'RINCON_AMP01400';

  ZoneGroupMember bar(String map) =>
      ZoneGroupMember(uuid: beam, zoneName: 'Woonkamer', htSatChanMapSet: map);

  test('semi-bonded HT (fronts + sub, no rears) → opens on the Rears step', () {
    final s = seedHtRoles(bar('$beam:CC;$fl:LF;$fr:RF;$sub:SW'));
    expect(s.fronts, [fl, fr]); // ordered left, right
    expect(s.surrounds, isEmpty);
    expect(s.subs, [sub]);
    expect(s.step, 1); // first empty role
  });

  test('full 5.1 → all roles seeded, opens on step 0', () {
    final s = seedHtRoles(bar('$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR;$sub:SW'));
    expect(s.fronts, [fl, fr]);
    expect(s.surrounds, [lr, rr]);
    expect(s.subs, [sub]);
    expect(s.step, 0);
  });

  test('Amp on both fronts collapses to a single front entry', () {
    final s = seedHtRoles(bar('$beam:CC;$amp:LF,RF;$sub:SW'));
    expect(s.fronts, [amp]);
    expect(s.surrounds, isEmpty);
    expect(s.subs, [sub]);
  });

  test('dual sub is fully seeded', () {
    final s = seedHtRoles(bar('$beam:CC;$fl:LF;$fr:RF;$sub:SW;$sub2:SW'));
    expect(s.subs, [sub, sub2]);
  });

  test('bare bar → nothing seeded, opens on Fronts', () {
    final s = seedHtRoles(bar('$beam:CC'));
    expect(s.fronts, isEmpty);
    expect(s.surrounds, isEmpty);
    expect(s.subs, isEmpty);
    expect(s.step, 0);
  });

  test('fronts + rears, no sub → opens on the Sub step', () {
    final s = seedHtRoles(bar('$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR'));
    expect(s.step, 2);
  });
}
