import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/front_layout.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/front_surrounds/front_surrounds_flow.dart';
import 'package:sonority/features/group/group_flow.dart';
import 'package:sonority/features/widgets/info_note.dart';
import 'package:sonority/features/widgets/speaker_diagram.dart';
import 'package:sonority/features/widgets/speaker_picker.dart';
import 'package:sonority/l10n/app_localizations.dart';

/// The review step is the ONLY gate on a destructive bond write (there is no
/// confirm dialog), so whatever the apply costs has to be on the same screen as
/// the Apply button. Named, not implied.
///
/// Both regressions guarded here shipped as a silent screen: the HT card
/// returned "Nothing selected yet" for a deselect-everything (which removes
/// every satellite and wipes the whole set's Trueplay), and the group card
/// never mentioned Trueplay at all: three taps behind the note that does.
void main() {
  const bar = 'RINCON_BEAM01400';
  const rearL = 'RINCON_REARL01400';
  const rearR = 'RINCON_REARR01400';
  const sub = 'RINCON_SUB01400';
  const pairL = 'RINCON_ONESL_L01400';
  const pairR = 'RINCON_ONESL_R01400';
  const free = 'RINCON_FREE01400';

  SonosDevice dev(String uuid, String model, [String room = 'Room']) =>
      SonosDevice(uuid: uuid, roomName: room, modelName: model, ip: '1.2.3.4');

  final devices = {
    bar: dev(bar, 'Sonos Beam', 'Woonkamer'),
    rearL: dev(rearL, 'Sonos Play:1'),
    rearR: dev(rearR, 'Sonos Play:1'),
    sub: dev(sub, 'Sonos Sub'),
    pairL: dev(pairL, 'Sonos One SL', 'Eetkamer'),
    pairR: dev(pairR, 'Sonos One SL', 'Eetkamer'),
    free: dev(free, 'Sonos One', 'Keuken'),
  };

  final ht = ZoneGroupMember(
    uuid: bar,
    zoneName: 'Woonkamer',
    htSatChanMapSet: '$bar:CC;$rearL:LR;$rearR:RR;$sub:SW',
    satellites: const [
      SonosSatellite(
          uuid: rearL, zoneName: 'Woonkamer', channels: [SonosChannel.leftRear]),
      SonosSatellite(
          uuid: rearR, zoneName: 'Woonkamer', channels: [SonosChannel.rightRear]),
      SonosSatellite(
          uuid: sub, zoneName: 'Woonkamer', channels: [SonosChannel.sub]),
    ],
  );
  const pair = ZoneGroupMember(
    uuid: pairL,
    zoneName: 'Eetkamer',
    channelMapSet: '$pairL:LF,LF;$pairR:RF,RF',
  );
  const freeRoom = ZoneGroupMember(uuid: free, zoneName: 'Keuken');

  final system = SonosSystem(
    groups: [
      ZoneGroup(coordinatorUuid: bar, members: [ht]),
      ZoneGroup(coordinatorUuid: pairL, members: [pair]),
      ZoneGroup(coordinatorUuid: free, members: [freeRoom]),
    ],
    devicesByUuid: devices,
  );

  const tuned = RoomCalibration(available: true, enabled: true);
  const untuned = RoomCalibration(available: false, enabled: false);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  group('the home-theater review card, with everything deselected', () {
    /// What the flow builds when the user deselects both rears AND the sub on a
    /// live 5.1: nothing picked, but the apply strips the bond.
    HtReviewStep card({required ZoneGroupMember member}) {
      final diff = diffHtLayout(
        current: member,
        target: buildLayoutMap(
          soundbar: member,
          soundbarDevice: devices[bar]!,
          desired: const {},
          preserveExisting: false,
        ),
      );
      return HtReviewStep(
        system: system,
        member: member,
        additions: const {},
        subs: const [],
        diff: diff,
        picker: PickerContext(
          system: system,
          calibration: {
            for (final u in [bar, rearL, rearR, sub]) u: tuned,
          },
          exceptPrimary: bar,
          // The production rule, not a copy of it. This was the last
          // hand-written `!diff.isNoOp` in the suite, which is exactly how the
          // drop-gated regression stayed green. Wiring test lives in
          // destination_cost_test.dart.
          writes: htApplyWrites(diff),
        ),
      );
    }

    testWidgets('names what leaves and whose Trueplay it costs',
        (tester) async {
      await pump(tester, card(member: ht));

      // What leaves: every satellite, named the way the cards are.
      expect(find.textContaining('leave this home theater'), findsOneWidget);
      expect(find.textContaining('Play:1 · Surround L'), findsOneWidget);
      expect(find.textContaining('Play:1 · Surround R'), findsOneWidget);

      // …and the unrecoverable part: RemoveHTSatellite wipes the whole set,
      // the soundbar included.
      expect(find.textContaining('Could lose Trueplay'), findsOneWidget);
      expect(find.textContaining('Beam'), findsWidgets);

      // The gate itself: the cost is not allowed to be swallowed by the
      // empty-selection placeholder while Apply stays enabled.
      expect(find.text('Nothing selected yet — choose speakers above.'),
          findsNothing);
      expect(find.byType(InfoNote), findsOneWidget);
    });

    testWidgets('shows the bare soundbar it would leave behind',
        (tester) async {
      // A diagram with no satellites around the bar is the plainest possible
      // statement of "everything leaves"; suppressing it would only hide it.
      await pump(tester, card(member: ht));
      expect(find.byType(SpeakerDiagram), findsOneWidget);
    });

    testWidgets('a bare soundbar with nothing picked still says so',
        (tester) async {
      // The one case the placeholder is actually right for: no satellites, no
      // selection, so the apply is a no-op and writes nothing.
      const bareBar = ZoneGroupMember(
          uuid: bar, zoneName: 'Woonkamer', htSatChanMapSet: '$bar:CC');
      await pump(tester, card(member: bareBar));
      expect(find.text('Nothing selected yet — choose speakers above.'),
          findsOneWidget);
      expect(find.byType(InfoNote), findsNothing);
    });
  });

  group('the group review card', () {
    GroupReviewStep card(List<String> selected,
            {Map<String, RoomCalibration> calibration = const {}}) =>
        GroupReviewStep(
          mode: GroupMode.zone,
          system: system,
          picker: PickerContext(system: system, calibration: calibration),
          selected: selected,
          channels: const {},
          subUuid: null,
          name: '',
        );

    testWidgets('names the speakers a take costs their Trueplay',
        (tester) async {
      // One half of a tuned stereo pair into a new zone: AddBondedZones cannot
      // absorb, so the pair is genuinely dissolved and BOTH halves pay.
      await pump(
        tester,
        card([pairL, free],
            calibration: const {
              pairL: tuned,
              pairR: tuned,
              free: untuned,
            }),
      );
      expect(find.byType(InfoNote), findsOneWidget);
      expect(find.textContaining('Eetkamer · One SL · L'), findsOneWidget);
      expect(find.textContaining('Eetkamer · One SL · R'), findsOneWidget);
      expect(find.textContaining('could lose their Trueplay'), findsOneWidget);
    });

    testWidgets('an UNTUNED source still states the dissolve', (tester) async {
      // The card replaced the removal confirm dialog, so it is the only gate
      // left, and with nothing tuned there was no cost line and no warning,
      // leaving a silent card over an Apply that dissolves a live pair.
      // Untuned is the COMMON case: Trueplay can't be measured from Android.
      await pump(
        tester,
        card([pairL, free],
            calibration: const {
              pairL: untuned,
              pairR: untuned,
              free: untuned,
            }),
      );
      expect(find.byType(InfoNote), findsOneWidget);
      expect(find.textContaining('Eetkamer'), findsOneWidget);
      expect(find.textContaining('breaks up'), findsOneWidget);
      // ...without inventing a Trueplay cost nobody measured.
      expect(find.textContaining('Trueplay'), findsNothing);
    });

    testWidgets('a take that touches no other bond stays quiet', (tester) async {
      // The genuine quiet case: one free speaker, nothing else disturbed.
      await pump(
        tester,
        card([free], calibration: const {free: untuned}),
      );
      expect(find.byType(InfoNote), findsNothing);
    });
  });
}
