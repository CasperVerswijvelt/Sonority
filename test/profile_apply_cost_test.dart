import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/cancellation.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/features/profiles/profile.dart';
import 'package:sonority/features/profiles/profile_controller.dart';
import 'package:sonority/features/profiles/profiles_screen.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/sonos_controller.dart';
import 'package:sonority/state/trueplay_controller.dart';

import 'trueplay_harness.dart';

/// Applying a profile is a destructive bond write like any other, so it has to
/// say what it costs.
///
/// It was the one path in the app that priced nothing: the confirm appeared
/// only when pre-flight found a missing or conflicting speaker, so a clean
/// apply that rebonds a tuned home theater went straight to the progress
/// screen. The rule it now uses is the SAME one the setup flows use, not a
/// second copy: an apply that writes costs every speaker it touches, an
/// unchanged re-apply writes nothing and so costs nothing.
void main() {
  const bar = 'RINCON_BEAM01400';
  const rearL = 'RINCON_REARL01400';
  const rearR = 'RINCON_REARR01400';
  const frontL = 'RINCON_FRONTL01400';
  const zoneA = 'RINCON_ZONEA01400';
  const zoneB = 'RINCON_ZONEB01400';

  SonosDevice dev(String uuid, String model, String room) =>
      SonosDevice(uuid: uuid, roomName: room, modelName: model, ip: '192.0.2.1');

  final devices = {
    bar: dev(bar, 'Sonos Beam', 'Woonkamer'),
    rearL: dev(rearL, 'Sonos Play:1', 'Woonkamer'),
    rearR: dev(rearR, 'Sonos Play:1', 'Woonkamer'),
    frontL: dev(frontL, 'Sonos One', 'Keuken'),
    zoneA: dev(zoneA, 'Sonos One', 'Eetkamer'),
    zoneB: dev(zoneB, 'Sonos One SL', 'Eetkamer'),
  };

  const htMap = '$bar:CC;$rearL:LR;$rearR:RR';
  const zoneMap = '$zoneA:LF,RF;$zoneB:LF,RF';

  final ht = ZoneGroupMember(
    uuid: bar,
    zoneName: 'Woonkamer',
    htSatChanMapSet: htMap,
    satellites: const [
      SonosSatellite(
          uuid: rearL, zoneName: 'Woonkamer', channels: [SonosChannel.leftRear]),
      SonosSatellite(
          uuid: rearR,
          zoneName: 'Woonkamer',
          channels: [SonosChannel.rightRear]),
    ],
  );
  const zone =
      ZoneGroupMember(uuid: zoneA, zoneName: 'Eetkamer', channelMapSet: zoneMap);

  /// The live system: a 5.1-minus-sub home theater, a two-speaker zone, and one
  /// free speaker.
  final system = SonosSystem(
    groups: [
      ZoneGroup(coordinatorUuid: bar, members: [ht]),
      ZoneGroup(coordinatorUuid: zoneA, members: [zone]),
      ZoneGroup(coordinatorUuid: frontL, members: [
        ZoneGroupMember(uuid: frontL, zoneName: 'Keuken'),
      ]),
    ],
    devicesByUuid: devices,
  );

  EntitySnapshot htSnap(String map) => EntitySnapshot(
        kind: EntityKind.homeTheater,
        primaryUuid: bar,
        mapSet: map,
        names: const {bar: 'Woonkamer'},
      );
  EntitySnapshot zoneSnap(String map) => EntitySnapshot(
        kind: EntityKind.zone,
        primaryUuid: zoneA,
        mapSet: map,
        names: const {zoneA: 'Eetkamer'},
      );

  Profile profile(List<EntitySnapshot> entities) =>
      Profile(id: 'p', name: 'Movie night', entities: entities);

  /// Everything tuned, so the cost list is about the RULE, not about reads.
  final tuned = {
    for (final u in devices.keys)
      u: const RoomCalibration(available: true, enabled: true),
  };

  final l10n = lookupAppLocalizations(const Locale('en'));

  group('what a profile apply writes', () {
    test('an unchanged re-apply writes nothing, so it costs nothing', () {
      final p = profile([htSnap(htMap), zoneSnap(zoneMap)]);
      expect(profileApplyWrites(p, system), isFalse);
      expect(profileTuningLost(p, system), isEmpty);
    });

    test('adding a front to the home theater writes, and costs the whole set',
        () {
      final p = profile([htSnap('$htMap;$frontL:LF')]);
      expect(profileApplyWrites(p, system), isTrue);
      // Q20: a purely additive bond took the bar and both rears to
      // available=0, so it is the whole destination, not just the new speaker.
      expect(profileTuningLost(p, system), {bar, rearL, rearR, frontL});
    });

    test('a group whose channels changed writes; the same map does not', () {
      expect(
          profileApplyWrites(
              profile([zoneSnap('$zoneA:LF,LF;$zoneB:RF,RF')]), system),
          isTrue);
      expect(profileApplyWrites(profile([zoneSnap(zoneMap)]), system), isFalse);
    });

    test('a standalone room that is already standalone costs nothing', () {
      final p = profile([
        const EntitySnapshot(
            kind: EntityKind.single,
            primaryUuid: frontL,
            mapSet: null,
            names: {frontL: 'Keuken'}),
      ]);
      expect(profileApplyWrites(p, system), isFalse);
      expect(profileTuningLost(p, system), isEmpty);
    });

    test('breaking a speaker out to a room costs the bond it leaves', () {
      // The zone COORDINATOR is the trap: `ownerOf` answers it with itself, so
      // pricing it against its own bond would hide the group the free
      // dissolves.
      final p = profile([
        const EntitySnapshot(
            kind: EntityKind.single,
            primaryUuid: zoneA,
            mapSet: null,
            names: {zoneA: 'Eetkamer'}),
      ]);
      expect(profileTuningLost(p, system), {zoneA, zoneB});
    });

    test('a blocked entity is skipped, so it prices nothing', () {
      final p = profile([htSnap('$htMap;$frontL:LF')]);
      expect(profileApplyWrites(p, system, skip: {bar}), isFalse);
      expect(profileTuningLost(p, system, skip: {bar}), isEmpty);
    });

    test('several entities price the union of the ones that write', () {
      final p = profile([htSnap('$htMap;$frontL:LF'), zoneSnap(zoneMap)]);
      expect(profileTuningLost(p, system), {bar, rearL, rearR, frontL},
          reason: 'the unchanged zone contributes nothing');
    });

    test('an untuned system is named as costing nothing', () {
      final p = profile([htSnap('$htMap;$frontL:LF')]);
      final cost = profileTuningCost(l10n, p, system, {
        for (final u in devices.keys)
          u: const RoomCalibration(available: false, enabled: false),
      });
      expect(cost.names, isEmpty);
      expect(cost.count, 0);
    });

    test('the names come from the shared speaker naming, bond prefix and all',
        () {
      final p = profile([htSnap('$htMap;$frontL:LF')]);
      final cost = profileTuningCost(l10n, p, system, tuned);
      expect(cost.count, 4);
      expect(cost.names, contains('Woonkamer · Play:1 · Surround L'));
    });
  });

  group('the Apply button asks before it rebonds', () {
    testWidgets('a clean apply that rebonds shows the cost', (tester) async {
      final ctx = await _pump(tester, system, tuned);
      // Not awaited: the future only completes once the dialog is answered.
      final done = ctx.apply(profile([htSnap('$htMap;$frontL:LF')]));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(l10n.profileApplyConfirmTitle('Movie night')),
          findsOneWidget);
      expect(find.textContaining('could lose their Trueplay tuning'),
          findsOneWidget);

      // Declining returns before any write, which also completes `done`.
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await done;
    });

    testWidgets('an unchanged re-apply asks nothing', (tester) async {
      final ctx = await _pump(tester, system, tuned);
      // Left running: a no-op apply goes straight to the progress screen, which
      // stays up until the user closes it, so `done` is not awaitable here.
      ctx.apply(profile([htSnap(htMap), zoneSnap(zoneMap)]));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(l10n.profileApplyConfirmTitle('Movie night')),
          findsNothing);
      // Drain the apply it went straight into.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    });
  });
}

