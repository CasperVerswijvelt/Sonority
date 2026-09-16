import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/front_layout.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/speaker_picker.dart';
import 'package:sonority/l10n/app_localizations.dart';

/// What the DESTINATION of a bond costs — the half no source bond knows about.
///
/// A bonding change costs the bond it CREATES, not only the ones it empties
/// (CLAUDE.md, Q20/Q8a). Pricing only stolen speakers left the most ordinary
/// destructive action in the app — pair two tuned speakers — priced at zero.
void main() {
  group('the flow wiring, end to end', _wiring);

  const a = 'RINCON_A01400';
  const b = 'RINCON_B01400';
  const c = 'RINCON_C01400';

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  SonosDevice dev(String uuid, String room) => SonosDevice(
      uuid: uuid, roomName: room, modelName: 'Sonos One SL', ip: '1.2.3.4');

  const tuned = RoomCalibration(available: true, enabled: true);
  const untuned = RoomCalibration(available: false, enabled: false);

  // Three standalone speakers, nothing bonded anywhere.
  final free = SonosSystem(
    groups: [
      for (final u in [a, b, c])
        ZoneGroup(coordinatorUuid: u, members: [
          ZoneGroupMember(uuid: u, zoneName: 'Room $u'),
        ]),
    ],
    devicesByUuid: {a: dev(a, 'Keuken'), b: dev(b, 'Bureau'), c: dev(c, 'Hal')},
  );

  PickerContext ctx({required bool writes, Map<String, RoomCalibration>? cal}) =>
      PickerContext(
        system: free,
        calibration: cal ?? {a: tuned, b: tuned, c: tuned},
        writes: writes,
      );

  test('pairing two tuned standalone speakers names BOTH of them', () {
    final cost = ctx(writes: true).tuningCost(l10n, {a, b});
    expect(cost.count, 2);
    expect(cost.names, ['Bureau', 'Keuken']);
    expect(ctx(writes: true).warning(l10n, {a, b}), isNotNull,
        reason: 'the flagship destructive action used to warn about nothing');
  });

  test('only the speakers actually in the selection are charged', () {
    expect(ctx(writes: true).tuningCost(l10n, {a, b}).names,
        isNot(contains('Hal')));
  });

  test('an untuned speaker is not named — there is nothing to lose', () {
    final cost = ctx(writes: true, cal: {a: tuned, b: untuned})
        .tuningCost(l10n, {a, b});
    expect(cost.names, ['Keuken']);
    expect(cost.count, 1);
  });

  test('a no-op apply still costs nothing', () {
    expect(ctx(writes: false).tuningCost(l10n, {a, b}).names, isEmpty);
    expect(ctx(writes: false).warning(l10n, {a, b}), isNull);
  });

  group('a dissolve is stated even when nothing is tuned', () {
    // The review step is the only gate before Apply — the removal confirm
    // dialog was deleted in favour of it — and an UNTUNED group priced nothing,
    // so the card said nothing destructive about a dissolve it was causing.
    // Untuned is the common case: Trueplay can't be measured from Android.
    const x = 'RINCON_X01400';
    const y = 'RINCON_Y01400';
    const z = 'RINCON_Z01400';

    final withGroups = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: x, members: const [
          ZoneGroupMember(
            uuid: x,
            zoneName: 'Keuken',
            channelMapSet: '$x:LF,RF;$y:LF,RF;$z:LF,RF',
          ),
        ]),
        ZoneGroup(coordinatorUuid: a, members: const [
          ZoneGroupMember(
            uuid: a,
            zoneName: 'Eetkamer',
            channelMapSet: '$a:LF,LF;$b:RF,RF',
          ),
        ]),
      ],
      devicesByUuid: {
        x: dev(x, 'Keuken'),
        y: dev(y, 'Keuken'),
        z: dev(z, 'Keuken'),
        a: dev(a, 'Eetkamer'),
        b: dev(b, 'Eetkamer'),
      },
    );

    // Every speaker read, and read as UNTUNED — so tuningCost names nobody.
    PickerContext untunedCtx() => PickerContext(
          system: withGroups,
          calibration: {for (final u in [x, y, z, a, b]) u: untuned},
          writes: true,
        );

    test('taking a member of a multi-speaker group names the group', () {
      final c = untunedCtx();
      expect(c.tuningCost(l10n, {y}).names, isEmpty,
          reason: 'nothing tuned — this is the case that went silent');
      expect(c.dissolveNote(l10n, {y}), contains('Keuken'));
    });

    test('a stereo pair breaks up too, and the card has to say so', () {
      // It reads as self-evident only next to a heading that NAMES the pair.
      // The review card has no heading, and for an untuned pair it was the
      // only gate before an Apply that dissolves a live bond.
      expect(untunedCtx().dissolveNote(l10n, {b}), contains('Eetkamer'));
    });

    test('a home theater source is named even though it survives the take', () {
      // Third case: an HT does NOT break up, it shrinks. It still has to be
      // named — every one of its members loses its tuning (Q20), and nothing
      // else on the card mentions a second entity at all.
      const barU = 'RINCON_BAR01400';
      const satU = 'RINCON_SAT01400';
      final withHt = SonosSystem(
        groups: [
          ZoneGroup(coordinatorUuid: barU, members: const [
            ZoneGroupMember(
              uuid: barU,
              zoneName: 'Woonkamer',
              htSatChanMapSet: '$barU:CC;$satU:LR',
            ),
          ]),
        ],
        devicesByUuid: {
          barU: dev(barU, 'Woonkamer'),
          satU: dev(satU, 'Woonkamer'),
        },
      );
      final note = PickerContext(
        system: withHt,
        calibration: {for (final u in [barU, satU]) u: untuned},
        writes: true,
      ).dissolveNote(l10n, {satU});
      expect(note, isNotNull);
      expect(note, contains('Woonkamer'));
    });

    test('nothing bonded, nothing dissolves', () {
      expect(untunedCtx().dissolveNote(l10n, {}), isNull);
    });

    test('two source groups are both named, once each', () {
      final note = untunedCtx().dissolveNote(l10n, {y, z})!;
      expect(note, contains('Keuken'));
      expect('Keuken'.allMatches(note).length, 1,
          reason: 'one group, not one line per member taken');
    });
  });

  group('a read still in flight claims nothing', () {
    // The reads are kicked off when the flow OPENS, so "no entry yet" was
    // indistinguishable from "asked and got nothing" — and the unknown branch
    // errs loud. Every bond block therefore opened with "Expect to re-tune all
    // of them." and every selected speaker was named at risk, for as long as
    // the reads took, then silently retracted. On Android, where Trueplay
    // cannot be measured at all, that is the only state a user ever sees.
    const x = 'RINCON_X01400';
    const y = 'RINCON_Y01400';
    final paired = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: x, members: const [
          ZoneGroupMember(
            uuid: x,
            zoneName: 'Keuken',
            channelMapSet: '$x:LF,LF;$y:RF,RF',
          ),
        ]),
      ],
      devicesByUuid: {x: dev(x, 'Keuken'), y: dev(y, 'Keuken')},
    );
    final src = paired.memberByUuid(x)!;

    test('the section header withholds the tuning claim while busy', () {
      expect(sectionCost(l10n, paired, src, const {}, busy: {x, y}),
          isNot(contains('re-tune')));
      // The consequences that are true either way still get stated.
      expect(sectionCost(l10n, paired, src, const {}, busy: {x, y}),
          contains('takes it out of this bond'));
    });

    test('a read that actually FAILED still warns — that is the loud case', () {
      expect(sectionCost(l10n, paired, src, const {}), contains('re-tune'));
    });

    test('the note under the list names nobody while busy', () {
      final ctx = PickerContext(
          system: paired, calibration: const {}, writes: true, busy: {x, y});
      expect(ctx.tuningCost(l10n, {y}).names, isEmpty);
      expect(ctx.warning(l10n, {y}), isNull);
      // Same selection once the reads have failed: named, as before.
      expect(
        PickerContext(system: paired, calibration: const {}, writes: true)
            .tuningCost(l10n, {y}).names,
        isNotEmpty,
      );
    });
  });

  test('a line-out box is never named as losing a tuning it cannot hold', () {
    // An Amp / Port / Connect has no drivers of its own, so Sonos never tunes
    // it — "re-tune it in the Sonos app" is advice that cannot be followed.
    const amp = 'RINCON_AMP01400';
    final withAmp = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: amp, members: const [
          ZoneGroupMember(uuid: amp, zoneName: 'Salon'),
        ]),
      ],
      devicesByUuid: {
        amp: SonosDevice(
            uuid: amp,
            roomName: 'Salon',
            modelName: 'Sonos Amp',
            ip: '1.2.3.4'),
      },
    );
    final c = PickerContext(
        system: withAmp, calibration: const {}, writes: true);
    // Unread would otherwise count it as at-risk, which is the safe default
    // everywhere else — but not for a box that cannot hold a tuning at all.
    expect(c.tuningCost(l10n, {amp}).names, isEmpty);
    expect(c.warning(l10n, {amp}), isNull);
  });

  group('the Apply gate and the engine agree about what a write is', () {
    const zone = ZoneGroupMember(
      uuid: a,
      zoneName: 'Keuken',
      channelMapSet: '$a:LF,RF;$b:LF,RF;$c:LF,RF',
    );
    const target = {
      a: GroupChannel.both,
      b: GroupChannel.both,
      c: GroupChannel.both,
    };

    // Through the PRODUCTION rule, not the engine primitive underneath it —
    // the flow's `writes` expression was only ever written out in these tests,
    // so reverting it (to drop-gated, or to a flat false) left them green.
    bool writes(Map<String, GroupChannel> channels, {String? coord = a}) =>
        groupApplyWrites(
            existing: zone, channels: channels, coordUuid: coord);

    test('a CREATE always writes — there is no bond to compare against', () {
      expect(
        groupApplyWrites(existing: null, channels: target, coordUuid: a),
        isTrue,
        reason: 'pairing two tuned standalone speakers costs both tunings',
      );
    });

    test('re-picking the same members in another order is NOT a change', () {
      // The map is built coordinator-first, then in selection order; only the
      // coordinator position is meaningful. An ordered-signature compare read
      // {a,c,b} as a rewrite, so the review card warned and the apply wrote
      // nothing.
      expect(writes(target), isFalse);
    });

    test('moving the coordinator IS a change — it cannot apply in place', () {
      expect(writes(target, coord: b), isTrue);
    });

    test('a channel change is still a change', () {
      expect(
          writes({
            a: GroupChannel.left,
            b: GroupChannel.both,
            c: GroupChannel.both
          }),
          isTrue);
    });

    test('dropping a member is still a change', () {
      expect(writes({a: GroupChannel.both, b: GroupChannel.both}), isTrue);
    });

    test('callers that do not care about the coordinator are unaffected', () {
      // The profile active-match check passes no coordUuid.
      expect(zone.matchesGroupLayout(target), isTrue);
    });
  });
}

