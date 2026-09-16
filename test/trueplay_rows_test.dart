import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/label_value_row.dart';
import 'package:sonority/features/widgets/speaker_picker.dart';
import 'package:sonority/features/widgets/trueplay_control.dart';
import 'package:sonority/l10n/app_localizations.dart';

import 'trueplay_harness.dart';

// The per-speaker breakdown behind an aggregate like "5/6 tuned · 0/6 active".
// A user's Arc Ultra report ("not sure why it's 5/6") is the case it answers:
// the counter names how many, never which.
void main() {
  const bar = SonosDevice(
      uuid: 'BAR',
      roomName: 'Living Room HT',
      modelName: 'Sonos Arc Ultra',
      ip: '192.168.1.20');
  const left = SonosDevice(
      uuid: 'LEFT',
      roomName: 'Living Room HT',
      modelName: 'Sonos Five',
      ip: '192.168.1.21');
  const right = SonosDevice(
      uuid: 'RIGHT',
      roomName: 'Living Room HT',
      modelName: 'Sonos One',
      ip: '192.168.1.22');
  const noIp = SonosDevice(
      uuid: 'NOIP', roomName: 'Living Room HT', modelName: 'Sonos Sub');
  const era = SonosDevice(
      uuid: 'ERA',
      roomName: 'Living Room HT',
      modelName: 'Sonos Era 100',
      ip: '192.168.1.23');

  const on = RoomCalibration(available: true, enabled: true);
  const storedOff = RoomCalibration(available: true, enabled: false);
  const none = RoomCalibration(available: false, enabled: false);

  test('maps each speaker to its own state, in the order given', () {
    final rows = trueplayRows(
      [bar, left, right],
      const {'BAR': on, 'LEFT': storedOff, 'RIGHT': none},
    );
    expect(rows.map((r) => r.label), ['Arc Ultra', 'Five', 'One']);
    expect(rows.map((r) => r.state), [
      TrueplayRowState.active,
      TrueplayRowState.tunedOff,
      TrueplayRowState.notTuned,
    ]);
  });

  test('a speaker that could not be read is kept as unknown, not dropped', () {
    // `right` has an IP, so it stays in the on-screen denominator while its
    // failed read keeps it out of the numerator — that is what renders "1/2"
    // rather than "1/1", and without a row the missing speaker is
    // unattributable. `noIp` can't be read either and leaves both counts.
    final rows = trueplayRows([bar, right, noIp], const {'BAR': on});
    expect(rows.length, 3);
    expect(rows[1].state, TrueplayRowState.unknown);
    expect(rows[2].state, TrueplayRowState.unknown);
  });

  testWidgets('the breakdown names the speaker that could not be read',
      (tester) async {
    await tester
        .pumpWidget(trueplayHarness([bar, left], const {'BAR': on}));
    await tester.pumpAndSettle();
    expect(find.text('Five'), findsOneWidget);
    expect(find.text("Couldn't read"), findsOneWidget);
  });

  testWidgets('a set where NOTHING could be read is not called untuned',
      (tester) async {
    await tester.pumpWidget(trueplayHarness([bar, left], const {}));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't read Trueplay from these speakers."),
        findsOneWidget);
    expect(find.textContaining('Not tuned'), findsNothing,
        reason: 'nothing answered, so there is no tuning fact to assert');
    expect(find.byType(LabelValueRow), findsNothing,
        reason: 'nothing was read, so every row would say the same thing');
  });

  testWidgets('a single unreadable speaker is not called "these speakers"',
      (tester) async {
    // What a standalone room passes: devices = [the one speaker]. Reachable
    // right after separating it, since a just-unbonded speaker refuses :1400
    // for ~20-30s and the room page is where the user lands.
    await tester.pumpWidget(trueplayHarness([bar], const {}));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't read Trueplay from this speaker."),
        findsOneWidget);
  });

  testWidgets('no failure copy while the first read is still in flight',
      (tester) async {
    // The reads are scheduled post-frame, so the first build has nothing loaded
    // AND nothing busy — which used to paint the failure line for one frame.
    await tester.pumpWidget(trueplayHarness([bar, left], const {}));
    expect(find.textContaining('Checking…'), findsOneWidget);
    expect(find.textContaining("Couldn't read Trueplay from these speakers."),
        findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('one unreadable speaker does not make the whole set "not tuned"',
      (tester) async {
    // Two of the three answered with no stored tuning; the third never
    // answered at all. "Not tuned" would assert a tuning fact about that one,
    // so the counter runs instead and the breakdown names it.
    await tester.pumpWidget(trueplayHarness(
      [bar, left, right],
      const {'BAR': none, 'LEFT': none},
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('run Trueplay once'), findsNothing);
    expect(find.textContaining('0/3 tuned'), findsOneWidget);
    expect(find.text("Couldn't read"), findsOneWidget);
  });

  testWidgets('the counter reads tuned before active', (tester) async {
    // A stored tuning is the precondition for an active one: leading with
    // "0/3 active" read as though nothing were tuned at all.
    await tester.pumpWidget(trueplayHarness(
      [bar, left, right],
      const {'BAR': storedOff, 'LEFT': storedOff, 'RIGHT': none},
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('2/3 tuned · 0/3 active'), findsOneWidget);
  });

  testWidgets('a fully tuned set that is switched OFF still says it is tuned',
      (tester) async {
    // Every speaker holds a stored tuning and nothing is switched on, so the
    // breakdown stays hidden (they all agree) — "0/3 active" on its own then
    // reads as though nothing were tuned at all.
    await tester.pumpWidget(trueplayHarness(
      [bar, left, right],
      const {'BAR': storedOff, 'LEFT': storedOff, 'RIGHT': storedOff},
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('3/3 tuned · 0/3 active'), findsOneWidget);
    expect(find.byType(LabelValueRow), findsNothing);
  });

  testWidgets('the breakdown stays hidden for a uniform set', (tester) async {
    await tester.pumpWidget(trueplayHarness(
      [bar, left, right],
      const {'BAR': on, 'LEFT': on, 'RIGHT': on},
    ));
    await tester.pumpAndSettle();
    expect(find.byType(LabelValueRow), findsNothing,
        reason: 'an all-active set says everything in its one-line subtitle');
  });

  testWidgets('the breakdown appears when the speakers disagree',
      (tester) async {
    await tester.pumpWidget(trueplayHarness(
      [bar, left, right],
      const {'BAR': on, 'LEFT': on, 'RIGHT': storedOff},
    ));
    await tester.pumpAndSettle();
    expect(find.byType(LabelValueRow), findsNWidgets(3));
  });

  // ONE set has to drive the counter, the rows and the warning gate. A device
  // with no IP was excluded from the counter's denominator but still given a
  // row, so the two disagreed — and worse, it made `incomplete` read a set as
  // complete that had a member nobody had ever asked, which silently dropped
  // the destructive-enable warning.
  testWidgets('a no-IP speaker is counted, not just listed', (tester) async {
    await tester.pumpWidget(trueplayHarness(
      [bar, left, noIp],
      const {'BAR': on, 'LEFT': none},
    ));
    await tester.pumpAndSettle();
    final rows = find.byType(LabelValueRow).evaluate().length;
    expect(rows, 3);
    expect(find.textContaining('1/$rows tuned · 1/$rows active'), findsOneWidget,
        reason: 'the denominator is the number of speakers the rows list');
    // The counter is the visible half. The SAFETY property the widened
    // denominator bought is that a member nobody asked keeps the set
    // INCOMPLETE, so the destructive-enable warning stays on. BAR is switched
    // on here, so the warning is the one-way-door half. Without this, a
    // refactor could keep the counter strings and quietly re-split the gate.
    expect(find.textContaining('may be permanent'), findsOneWidget,
        reason: 'an unasked member keeps the set incomplete, which is the point');
  });

  testWidgets('a no-IP speaker beside an untuned one is never "Tuned · off"',
      (tester) async {
    // The fall-through the split opened: the flat "not tuned" branch failed
    // (one read, two devices) and the single-speaker branch fired instead,
    // because exactly one device had an IP — printing "Tuned · off" for a
    // speaker that answered with no stored tuning at all.
    await tester.pumpWidget(trueplayHarness([noIp, left], const {'LEFT': none}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tuned · off'), findsNothing,
        reason: 'nothing here holds a stored tuning');
    expect(find.textContaining('0/2 tuned'), findsOneWidget);
  });

  testWidgets('no speakers at all says nothing', (tester) async {
    // The room page renders this whenever the topology has a member it never
    // resolved to a device, which made the plural failure line talk about zero
    // speakers.
    await tester.pumpWidget(trueplayHarness(const [], const {}));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't read"), findsNothing);
    expect(find.text('Trueplay'), findsNothing);
  });

  // The case the breakdown exists for, and the one it used to fail: a 5.1 with
  // two MATCHED surrounds. Labelled by type alone both rows read "One SL", so
  // "5/6" still named nobody — the channel was on screen only as row ORDER.
  group('two speakers of the same model', () {
    const barUuid = 'RINCON_BEAM01400';
    const surroundL = 'RINCON_ONESL_L01400';
    const surroundR = 'RINCON_ONESL_R01400';
    const subUuid = 'RINCON_SUB01400';

    const beam = SonosDevice(
        uuid: barUuid,
        roomName: 'Woonkamer',
        modelName: 'Sonos Beam',
        modelNumber: 'S31',
        ip: '192.168.1.30');
    const oneSlLeft = SonosDevice(
        uuid: surroundL,
        roomName: 'Woonkamer',
        modelName: 'Sonos One SL',
        ip: '192.168.1.31');
    const oneSlRight = SonosDevice(
        uuid: surroundR,
        roomName: 'Woonkamer',
        modelName: 'Sonos One SL',
        ip: '192.168.1.32');
    const theSub = SonosDevice(
        uuid: subUuid,
        roomName: 'Woonkamer',
        modelName: 'Sonos Sub',
        ip: '192.168.1.33');

    final system = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: barUuid, members: [
          const ZoneGroupMember(
            uuid: barUuid,
            zoneName: 'Woonkamer',
            htSatChanMapSet:
                '$barUuid:CC;$surroundL:LR;$surroundR:RR;$subUuid:SW',
          ),
        ]),
      ],
      devicesByUuid: const {
        barUuid: beam,
        surroundL: oneSlLeft,
        surroundR: oneSlRight,
        subUuid: theSub,
      },
    );

    late AppLocalizations l10n;
    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    String label(SonosDevice d) => bondedCardTitle(l10n, system, device: d);

    testWidgets('the breakdown tells matched surrounds apart', (tester) async {
      await tester.pumpWidget(trueplayHarness(
        const [beam, oneSlLeft, oneSlRight],
        const {barUuid: on, surroundL: storedOff},
        label: label,
      ));
      await tester.pumpAndSettle();

      final labels = tester
          .widgetList<LabelValueRow>(find.byType(LabelValueRow))
          .map((r) => r.label)
          .toList();
      expect(labels.toSet(), hasLength(labels.length),
          reason: 'every row has to name a different speaker');
      expect(find.text('One SL · Surround L'), findsOneWidget);
      expect(find.text('One SL · Surround R'), findsOneWidget);
      // The one holding the set short is the R surround, and the row says so.
      expect(
        tester.getSemantics(find.byType(LabelValueRow).last),
        matchesSemantics(label: "One SL · Surround R\nCouldn't read"),
      );
    });

    testWidgets('the bar and the sub carry no redundant channel',
        (tester) async {
      // The soundbar is the bond's own coordinator (there is only one) and a
      // Sub's type and channel are the same word — "Beam (Gen 2) · Center" and
      // "Sub · Sub" would both be noise.
      await tester.pumpWidget(trueplayHarness(
        const [beam, oneSlLeft, theSub],
        const {barUuid: on, surroundL: storedOff},
        label: label,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Beam (Gen 2)'), findsOneWidget);
      expect(find.text('Sub'), findsOneWidget);
    });
  });

  testWidgets('a standalone room labels its speaker by type alone',
      (tester) async {
    // What the room page passes: one device and no label override. A standalone
    // speaker holds no channel, so a qualifier would be an empty " · " or a
    // channel it doesn't have — and one speaker renders no breakdown anyway.
    await tester.pumpWidget(trueplayHarness([left], const {}));
    await tester.pumpAndSettle();
    expect(find.byType(LabelValueRow), findsNothing);
    expect(trueplayRows([left, right], const {'LEFT': on}).map((r) => r.label),
        ['Five', 'One'],
        reason: 'unqualified is the default; only a bonded caller overrides it');
  });

  test('a speaker being read right now is checking, not unreadable', () {
    // `unknown` renders "Couldn't read" — a claim that we asked and got
    // nothing. Mid-read we have not asked yet, and the two are only seconds
    // apart in exactly the window a just-bonded speaker refuses :1400.
    final rows = trueplayRows(
      [bar, era],
      const {'BAR': on},
      busy: const {'ERA'},
    );
    expect(rows.map((r) => r.state),
        [TrueplayRowState.active, TrueplayRowState.checking]);
    expect(
      trueplayRows([bar, era], const {'BAR': on}).last.state,
      TrueplayRowState.unknown,
      reason: 'the same row with no read in flight IS unreadable',
    );
  });

  testWidgets('a uniform set that grows by one does not flash the list in',
      (tester) async {
    // The set agrees; the new member is simply pending. Counting it as a
    // disagreeing state would pop the whole breakdown open mid-read and then
    // close it again — and name the new speaker "Couldn't read" while doing so.
    await tester.pumpWidget(trueplayHarness(
      [bar, left, era],
      const {'BAR': on, 'LEFT': on},
      busy: const {'ERA'},
    ));
    // Not pumpAndSettle: `busy` keeps a progress spinner animating, so the
    // scheduler never goes idle. Two pumps = build, then the post-frame read.
    await tester.pump();
    await tester.pump();
    expect(find.byType(LabelValueRow), findsNothing);
    expect(find.text("Couldn't read"), findsNothing);
  });

  testWidgets('once the set really disagrees, a pending row says so', (tester) async {
    // Settled rows disagree (active vs not tuned), so the list is up on its own
    // merits — and the speaker still being read must not borrow a verdict.
    await tester.pumpWidget(trueplayHarness(
      [bar, left, era],
      const {'BAR': on, 'LEFT': none},
      busy: const {'ERA'},
    ));
    // Not pumpAndSettle: `busy` keeps a progress spinner animating, so the
    // scheduler never goes idle. Two pumps = build, then the post-frame read.
    await tester.pump();
    await tester.pump();
    expect(find.byType(LabelValueRow), findsNWidgets(3));
    expect(find.text('Checking…'), findsOneWidget);
    expect(find.text("Couldn't read"), findsNothing);
  });

  testWidgets('a breakdown row announces its speaker and its state together',
      (tester) async {
    // As sibling nodes a screen reader read "Era 100" and "Couldn't read" as
    // unrelated, six times over on a 5.1 system, so the pairing the row exists
    // to show was sighted-only.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(trueplayHarness([bar, era], const {'BAR': on}));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byType(LabelValueRow).last),
        matchesSemantics(label: "Era 100\nCouldn't read"));
    handle.dispose();
  });
}
