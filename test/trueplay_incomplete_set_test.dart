import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/trueplay_control.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/trueplay_controller.dart';

/// ☠️ Measured (EXP-23): switching Trueplay ON while any bonded member holds no
/// stored tuning clears the tunings that ARE there — four cells, unrecoverably,
/// because a tuning commits for the set as a whole. The same write on a
/// changed-but-COMPLETE set (Q19, ×2) was harmless.
///
/// It is deliberately NOT blocked. The measurement is one household, the
/// mechanism is undetermined ("the write destroyed it" and "it was already dead
/// and the write cleared a stale flag" are indistinguishable), and users on
/// other hardware sit in this state and toggle on purpose. What the evidence
/// justifies is not letting it happen by ACCIDENT: the loss is silent and has
/// no undo, so the ON direction confirms first — and so does the OFF direction
/// while the set is short, because the only way back is the destructive write.
void main() {
  const tuned = RoomCalibration(available: true, enabled: false);
  const active = RoomCalibration(available: true, enabled: true);
  const untuned = RoomCalibration(available: false, enabled: false);

  SonosDevice dev(String uuid) => SonosDevice(
      uuid: uuid, roomName: 'R', modelName: 'Sonos One', ip: '1.2.3.4');
  final a = dev('RINCON_A01400');
  final b = dev('RINCON_B01400');

  Future<Switch> pump(
      WidgetTester tester, Map<String, RoomCalibration> cal) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trueplayControllerProvider.overrideWith(() => _FakeTrueplay(cal)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TrueplayControl(devices: [a, b])),
      ),
    ));
    await tester.pump();
    return tester.widget<Switch>(find.byType(Switch));
  }

  testWidgets('an INCOMPLETE set is NOT blocked — the switch still works',
      (tester) async {
    final s = await pump(tester, {a.uuid: tuned, b.uuid: untuned});
    expect(s.onChanged, isNotNull,
        reason: 'one household of evidence does not justify removing a control');
  });

  testWidgets('switching ON an incomplete set asks first, and names the cost',
      (tester) async {
    await pump(tester, {a.uuid: tuned, b.uuid: untuned});
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    // Scoped to the dialog: the row behind it carries the same warning, which
    // is the point — you are told before you tap, and again before it writes.
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('could destroy')),
        findsOneWidget);
  });

  testWidgets('declining the confirm does not write', (tester) async {
    await pump(tester, {a.uuid: tuned, b.uuid: untuned});
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('a COMPLETE set switches on with no confirm at all',
      (tester) async {
    await pump(tester, {a.uuid: tuned, b.uuid: tuned});
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'nothing is at stake, so asking would be noise');
  });

  testWidgets('switching OFF on an incomplete set ALSO asks — it is a one-way door',
      (tester) async {
    // Not because the (0) write is known to destroy anything; it is not, and on
    // an incomplete set it is untested. But the only way back is the (1) write,
    // which IS destructive here — so turning it off is effectively
    // irreversible, and being told that afterwards is no use.
    await pump(tester, {a.uuid: active, b.uuid: untuned});
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Turn off Trueplay?'), findsOneWidget);
    expect(find.textContaining('turning it back on later'), findsOneWidget);
  });

  testWidgets('switching OFF a COMPLETE set never asks', (tester) async {
    await pump(tester, {a.uuid: active, b.uuid: active});
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'it can be turned straight back on, so nothing is at stake');
  });

  testWidgets('the row warns about the cost before it is tapped',
      (tester) async {
    await pump(tester, {a.uuid: tuned, b.uuid: untuned});
    expect(find.textContaining('could destroy the tunings'), findsOneWidget);
  });

  testWidgets('the row warns that OFF is one-way when it is currently on',
      (tester) async {
    await pump(tester, {a.uuid: active, b.uuid: untuned});
    expect(find.textContaining('may be permanent'), findsOneWidget);
  });

  // A warning must only ever describe a write the user can issue. With NOTHING
  // tuned the switch is disabled, so there is no write and nothing to destroy —
  // yet the row said "could destroy the tunings that are left" beside a dead
  // switch. Trueplay can only be MEASURED in the iOS Sonos app, so on Android
  // this is the only Trueplay row the user ever sees.
  testWidgets('an UNTUNED set warns about nothing — there is no write to make',
      (tester) async {
    final s = await pump(tester, {a.uuid: untuned, b.uuid: untuned});
    expect(s.onChanged, isNull, reason: 'nothing to switch on');
    expect(find.textContaining('could destroy'), findsNothing);
    expect(find.textContaining('Not tuned'), findsOneWidget);
  });

  // Same rule while the reads are still in flight: the switch is disabled, so
  // "Checking… · turning it on could destroy…" was up to 8s of warning about a
  // set that may turn out to be complete.
  testWidgets('a set still being read warns about nothing either',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trueplayControllerProvider
            .overrideWith(() => _FakeTrueplay(const {}, busy: {a.uuid, b.uuid})),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TrueplayControl(devices: [a, b])),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('could destroy'), findsNothing);
    expect(find.textContaining('Checking'), findsOneWidget);
  });
}

class _FakeTrueplay extends TrueplayController {
  final Map<String, RoomCalibration> cal;
  final Set<String> busy;
  _FakeTrueplay(this.cal, {this.busy = const {}});

  @override
  TrueplayState build() => TrueplayState(byUuid: cal, busy: busy);

  @override
  Future<void> load(Iterable<SonosDevice> devices) async {}
}
