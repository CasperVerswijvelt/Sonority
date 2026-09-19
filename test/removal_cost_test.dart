import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/features/group/group_detail_screen.dart';
import 'package:sonority/features/home_theater/home_theater_screen.dart';
import 'package:sonority/features/widgets/speaker_picker.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/sonos_controller.dart';
import 'package:sonority/state/trueplay_controller.dart';

import 'trueplay_harness.dart';

/// Separate / Remove are the most destructive things in the app: a removal
/// clears the Trueplay of the WHOLE bonded set, not just what leaves (Q20).
///
/// All three confirms used to say nothing about it, so a user could tap
/// Separate on a tuned 5.1, read that the speakers become rooms again, and
/// silently lose every tuning. They now price it through the same model the
/// setup flows use, which also means an UNTUNED set is told nothing: this is a
/// cost line, not a permanent scare line.
void main() {
  const bar = 'RINCON_BEAM01400';
  const rearL = 'RINCON_REARL01400';
  const amp = 'RINCON_AMP01400';
  const zoneA = 'RINCON_ZONEA01400';
  const zoneB = 'RINCON_ZONEB01400';

  SonosDevice dev(String uuid, String model, String room) =>
      SonosDevice(uuid: uuid, roomName: room, modelName: model, ip: '192.0.2.1');

  final devices = {
    bar: dev(bar, 'Sonos Beam', 'Woonkamer'),
    rearL: dev(rearL, 'Sonos Play:1', 'Woonkamer'),
    amp: dev(amp, 'Sonos Amp', 'Woonkamer'),
    zoneA: dev(zoneA, 'Sonos One', 'Eetkamer'),
    zoneB: dev(zoneB, 'Sonos One SL', 'Eetkamer'),
  };

  final ht = ZoneGroupMember(
    uuid: bar,
    zoneName: 'Woonkamer',
    htSatChanMapSet: '$bar:CC;$rearL:LR;$amp:LF,RF',
    satellites: const [
      SonosSatellite(
          uuid: rearL, zoneName: 'Woonkamer', channels: [SonosChannel.leftRear]),
      SonosSatellite(uuid: amp, zoneName: 'Woonkamer', channels: [
        SonosChannel.leftFront,
        SonosChannel.rightFront,
      ]),
    ],
  );
  const zone = ZoneGroupMember(
    uuid: zoneA,
    zoneName: 'Eetkamer',
    channelMapSet: '$zoneA:LF,RF;$zoneB:LF,RF',
  );

  final system = SonosSystem(
    groups: [
      ZoneGroup(coordinatorUuid: bar, members: [ht]),
      ZoneGroup(coordinatorUuid: zoneA, members: [zone]),
    ],
    devicesByUuid: devices,
  );

  final tuned = {
    for (final u in devices.keys)
      u: const RoomCalibration(available: true, enabled: true),
  };
  final untuned = {
    for (final u in devices.keys)
      u: const RoomCalibration(available: false, enabled: false),
  };

  final l10n = lookupAppLocalizations(const Locale('en'));

  group('removalTuningWarning', () {
    test('names every member of a tuned bond, never just what leaves', () {
      final w = removalTuningWarning(l10n, system, tuned, ht);
      expect(w, isNotNull);
      expect(w, contains('Beam'));
      expect(w, contains('Play:1'));
      expect(w, contains('could lose'));
    });

    test('an Amp is never named: a line-out box holds no tuning', () {
      expect(removalTuningWarning(l10n, system, tuned, ht), isNot(contains('Amp')));
    });

    test('an untuned bond gets no sentence at all', () {
      expect(removalTuningWarning(l10n, system, untuned, ht), isNull);
      expect(removalTuningWarning(l10n, system, untuned, zone), isNull);
    });

    test('a speaker still being read is not claimed about', () {
      expect(
          removalTuningWarning(l10n, system, const {}, zone,
              busy: {zoneA, zoneB}),
          isNull);
    });

    test('a tuned group names both halves', () {
      final w = removalTuningWarning(l10n, system, tuned, zone);
      expect(w, contains('One,'));
      expect(w, contains('One SL'));
    });
  });

  group('the confirms carry it', () {
    Widget app(Widget home, Map<String, RoomCalibration> cal) => ProviderScope(
          overrides: [
            sonosRepositoryProvider.overrideWithValue(_StubRepo(system)),
            trueplayControllerProvider.overrideWith(() => FakeTrueplay(cal)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        );

    Future<void> open(WidgetTester tester, Widget home,
        Map<String, RoomCalibration> cal, String button) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(home, cal));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(button));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('separating a tuned group says what it costs', (tester) async {
      await open(tester, const GroupDetailScreen(uuid: zoneA), tuned,
          l10n.groupSeparate);
      expect(find.text(l10n.groupSeparateConfirmTitle), findsOneWidget);
      expect(find.textContaining('could lose'), findsOneWidget);
    });

    testWidgets('separating an untuned group says nothing extra',
        (tester) async {
      await open(tester, const GroupDetailScreen(uuid: zoneA), untuned,
          l10n.groupSeparate);
      expect(find.text(l10n.groupSeparateConfirmMessage), findsOneWidget);
      expect(find.textContaining('could lose'), findsNothing);
    });

    testWidgets('separating a tuned home theater says what it costs',
        (tester) async {
      await open(tester, const HomeTheaterScreen(soundbarUuid: bar), tuned,
          l10n.htSeparate);
      expect(find.text(l10n.htSeparateConfirmTitle), findsOneWidget);
      expect(find.textContaining('could lose'), findsOneWidget);
    });

    testWidgets('separating an untuned home theater says nothing extra',
        (tester) async {
      await open(tester, const HomeTheaterScreen(soundbarUuid: bar), untuned,
          l10n.htSeparate);
      expect(find.text(l10n.htSeparateMessage), findsOneWidget);
      expect(find.textContaining('could lose'), findsNothing);
    });
  });
}

/// Answers every topology read with one fixed system; no writes reach it.
class _StubRepo extends SonosRepository {
  final SonosSystem system;
  _StubRepo(this.system);

  @override
  Future<SonosSystem> discover() async => system;

  @override
  Future<SonosSystem> refresh(SonosSystem previous, String ip) async => system;
}
