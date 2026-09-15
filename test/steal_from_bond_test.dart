import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/speaker_picker.dart';
import 'package:sonority/l10n/app_localizations.dart';

/// Taking speakers out of an existing bond: who is offered, and what the take
/// costs in room calibration.
///
/// The cost is the WHOLE source bond, every time. Storage is kinder — EXP-23
/// measured that an absorbed speaker keeps its coefficients — but they come
/// back switched off and the write that switches them on destroys them, so no
/// screen credits an absorb. What the absorb is still worth is skipping the
/// free, which is `canAbsorbFrom`.
void main() {
  const bar = 'RINCON_BEAM01400';
  const sub = 'RINCON_SUB01400';
  const rear = 'RINCON_REAR01400';
  const pairL = 'RINCON_ONESL_L01400';
  const pairR = 'RINCON_ONESL_R01400';
  const zoneA = 'RINCON_ZONEA01400';
  const zoneB = 'RINCON_ZONEB01400';

  SonosDevice dev(String uuid, String model) =>
      SonosDevice(uuid: uuid, roomName: 'Room', modelName: model, ip: '1.2.3.4');

  final devices = {
    bar: dev(bar, 'Sonos Beam'),
    sub: dev(sub, 'Sonos Sub'),
    rear: dev(rear, 'Sonos Play:1'),
    pairL: dev(pairL, 'Sonos One SL'),
    pairR: dev(pairR, 'Sonos One SL'),
    zoneA: dev(zoneA, 'Sonos One'),
    zoneB: dev(zoneB, 'Sonos Play:1'),
  };

  final ht = ZoneGroupMember(
    uuid: bar,
    zoneName: 'Woonkamer',
    htSatChanMapSet: '$bar:CC;$rear:LR;$sub:SW',
    satellites: const [
      SonosSatellite(
          uuid: rear, zoneName: 'Woonkamer', channels: [SonosChannel.leftRear]),
      SonosSatellite(
          uuid: sub, zoneName: 'Woonkamer', channels: [SonosChannel.sub]),
    ],
  );
  const pair = ZoneGroupMember(
    uuid: pairL,
    zoneName: 'Eetkamer',
    channelMapSet: '$pairL:LF,LF;$pairR:RF,RF',
  );
  const zone = ZoneGroupMember(
    uuid: zoneA,
    zoneName: 'Keuken',
    channelMapSet: '$zoneA:LF,RF;$zoneB:LF,RF',
  );

  final system = SonosSystem(
    groups: [
      ZoneGroup(coordinatorUuid: bar, members: [ht]),
      ZoneGroup(coordinatorUuid: pairL, members: [pair]),
      ZoneGroup(coordinatorUuid: zoneA, members: [zone]),
    ],
    devicesByUuid: devices,
  );

  group('stealableSpeakers', () {
    test('offers speakers bonded elsewhere, minus soundbars and subs', () {
      final got = system.stealableSpeakers().map((d) => d.uuid).toSet();
      expect(got, {rear, pairL, pairR, zoneA, zoneB});
      expect(got, isNot(contains(bar)), reason: 'soundbars have their own flow');
      expect(got, isNot(contains(sub)), reason: 'subs have their own picker');
    });

    test('excludes the bond being configured', () {
      final got =
          system.stealableSpeakers(exceptPrimary: bar).map((d) => d.uuid);
      expect(got, isNot(contains(rear)));
      expect(got, containsAll([pairL, pairR]));
    });

    test('a pair half hidden from allMembers is still offered', () {
      // pairR is Invisible in real topology — it only exists in the primary's
      // ChannelMapSet, which is exactly why the old bondableSpeakers missed it.
      expect(system.stealableSpeakers().map((d) => d.uuid), contains(pairR));
    });
  });

  group('what taking a speaker costs, and what an absorb is still worth', () {
    // Storage is kinder than this: an absorbed speaker keeps its coefficients
    // (Q7/Q9/Q10). They come back switched OFF and the only write that switches
    // them on destroys them, so no screen credits an absorb — the whole source
    // bond pays, whatever the source's kind.
    test('a pair pays in full, however many halves are taken', () {
      expect(system.tuningLostBySelection(selected: {pairL, pairR}),
          {pairL, pairR});
      expect(system.tuningLostBySelection(selected: {pairL}), {pairL, pairR});
    });

    test('a zone pays in full — taking one member dissolves it (Q12)', () {
      expect(system.tuningLostBySelection(selected: {zoneB}), {zoneA, zoneB});
      expect(system.tuningLostBySelection(selected: {zoneA, zoneB}),
          {zoneA, zoneB});
    });

    test('a home theater pays in full, the speaker taken included', () {
      expect(system.tuningLostBySelection(selected: {rear}), {bar, rear, sub});
    });

    test('every source touched is charged, plus what the destination costs',
        () {
      expect(
        system
            .tuningLostBySelection(selected: {pairL, zoneB}, alsoLosing: {bar}),
        {pairL, pairR, zoneA, zoneB, bar},
      );
    });

    // What an absorb IS still worth: skipping the free. This is the part
    // `_freeConflicts` acts on, and it is measured per source kind.
    test('a pair and a zone can be absorbed from, a home theater cannot', () {
      expect(system.canAbsorbFrom(pair), isTrue);
      expect(system.canAbsorbFrom(zone), isTrue);
      expect(system.canAbsorbFrom(ht), isFalse,
          reason: 'never measured — one soundbar on the test system');
    });
  });

  group('who needs freeing before a new group can form', () {
    // Regression, caught on hardware: createGroup used
    // `ownerOf(u)` + `!involved.contains(owner)` to spot conflicts. For a
    // group's COORDINATOR `ownerOf` returns that speaker's OWN uuid, so the
    // coordinator read as unbonded, no free step ran, and `AddBondedZones`
    // dissolved the source zone without forming the new pair. `isStandalone`
    // is the right question.
    test('a zone COORDINATOR is not standalone', () {
      expect(system.isStandalone(zoneA), isFalse,
          reason: 'ownerOf(zoneA) returns zoneA itself — the trap');
      expect(system.ownerOf(zoneA), zoneA);
    });

    test('every other bonded role is caught too', () {
      for (final u in [zoneB, pairL, pairR, rear, sub, bar]) {
        expect(system.isStandalone(u), isFalse, reason: u);
      }
    });

    test('a free speaker needs no freeing', () {
      const free = 'RINCON_FREE01400';
      final sys = SonosSystem(
        groups: [
          ZoneGroup(coordinatorUuid: free, members: const [
            ZoneGroupMember(uuid: free, zoneName: 'Kitchen'),
          ]),
        ],
        devicesByUuid: {free: dev(free, 'Sonos One')},
      );
      expect(sys.isStandalone(free), isTrue);
    });
  });

  group('mustFreeBeforeBonding — what each apply path decides to free', () {
    // This predicate is where every bug in this feature lived: three controller
    // paths each hand-rolled it and each got it wrong differently. One of them
    // dissolved a live zone on real hardware.
    test('a free speaker never needs freeing', () {
      const free = 'RINCON_FREE01400';
      final sys = SonosSystem(
        groups: [
          ZoneGroup(coordinatorUuid: free, members: const [
            ZoneGroupMember(uuid: free, zoneName: 'Kitchen'),
          ]),
        ],
        devicesByUuid: {free: dev(free, 'Sonos One')},
      );
      expect(
          sys.mustFreeBeforeBonding(free, keep: const {}, absorbing: true),
          isFalse);
    });

    test('the target keeps its OWN members — an unchanged re-apply frees none',
        () {
      for (final u in [bar, rear, sub]) {
        expect(
            system.mustFreeBeforeBonding(u,
                keep: {bar, rear, sub}, absorbing: true),
            isFalse,
            reason: u);
      }
    });

    test('an HT target ABSORBS a pair or zone member — no free', () {
      for (final u in [pairL, pairR, zoneA, zoneB]) {
        expect(
            system.mustFreeBeforeBonding(u, keep: const {}, absorbing: true),
            isFalse,
            reason: u);
      }
    });

    test('a GROUP target absorbs nothing — every bonded speaker is freed', () {
      for (final u in [pairL, pairR, zoneA, zoneB, rear]) {
        expect(
            system.mustFreeBeforeBonding(u, keep: const {}, absorbing: false),
            isTrue,
            reason: u);
      }
    });

    test('an HT SOURCE is freed even by an HT target (never measured)', () {
      expect(
          system.mustFreeBeforeBonding(rear, keep: const {}, absorbing: true),
          isTrue);
    });

    test('re-applying an HT unchanged frees NOTHING', () {
      // Regression: an HT is not absorbable, so without the bar's own members
      // in `keep` every satellite it already has reads as needing a free — a
      // no-op re-apply would strip the bond and wipe its Trueplay. `keep` must
      // be the bar plus its live bond, which is what both HT paths now pass.
      final keep = {bar, ...system.bondMemberUuids(ht)};
      for (final u in [rear, sub]) {
        expect(system.mustFreeBeforeBonding(u, keep: keep, absorbing: true),
            isFalse,
            reason: '$u is already in this home theater');
      }
      // …while a speaker from elsewhere in the same apply still gets freed.
      expect(system.mustFreeBeforeBonding(zoneA, keep: keep, absorbing: true),
          isFalse,
          reason: 'a zone IS absorbable');
      expect(system.mustFreeBeforeBonding(pairL, keep: keep, absorbing: false),
          isTrue,
          reason: 'a group target absorbs nothing');
    });

    test('the coordinator trap: ownerOf returns self, isStandalone does not',
        () {
      // The exact hardware-caught bug — an owner-based test skipped this.
      expect(system.ownerOf(zoneA), zoneA);
      expect(
          system.mustFreeBeforeBonding(zoneA, keep: const {}, absorbing: false),
          isTrue);
    });
  });

  test('bondMemberUuids covers satellites and channel-map members', () {
    expect(system.bondMemberUuids(ht), {bar, rear, sub});
    expect(system.bondMemberUuids(pair), {pairL, pairR});
  });

  group('pickerSections', () {
    List<SonosDevice> cands(List<String> ids) =>
        [for (final id in ids) devices[id]!];

    test('available first, then one block per source bond', () {
      final s = pickerSections(
        system: system,
        candidates: cands([pairL, rear, zoneA, pairR, zoneB]),
        exceptPrimary: bar, // configuring the home theater
      );
      expect(s.map((x) => x.isAvailable), [
        true, // `rear` is already in THIS HT: free to keep
        false, // the pair
        false, // the zone
      ]);
      expect(s[0].devices.map((d) => d.uuid), [rear],
          reason: "the configured entity's own members are available, not a "
              'separate block — keeping one costs nothing');
      expect(s[1].source?.uuid, pairL);
      expect(s[1].devices.map((d) => d.uuid), [pairL, pairR],
          reason: 'both halves land under one heading, in candidate order');
      expect(s[2].devices.map((d) => d.uuid), [zoneA, zoneB]);
    });

    test('a free speaker gets the available block', () {
      final free = SonosDevice(
          uuid: 'RINCON_FREE01400',
          roomName: 'Kitchen',
          modelName: 'Sonos One',
          ip: '1.2.3.9');
      final sys = SonosSystem(
        groups: [
          ZoneGroup(coordinatorUuid: free.uuid, members: [
            ZoneGroupMember(uuid: free.uuid, zoneName: 'Kitchen'),
          ]),
        ],
        devicesByUuid: {free.uuid: free},
      );
      final s = pickerSections(system: sys, candidates: [free]);
      expect(s.single.isAvailable, isTrue);
      expect(s.single.source, isNull);
    });

    test('empty blocks are dropped, so one source means one block', () {
      final s = pickerSections(
        system: system,
        candidates: cands([pairL, pairR]),
      );
      expect(s, hasLength(1),
          reason: 'a single block renders without a heading at all');
      expect(s.single.isAvailable, isFalse);
    });
  });

  group('one cost model, every screen in the HT flow', () {
    late AppLocalizations l10n;
    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    // The PickerContext the flow builds. `writes` is `!diff.isNoOp` there:
    // ANY write costs this home theater its own tuning, not only one that
    // drops a satellite (CLAUDE.md Q20 — a pure add took the bar and both
    // rears to available=0). A no-op writes nothing, so it costs nothing.
    PickerContext ctx({required bool writes}) => PickerContext(
          system: system,
          calibration: {
            for (final u in [bar, sub, rear, pairL, pairR, zoneA, zoneB])
              u: const RoomCalibration(available: true, enabled: true),
          },
          exceptPrimary: bar,
          ownBondMembers:
              writes ? system.bondMemberUuids(ht) : const <String>{},
        );

    // The speaker list's note and the review card are rendered from the SAME
    // method with the same selection; the bar is skipped either way by
    // exceptPrimary. They disagreed once — that is what this pins.
    test('the picker note and the review card name the same speakers', () {
      final c = ctx(writes: true);
      final picked = {pairL, pairR}; // what the speaker step has selected
      final resulting = {bar, ...picked}; // what the review step prices
      expect(c.tuningCost(l10n, resulting).names,
          c.tuningCost(l10n, picked).names);
      expect(c.warning(l10n, picked), isNotNull,
          reason: 'the note cannot stay silent while the header says cleared');
    });

    test('an UNREAD speaker keeps the note in step with the header', () {
      // The header errs safe on a speaker it could not read; the note has to
      // err the same way, or the screen says "cleared" and names nobody.
      final c = PickerContext(
        system: system,
        calibration: const {pairR: RoomCalibration(available: false, enabled: false)},
        exceptPrimary: bar,
      );
      expect(sectionCost(l10n, system, pair, c.calibration), contains('cleared'),
          reason: 'pairL was never read');
      expect(c.warning(l10n, {pairL}), isNotNull);
    });

    test('taking a WHOLE pair still costs it — no screen credits an absorb',
        () {
      // Storage is kinder (both halves absorbed ⇒ nothing lost), but a
      // surviving tuning comes back off and cannot be switched on again, so the
      // copy promises nothing. Q15/Q16.
      expect(ctx(writes: true).tuningCost(l10n, {bar, pairL, pairR}).count, 5,
          reason: 'both pair halves plus the whole home theater');
    });

    test('a purely ADDITIVE apply still prices this home theater', () {
      // Nothing dropped: the old gate said "costs nothing", Q20 says the bar
      // and the rears go to available=0 anyway.
      final lost = ctx(writes: true).tuningCost(l10n, {bar, rear, sub, pairL});
      expect(lost.count, 5);
      expect(lost.names.join(' '), contains('Beam'));
    });

    test('a NO-OP apply costs nothing', () {
      expect(ctx(writes: false).tuningCost(l10n, {bar, rear, sub}).names,
          isEmpty);
    });
  });

  group('the steal warning names losers, and pluralises on speakers', () {
    const p1a = 'RINCON_P1A01400';
    const p1b = 'RINCON_P1B01400';
    final twins = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: p1a, members: const [
          ZoneGroupMember(
            uuid: p1a,
            zoneName: 'Boven',
            channelMapSet: '$p1a:LF,RF;$p1b:LF,RF',
          ),
        ]),
      ],
      devicesByUuid: {
        p1a: dev(p1a, 'Sonos Play:1'),
        p1b: dev(p1b, 'Sonos Play:1'),
      },
    );

    /// Two identical models in one zone share a card title, so the name list
    /// collapses to one entry while TWO speakers actually lose their tuning.
    Future<String?> warn(Set<String> taking) async {
      return PickerContext(
        system: twins,
        calibration: const {
          p1a: RoomCalibration(available: true, enabled: true),
          p1b: RoomCalibration(available: true, enabled: true),
        },
      ).warning(await AppLocalizations.delegate.load(const Locale('en')), taking);
    }

    test('one label, two speakers ⇒ plural wording', () async {
      final w = await warn({p1a});
      expect(w, contains('Boven · Play:1'));
      expect(w, contains('their Trueplay'),
          reason: 'both Play:1s lose it even though they share a label');
    });

    test('a single tuned speaker ⇒ singular wording', () async {
      final w = PickerContext(
        system: twins,
        calibration: const {
          p1a: RoomCalibration(available: true, enabled: true),
          p1b: RoomCalibration(available: false, enabled: false),
        },
      ).warning(
          await AppLocalizations.delegate.load(const Locale('en')), {p1a});
      expect(w, contains('its Trueplay'),
          reason: 'only p1a holds a tuning, so one speaker pays');
    });
  });

  group('naming the keeps/loses lists', () {
    Future<({List<String> names, int count})> named(Set<String> uuids) async =>
        tunedSpeakers(
          await AppLocalizations.delegate.load(const Locale('en')),
          system,
          uuids,
          const {
            bar: RoomCalibration(available: true, enabled: true),
            rear: RoomCalibration(available: true, enabled: false),
            pairR: RoomCalibration(available: true, enabled: true),
            pairL: RoomCalibration(available: false, enabled: false),
          },
          ownBond: bar,
        );

    test('the configured home theater by type, other bonds by name', () async {
      final got = await named({bar, rear, pairR});
      expect(got.names, [
        'Eetkamer · One SL · R', // another bond: say whose it is
        'Play:1 · Surround L', // this HT's own satellite: type and role
        'Beam', // the bar itself, named like its satellites
      ]..sort());
      expect(got.count, 3);
    });

    test('a speaker READ as untuned is never named', () async {
      final got = await named({pairL});
      expect(got.names, isEmpty);
      expect(got.count, 0);
    });

    test('a speaker that could not be read counts as at risk', () async {
      // No entry at all means the Trueplay read FAILED — routine inside the
      // ~20-30s window after an unbond, or for an offline speaker. Dropping it
      // silently shortened the at-risk list while the section header above it,
      // reading the same map, already said the bond's tuning gets cleared.
      final got = await named({sub});
      expect(got.count, 1);
      expect(got.names, ['Sub']);
    });
  });

  group('the section header sentence tracks the measured cost model', () {
    late AppLocalizations l10n;
    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    const tuned = RoomCalibration(available: true, enabled: true);
    const untuned = RoomCalibration(available: false, enabled: false);
    final all = {
      for (final u in [bar, sub, rear, pairL, pairR, zoneA, zoneB]) u: tuned,
    };

    String cost(ZoneGroupMember src, [Map<String, RoomCalibration>? cal]) =>
        sectionCost(l10n, system, src, cal ?? all);

    // EXP-23 Q15/Q16: a tuning that survives an absorb comes back switched off,
    // and switching it on destroys it — no safe delay, and the role-preserving
    // case died too. So NO source may promise retention, however much of it
    // survives in storage. These assertions are the only thing stopping that
    // promise creeping back into the prose.
    test('no source promises that anything keeps its Trueplay', () {
      for (final src in [pair, zone, ht]) {
        expect(cost(src), contains('cleared'));
        expect(cost(src), isNot(contains('keep')));
      }
    });

    test('a zone still says the group breaks up, which nothing else shows', () {
      expect(cost(zone), contains('breaks up the whole group'));
      expect(cost(pair), isNot(contains('breaks up')));
    });

    test('nothing tuned in the bond ⇒ no Trueplay sentence at all', () {
      final none = {for (final u in all.keys) u: untuned};
      expect(cost(pair, none), l10n.pickerSectionLeavesBond);
      // ...but a zone still warns that picking dissolves it, tuning or not.
      expect(cost(zone, none), contains('breaks up the whole group'));
      expect(cost(zone, none), isNot(contains('Trueplay')));
    });

    test('an UNREAD speaker is not the same as an untuned one', () {
      // A Trueplay read that failed leaves no entry. Suppressing the cost then
      // would be the one wrong direction: silence about a destructive write.
      expect(cost(pair, const {pairL: untuned}), contains('cleared'));
    });
  });

  group('a bonded speaker is never titled by the bond\'s name', () {
    // Sonos absorbs a bonded speaker's room name into the bond's, so BOTH
    // halves report the same name. Titling a picker card by room name there
    // printed that one name on every member: two adjacent cards reading
    // "Woonkamer", told apart only by their Left/Right toggle. The card falls
    // back to the room name whenever `titleOverride` is null, so null IS the
    // bug — it is not an absence of opinion.
    Future<String?> title(
      WidgetTester tester,
      PickerContext ctx,
      SonosDevice d,
    ) async {
      String? got;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          got = ctx.titleOverride(context, d);
          return const SizedBox.shrink();
        }),
      ));
      return got;
    }

    testWidgets("the CONFIGURED entity's own members title by type", (t) async {
      // `rear` is already a satellite of the home theater being configured, so
      // it is listed as available (keeping it costs nothing) — but its name is
      // still the bar's.
      final ctx = PickerContext(
        system: system,
        calibration: const {},
        exceptPrimary: bar,
      );
      expect(await title(t, ctx, devices[rear]!), 'Play:1',
          reason: 'null would fall back to the home theater\'s room name');
    });

    testWidgets('a group edit titles its own members by type too', (t) async {
      // The same path via `exceptPrimary: editUuid`: two Play:1s in one zone,
      // both carrying the zone's name, are the observed duplicate-title case.
      const a = 'RINCON_TWINA01400';
      const b = 'RINCON_TWINB01400';
      SonosDevice twin(String uuid) => SonosDevice(
          uuid: uuid,
          roomName: 'Boven',
          modelName: 'Sonos Play:1',
          ip: '1.2.3.4');
      final twins = SonosSystem(
        groups: [
          ZoneGroup(coordinatorUuid: a, members: const [
            ZoneGroupMember(
              uuid: a,
              zoneName: 'Boven',
              channelMapSet: '$a:LF,RF;$b:LF,RF',
            ),
          ]),
        ],
        devicesByUuid: {a: twin(a), b: twin(b)},
      );
      final ctx =
          PickerContext(system: twins, calibration: const {}, exceptPrimary: a);
      for (final u in [a, b]) {
        expect(await title(t, ctx, twins.device(u)!), 'Play:1',
            reason: 'both would otherwise read "Boven"');
      }
    });

    testWidgets('another bond still says which channel it holds', (t) async {
      // Regression guard: under a heading that names the source bond, the
      // channel is what tells two same-model cards apart.
      final ctx = PickerContext(
        system: system,
        calibration: const {},
        exceptPrimary: bar,
      );
      expect(await title(t, ctx, devices[pairR]!), 'One SL · R');
      expect(await title(t, ctx, devices[rear]!), isNot(contains('·')),
          reason: "no heading names this speaker's bond, and the live channel "
              'would contradict the L/R toggle the user is editing with');
    });

    testWidgets('a free speaker keeps its own room name', (t) async {
      const free = 'RINCON_FREE01400';
      final d = SonosDevice(
          uuid: free,
          roomName: 'Kitchen',
          modelName: 'Sonos One',
          ip: '1.2.3.9');
      final sys = SonosSystem(
        groups: [
          ZoneGroup(coordinatorUuid: free, members: const [
            ZoneGroupMember(uuid: free, zoneName: 'Kitchen'),
          ]),
        ],
        devicesByUuid: {free: d},
      );
      final ctx = PickerContext(system: sys, calibration: const {});
      expect(await title(t, ctx, d), isNull,
          reason: 'it has a name of its own — the card shows it');
    });
  });
}
