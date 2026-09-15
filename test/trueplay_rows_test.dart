import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/label_value_row.dart';
import 'package:sonority/features/widgets/trueplay_control.dart';

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
}
