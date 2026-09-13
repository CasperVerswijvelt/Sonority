import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/widgets/speaker_picker.dart';

/// Taking speakers out of an existing bond, and what each case costs in room
/// calibration. Every expectation here is a hardware-measured row of EXP-23
/// (`docs/trueplay-re/protocols/EXP-23-…`), not a guess:
///
///  * stereo pair, both halves taken → nothing lost (the pair dissolves under
///    `AddHTSatellite` and both keep their tuning)
///  * stereo pair, one half taken    → only the speaker LEFT BEHIND loses it
///  * home theater / group, anything → EVERY member loses it, taken ones too
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

  group('tuningLostByTaking — EXP-23 measured rows', () {
    test('pair, BOTH halves taken → nothing loses its tuning', () {
      expect(system.tuningLostByTaking(pair, {pairL, pairR}), isEmpty);
    });

    test('pair, ONE half taken → only the leftover loses it', () {
      expect(system.tuningLostByTaking(pair, {pairL}), {pairR});
      expect(system.tuningLostByTaking(pair, {pairR}), {pairL});
    });

    test('home theater → every member loses it, including the one taken', () {
      expect(system.tuningLostByTaking(ht, {rear}), {bar, rear, sub});
    });

    test('a home-theater source is never absorbed, so the whole HT pays', () {
      // Absorbing out of another home theater was never measured (one soundbar
      // on the test system), so it is not assumed: the speaker gets freed
      // first, exactly as in a group flow. This is why BOTH pickers say the
      // same thing about a home-theater source.
      expect(system.canAbsorbFrom(ht), isFalse);
      expect(system.tuningLostByTaking(ht, {rear}), {bar, rear, sub});
      expect(system.tuningLostByTaking(ht, {rear}, destinationAbsorbs: false),
          {bar, rear, sub},
          reason: 'same either way — the destination cannot rescue it');
    });

    test('pair and zone ARE absorbable', () {
      expect(system.canAbsorbFrom(pair), isTrue);
      expect(system.canAbsorbFrom(zone), isTrue);
    });

    test('zone → only the COORDINATOR keeps it (Q10, 2 cycles)', () {
      // Measured: absorbing both members of a live zone into a home theater
      // kept the zone coordinator's tuning and lost the other member's, with
      // the same decay series on both cycles.
      expect(system.tuningLostByTaking(zone, {zoneA, zoneB}), {zoneB});
      expect(system.tuningLostByTaking(zone, {zoneB}), {zoneB});
    });

    test('a GROUP destination cannot absorb, so the whole source bond pays', () {
      // AddBondedZones is accepted and silently no-ops on a speaker bonded
      // elsewhere (Q11, 2 cycles), so the speaker is freed first — which
      // dissolves the source bond and costs every member, pair or not.
      expect(
        system.tuningLostByTaking(pair, {pairL, pairR},
            destinationAbsorbs: false),
        {pairL, pairR},
        reason: 'the pair is dissolved, not absorbed',
      );
      expect(
        system.tuningLostByTaking(zone, {zoneA}, destinationAbsorbs: false),
        {zoneA, zoneB},
      );
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
}