/// A pumped Profiles-tab context: the live system behind a stubbed repository,
/// canned calibration, and a handle to fire the real `applyProfileInteractive`.
class _Ctx {
  final WidgetTester tester;
  final BuildContext context;
  final WidgetRef ref;
  _Ctx(this.tester, this.context, this.ref);

  Future<void> apply(Profile p) => applyProfileInteractive(context, ref, p);
}

Future<_Ctx> _pump(WidgetTester tester, SonosSystem system,
    Map<String, RoomCalibration> cal) async {
  late BuildContext ctx;
  late WidgetRef widgetRef;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sonosRepositoryProvider.overrideWithValue(_StubRepo(system)),
      trueplayControllerProvider.overrideWith(() => FakeTrueplay(cal)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(builder: (c, ref, _) {
        ctx = c;
        widgetRef = ref;
        return const Scaffold(body: SizedBox());
      }),
    ),
  ));
  // Let the controller's initial discover() land, or the apply bails on a null
  // system before it ever prices anything.
  await tester.pump();
  await widgetRef.read(sonosControllerProvider.future);
  await tester.pump();
  return _Ctx(tester, ctx, widgetRef);
}

/// Answers every topology read with one fixed system; writes are no-ops.
class _StubRepo extends SonosRepository {
  final SonosSystem system;
  _StubRepo(this.system);

  @override
  Future<SonosSystem> discover() async => system;

  @override
  Future<SonosSystem> refresh(SonosSystem previous, String ip) async => system;

  @override
  Future<bool> setRoomName({required String ip, required String name}) async =>
      false;

  @override
  Future<void> freeSpeaker(SonosSystem s, String uuid,
      {CancellationToken? cancel}) async {}
}
