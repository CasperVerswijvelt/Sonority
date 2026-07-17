import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/front_layout.dart';

/// The WYSIWYG configure-HT path: the flow seeds its selection from the live
/// layout, edits it, and applies the FULL desired map via
/// `buildLayoutMap(preserveExisting: false)` → `diffHtLayout`. These chain both
/// exactly as `SonosController.applyHomeTheaterLayout` does, so a deselected role
/// resolves to a real `RemoveHTSatellite`, not a stale keep.
void main() {
  const beam = 'RINCON_BEAM01400';
  const fl = 'RINCON_FL01400';
  const fr = 'RINCON_FR01400';
  const lr = 'RINCON_LR01400';
  const rr = 'RINCON_RR01400';
  const sub = 'RINCON_SUB01400';
  const nfl = 'RINCON_NEWFL01400';
  const nfr = 'RINCON_NEWFR01400';

  SonosDevice dev(String uuid) => SonosDevice(
      uuid: uuid, roomName: uuid, modelName: 'Sonos One', ip: '1.2.3.4');
  ZoneGroupMember bar(String map) =>
      ZoneGroupMember(uuid: beam, zoneName: 'Woonkamer', htSatChanMapSet: map);

  HtDiff apply(ZoneGroupMember current, Map<SonosChannel, String> desired,
          {List<String> subs = const []}) =>
      diffHtLayout(
        current: current,
        target: buildLayoutMap(
          soundbar: current,
          soundbarDevice: dev(beam),
          desired: desired,
          subUuids: subs,
          preserveExisting: false,
        ),
      );

  test('add rears to a bar with existing fronts + sub: nothing removed', () {
    final d = apply(
      bar('$beam:CC;$fl:LF;$fr:RF;$sub:SW'),
      {
        SonosChannel.leftFront: fl,
        SonosChannel.rightFront: fr,
        SonosChannel.leftRear: lr,
        SonosChannel.rightRear: rr,
      },
      subs: [sub],
    );
    expect(d.toRemove, isEmpty);
    expect(d.isNoOp, isFalse);
  });

  test('replace fronts (deselect old pair, pick a new one): old pair removed', () {
    final d = apply(
      bar('$beam:CC;$fl:LF;$fr:RF;$sub:SW'),
      {SonosChannel.leftFront: nfl, SonosChannel.rightFront: nfr},
      subs: [sub],
    );
    expect(d.toRemove, {fl, fr});
    expect(d.target.encode(), '$beam:CC;$nfl:LF;$nfr:RF;$sub:SW');
    expect(d.isNoOp, isFalse);
  });

  test('swap fronts↔surrounds: movers stay bonded, nothing removed', () {
    final d = apply(
      bar('$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR;$sub:SW'),
      {
        // fr and lr exchange roles; both remain bonded on a new channel, so the
        // apply reassigns in place rather than stripping them first.
        SonosChannel.leftFront: fl,
        SonosChannel.rightFront: lr,
        SonosChannel.leftRear: fr,
        SonosChannel.rightRear: rr,
      },
      subs: [sub],
    );
    expect(d.toRemove, isEmpty);
    expect(d.isNoOp, isFalse);
  });

  test('unchanged selection is a zero-write no-op', () {
    final d = apply(
      bar('$beam:CC;$fl:LF;$fr:RF;$sub:SW'),
      {SonosChannel.leftFront: fl, SonosChannel.rightFront: fr},
      subs: [sub],
    );
    expect(d.isNoOp, isTrue);
    expect(d.toRemove, isEmpty);
  });

  test('deselect everything strips to the bare bar (all satellites removed)', () {
    final d = apply(bar('$beam:CC;$fl:LF;$fr:RF;$sub:SW'), const {});
    expect(d.target.encode(), '$beam:CC');
    expect(d.toRemove, {fl, fr, sub});
    expect(d.isNoOp, isFalse);
  });
}
