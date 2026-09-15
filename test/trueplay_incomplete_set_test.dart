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
/// no undo, so the ON direction confirms first. OFF never does.
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
    expect(find.textContaining('cannot be recovered'), findsOneWidget);
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

  testWidgets('switching OFF never asks, even on an incomplete set',
      (tester) async {
    // Turning it off has never been measured as destructive, and making someone
    // confirm their way out of a state they are already in would be noise.
    await pump(tester, {a.uuid: active, b.uuid: untuned});
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the row warns about the cost before it is tapped',
      (tester) async {
    await pump(tester, {a.uuid: tuned, b.uuid: untuned});
    expect(find.textContaining('will clear the tunings'), findsOneWidget);
  });
}

class _FakeTrueplay extends TrueplayController {
  final Map<String, RoomCalibration> cal;
  _FakeTrueplay(this.cal);

  @override
  TrueplayState build() => TrueplayState(byUuid: cal);

  @override
  Future<void> load(Iterable<SonosDevice> devices) async {}
}
