import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/profiles/profile.dart';
import 'package:sonority/features/profiles/profile_controller.dart';

/// The three cases where "is this speaker bonded elsewhere?" was answered
/// differently by two pieces of code that had to agree.
void main() {
  const a = 'RINCON_A01400';
  const b = 'RINCON_B01400';
  const c = 'RINCON_C01400';
  const bar = 'RINCON_BEAM01400';
  const sub1 = 'RINCON_SUB101400';
  const sub2 = 'RINCON_SUB201400';

  SonosDevice dev(String uuid, [String model = 'Sonos One']) =>
      SonosDevice(uuid: uuid, roomName: 'Room', modelName: model, ip: '1.2.3.4');

  SonosSystem sys(List<ZoneGroupMember> members, Iterable<String> uuids) =>
      SonosSystem(
        groups: [
          for (final m in members)
            ZoneGroup(coordinatorUuid: m.uuid, members: [m]),
        ],
        devicesByUuid: {for (final u in uuids) u: dev(u)},
      );

  group('an orphaned zone survivor', () {
    // A zone partner went away; Sonos leaves the survivor Invisible, still
    // carrying the whole stale ChannelMapSet. `memberByUuid` filters Invisible
    // members, so the owner never resolves, but `freeSpeaker` walks the
    // members unfiltered and DOES recover it with a targeted separate.
    final orphaned = sys([
      const ZoneGroupMember(
        uuid: a,
        zoneName: 'Keuken',
        channelMapSet: '$a:LF,RF;$b:LF,RF',
        invisible: true,
      ),
    ], [a]);

    test('is not standalone, and its owner does not resolve', () {
      expect(orphaned.isStandalone(a), isFalse);
      expect(orphaned.ownerOf(a), isNotNull);
      expect(orphaned.memberByUuid(orphaned.ownerOf(a)!), isNull,
          reason: 'the survivor is Invisible, so allMembers excludes it');
    });

    test('must still be freed: the regression that skipped the recovery', () {
      expect(
          orphaned.mustFreeBeforeBonding(a, keep: const {}, absorbing: false),
          isTrue);
      expect(orphaned.mustFreeBeforeBonding(a, keep: const {}, absorbing: true),
          isTrue,
          reason: 'absorbing out of a bond we cannot classify is unmeasured');
    });

    test('a speaker with NO owner at all is still not freed', () {
      // A soundbar: `ownerOf` returns null and there is nothing to free it from.
      final htSys = sys([
        ZoneGroupMember(
          uuid: bar,
          zoneName: 'Woonkamer',
          htSatChanMapSet: '$bar:CC;$a:LR',
          satellites: const [
            SonosSatellite(
                uuid: a, zoneName: 'Woonkamer', channels: [SonosChannel.leftRear]),
          ],
        ),
      ], [bar, a]);
      expect(htSys.ownerOf(bar), isNull);
      expect(
          htSys.mustFreeBeforeBonding(bar, keep: const {}, absorbing: true),
          isFalse);
    });
  });

  group('dual subs', () {
    // `channelAssignments` is keyed by CHANNEL, so `…:SW;…:SW` collapses to one
    // uuid. The satellite list normally covers the second, but it briefly
    // VANISHES after any bonding change (gotcha #1), which is the window the
    // authoritative-map read exists for.
    final midSettle = sys([
      const ZoneGroupMember(
        uuid: bar,
        zoneName: 'Woonkamer',
        htSatChanMapSet: '$bar:CC;$sub1:SW;$sub2:SW',
        satellites: [], // the transient window
      ),
    ], [bar, sub1, sub2]);

    test('both subs read as bonded with an empty satellite list', () {
      expect(midSettle.isStandalone(sub1), isFalse);
      expect(midSettle.isStandalone(sub2), isFalse,
          reason: 'the FIRST SW entry is the one the second overwrites');
    });

    test('both subs are part of the bond, so both are priced', () {
      final m = midSettle.memberByUuid(bar)!;
      expect(midSettle.bondMemberUuids(m), {bar, sub1, sub2});
    });

    test('both subs resolve an owner, so both get freed before a bond', () {
      // Where the value is CONSUMED. `isStandalone` reading right is not
      // enough: `mustFreeBeforeBonding` short-circuits on `ownerOf == null`,
      // so the sub the channel key dropped was reported standalone-owned,
      // skipped its free, and let a bond target a speaker the bar still holds.
      expect(midSettle.ownerOf(sub1), bar);
      expect(midSettle.ownerOf(sub2), bar);
      for (final s in [sub1, sub2]) {
        expect(
          midSettle.mustFreeBeforeBonding(s, keep: const {}, absorbing: false),
          isTrue,
          reason: '$s is bonded to $bar and must be freed first',
        );
      }
    });
  });

  group('entityFreePlan agrees with the pre-flight', () {
    // Profile captured a PAIR {a,b}; the user has since grown it to {a,b,c}.
    final grown = sys([
      const ZoneGroupMember(
        uuid: a,
        zoneName: 'Keuken',
        channelMapSet: '$a:LF,RF;$b:LF,RF;$c:LF,RF',
      ),
    ], [a, b, c]);

    const captured = EntitySnapshot(
      kind: EntityKind.stereoPair,
      primaryUuid: a,
      mapSet: '$a:LF,LF;$b:RF,RF',
      names: {a: 'Keuken', b: 'Keuken R'},
    );

    test('the target drops a live member, so nothing is kept', () {
      final plan = entityFreePlan(captured, grown);
      expect(plan.uuids, {a, b});
      expect(plan.keep, isEmpty,
          reason: 'AddBondedZones cannot drop c: the bond must dissolve first');
      expect(plan.absorbing, isFalse);
    });

    test('pre-flight reports the conflict the apply would write', () {
      final issues = preflightProfile(
        const Profile(id: 'p', name: 'P', entities: [captured]),
        grown,
      );
      expect(issues.single.conflicts, isNotEmpty,
          reason: 'the apply dissolves the live zone; the user must be asked');
    });

    test('an unchanged group is a no-op, and reports nothing', () {
      final live = sys([
        const ZoneGroupMember(
          uuid: a,
          zoneName: 'Keuken',
          channelMapSet: '$a:LF,LF;$b:RF,RF',
        ),
      ], [a, b]);
      expect(entityFreePlan(captured, live).uuids, isEmpty);
      expect(
          preflightProfile(
            const Profile(id: 'p', name: 'P', entities: [captured]),
            live,
          ).single.conflicts,
          isEmpty);
    });

    test('a single room bonded elsewhere is a conflict. It used to be skipped',
        () {
      const single =
          EntitySnapshot(
              kind: EntityKind.single,
              primaryUuid: a,
              mapSet: null,
              names: {a: 'Keuken'});
      final plan = entityFreePlan(single, grown);
      expect(plan.uuids, {a}, reason: 'apply frees the primary unconditionally');
      expect(
          preflightProfile(
            const Profile(id: 'p', name: 'P', entities: [single]),
            grown,
          ).single.conflicts,
          isNotEmpty);
    });
  });
}