/// The HT flow's `writes` wiring, chained through the SAME production functions
/// the flow chains: `buildLayoutMap(preserveExisting: false)` → `diffHtLayout`
/// → `PickerContext(writes: !diff.isNoOp)` → `tuningCost`.
///
/// This is the gap that let the "additive apply priced nothing" bug ship: the
/// widget tests constructed the PickerContext with a hand-written copy of the
/// flow's expression, so reverting the flow to the old drop-gated behaviour
/// left every one of them green.
void _wiring() {
  const beam = 'RINCON_BEAM01400';
  const rear = 'RINCON_REAR01400';
  const newFl = 'RINCON_NEWFL01400';
  const newFr = 'RINCON_NEWFR01400';

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  SonosDevice dev(String uuid, String model, String room) => SonosDevice(
      uuid: uuid, roomName: room, modelName: model, ip: '1.2.3.4');

  final devices = {
    beam: dev(beam, 'Sonos Beam', 'Woonkamer'),
    rear: dev(rear, 'Sonos One SL', 'Woonkamer'),
    // Free speakers, so they still have names of their own — which is what a
    // picker calls them. A bonded one is named by type + channel instead.
    newFl: dev(newFl, 'Sonos Era 100', 'Bureau'),
    newFr: dev(newFr, 'Sonos Era 100', 'Hal'),
  };

  // A tuned 3.1 — bar + one rear — and two free tuned speakers to add as fronts.
  ZoneGroupMember bar(String map) =>
      ZoneGroupMember(uuid: beam, zoneName: 'Woonkamer', htSatChanMapSet: map);
  final current = bar('$beam:CC;$rear:LR');
  final system = SonosSystem(
    groups: [
      ZoneGroup(coordinatorUuid: beam, members: [current]),
      for (final u in [newFl, newFr])
        ZoneGroup(coordinatorUuid: u, members: [
          ZoneGroupMember(uuid: u, zoneName: 'Room'),
        ]),
    ],
    devicesByUuid: devices,
  );

  ({List<String> names, int count}) cost(
      Map<SonosChannel, String> desired) {
    final diff = diffHtLayout(
      current: current,
      target: buildLayoutMap(
        soundbar: current,
        soundbarDevice: devices[beam]!,
        desired: desired,
        subUuids: const [],
        preserveExisting: false,
      ),
    );
    final picker = PickerContext(
      system: system,
      calibration: {
        for (final u in devices.keys)
          u: const RoomCalibration(available: true, enabled: true),
      },
      exceptPrimary: beam,
      // The PRODUCTION rule, not a copy of it. Hand-writing `!diff.isNoOp`
      // here is what let the drop-gated regression stay green in both flows.
      writes: htApplyWrites(diff),
    );
    return picker.tuningCost(l10n, {beam, ...desired.values});
  }

  test('adding two fronts prices the bar, the rear AND both new fronts', () {
    final lost = cost({
      SonosChannel.leftRear: rear,
      SonosChannel.leftFront: newFl,
      SonosChannel.rightFront: newFr,
    });
    expect(lost.count, 4);
    // The bar and the rear are inside the bond, so they are named by TYPE; the
    // two speakers being absorbed are still standalone, so by room name.
    expect(lost.names.join(' '), contains('Beam'));
    expect(lost.names, containsAll(['Bureau', 'Hal']));
  });

  test('re-applying the SAME layout is a no-op and prices nothing', () {
    expect(cost({SonosChannel.leftRear: rear}).names, isEmpty);
  });

  test('an ADDITIVE apply writes, so it is priced', () {
    // The regression this pins: gating on `toRemove.isNotEmpty` reads false
    // here — nothing leaves — and priced the flagship action at zero, while
    // Q20 measured exactly this taking the bar and the rear to available=0.
    final add = diffHtLayout(
      current: current,
      target: buildLayoutMap(
        soundbar: current,
        soundbarDevice: devices[beam]!,
        desired: {
          SonosChannel.leftRear: rear,
          SonosChannel.leftFront: newFl,
          SonosChannel.rightFront: newFr,
        },
        subUuids: const [],
        preserveExisting: false,
      ),
    );
    expect(add.toRemove, isEmpty, reason: 'nothing leaves — that is the trap');
    expect(htApplyWrites(add), isTrue);
  });
}
