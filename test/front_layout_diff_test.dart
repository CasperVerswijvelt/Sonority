import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/channel_map.dart';
import 'package:sonority/data/sonos/front_layout.dart';

void main() {
  const beam = 'RINCON_BEAM01400';
  const fl = 'RINCON_FL01400';
  const fr = 'RINCON_FR01400';
  const lr = 'RINCON_LR01400';
  const rr = 'RINCON_RR01400';
  const sub = 'RINCON_SUB01400';
  const sub2 = 'RINCON_SUB201400';
  const amp = 'RINCON_AMP01400';

  ZoneGroupMember bar(String? map) =>
      ZoneGroupMember(uuid: beam, zoneName: 'Woonkamer', htSatChanMapSet: map);
  ChannelMap target(String map) => ChannelMap.parse(map);

  const full = '$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR;$sub:SW';

  test('no-op when current already equals target', () {
    final d = diffHtLayout(current: bar(full), target: target(full));
    expect(d.isNoOp, isTrue);
    expect(d.toRemove, isEmpty);
  });

  test('add-only (bare bar → full): nothing to remove, not a no-op', () {
    final d = diffHtLayout(current: bar('$beam:CC'), target: target(full));
    expect(d.isNoOp, isFalse);
    expect(d.toRemove, isEmpty);
  });

  test('remove-only (target drops the sub): the sub is removed, not a no-op', () {
    final d = diffHtLayout(
      current: bar(full),
      target: target('$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR'),
    );
    expect(d.isNoOp, isFalse);
    expect(d.toRemove, {sub});
  });

  test('swap (LR↔RR): both surrounds must be removed first', () {
    final d = diffHtLayout(
      current: bar(full),
      // lr now on RR, rr now on LR — each moved channel.
      target: target('$beam:CC;$fl:LF;$fr:RF;$rr:LR;$lr:RR;$sub:SW'),
    );
    expect(d.isNoOp, isFalse);
    expect(d.toRemove, {lr, rr});
  });

  test('replace (different speaker on a channel): old one removed', () {
    final d = diffHtLayout(
      current: bar('$beam:CC;$fl:LF;$fr:RF'),
      target: target('$beam:CC;OTHER:LF;$fr:RF'),
    );
    expect(d.toRemove, {fl});
    expect(d.isNoOp, isFalse);
  });

  test('dual-sub no-op: both SW UUIDs kept, no spurious remove', () {
    const dual = '$beam:CC;$fl:LF;$fr:RF;$sub:SW;$sub2:SW';
    final d = diffHtLayout(current: bar(dual), target: target(dual));
    expect(d.isNoOp, isTrue);
    expect(d.toRemove, isEmpty);
  });

  test('dual-sub → single sub: the dropped sub is removed', () {
    final d = diffHtLayout(
      current: bar('$beam:CC;$sub:SW;$sub2:SW'),
      target: target('$beam:CC;$sub:SW'),
    );
    expect(d.toRemove, {sub2});
    expect(d.isNoOp, isFalse);
  });

  test('Amp on both fronts is a no-op when unchanged', () {
    const ampMap = '$beam:CC;$amp:LF,RF;$sub:SW';
    final d = diffHtLayout(current: bar(ampMap), target: target(ampMap));
    expect(d.isNoOp, isTrue);
    expect(d.toRemove, isEmpty);
  });

  test('two separate fronts → one Amp on both: both old fronts removed', () {
    final d = diffHtLayout(
      current: bar('$beam:CC;$fl:LF;$fr:RF'),
      target: target('$beam:CC;$amp:LF,RF'),
    );
    expect(d.toRemove, {fl, fr});
    expect(d.isNoOp, isFalse);
  });

  test('target is preserved on the diff for the caller to bond', () {
    final t = target(full);
    final d = diffHtLayout(current: bar('$beam:CC'), target: t);
    expect(d.target, same(t));
  });
}
