import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
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

  SonosDevice dev(String uuid) =>
      SonosDevice(uuid: uuid, roomName: uuid, modelName: 'Sonos One', ip: '1.2.3.4');

  ZoneGroupMember bar({String? map}) =>
      ZoneGroupMember(uuid: beam, zoneName: 'Woonkamer', htSatChanMapSet: map);

  test('builds a full 5.1 from a bare bar (canonical order)', () {
    final map = buildLayoutMap(
      soundbar: bar(),
      soundbarDevice: dev(beam),
      desired: {
        SonosChannel.leftFront: fl,
        SonosChannel.rightFront: fr,
        SonosChannel.leftRear: lr,
        SonosChannel.rightRear: rr,
        SonosChannel.sub: sub,
      },
    );
    expect(map.encode(),
        '$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR;$sub:SW');
  });

  test('adds surrounds while preserving existing fronts + sub', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;$fl:LF;$fr:RF;$sub:SW'),
      soundbarDevice: dev(beam),
      desired: {SonosChannel.leftRear: lr, SonosChannel.rightRear: rr},
    );
    expect(map.encode(), '$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR;$sub:SW');
  });

  test('adds a sub while preserving fronts + rears', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR'),
      soundbarDevice: dev(beam),
      desired: {SonosChannel.sub: sub},
    );
    expect(map.encode(), '$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR;$sub:SW');
  });

  test('overrides existing fronts rather than duplicating', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;OLD_FL:LF;OLD_FR:RF;$sub:SW'),
      soundbarDevice: dev(beam),
      desired: {SonosChannel.leftFront: fl, SonosChannel.rightFront: fr},
    );
    expect(map.encode(), '$beam:CC;$fl:LF;$fr:RF;$sub:SW');
    expect(map.entries.where((e) => e.uuid == 'OLD_FL'), isEmpty);
  });

  test('an Amp on both fronts collapses into one AMP:LF,RF entry', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;$sub:SW'),
      soundbarDevice: dev(beam),
      desired: {SonosChannel.leftFront: amp, SonosChannel.rightFront: amp},
    );
    expect(map.encode(), '$beam:CC;$amp:LF,RF;$sub:SW');
  });

  test('preserveExisting:false ignores the current layout (full rebuild)', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;$fl:LF;$fr:RF;$lr:LR;$rr:RR;$sub:SW'),
      soundbarDevice: dev(beam),
      desired: {SonosChannel.leftRear: lr, SonosChannel.rightRear: rr},
      preserveExisting: false,
    );
    expect(map.encode(), '$beam:CC;$lr:LR;$rr:RR');
  });

  test('adds two Subs (dual-sub) via subUuids', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;$fl:LF;$fr:RF'),
      soundbarDevice: dev(beam),
      desired: const {},
      subUuids: [sub, sub2],
    );
    expect(map.encode(), '$beam:CC;$fl:LF;$fr:RF;$sub:SW;$sub2:SW');
  });

  test('adds a second Sub while preserving the existing one', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;$fl:LF;$fr:RF;$sub:SW'),
      soundbarDevice: dev(beam),
      desired: const {},
      subUuids: [sub2],
    );
    expect(map.encode(), '$beam:CC;$fl:LF;$fr:RF;$sub:SW;$sub2:SW');
  });

  test('dual-sub is idempotent (re-adding an existing Sub does not duplicate)', () {
    final map = buildLayoutMap(
      soundbar: bar(map: '$beam:CC;$fl:LF;$fr:RF;$sub:SW;$sub2:SW'),
      soundbarDevice: dev(beam),
      desired: const {},
      subUuids: [sub, sub2],
    );
    expect(map.encode(), '$beam:CC;$fl:LF;$fr:RF;$sub:SW;$sub2:SW');
  });

  test('subUuids parses both Subs off an HTSatChanMapSet', () {
    final m = bar(map: '$beam:CC;$fl:LF;$fr:RF;$sub:SW;$sub2:SW');
    expect(m.subUuids, [sub, sub2]);
  });

  test('isAmp matches Amp / Connect:Amp but not speakers, subs, or soundbars', () {
    SonosDevice d(String model) =>
        SonosDevice(uuid: amp, roomName: amp, modelName: model, ip: '1.2.3.4');
    expect(d('Sonos Amp').isAmp, isTrue);
    expect(d('Sonos Connect:Amp').isAmp, isTrue);
    expect(d('Sonos Beam').isAmp, isFalse);
    expect(d('Sonos One SL').isAmp, isFalse);
    expect(d('Sonos Sub').isAmp, isFalse);
  });
}
