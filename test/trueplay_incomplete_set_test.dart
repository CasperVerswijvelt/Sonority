import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/trueplay_control.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/trueplay_controller.dart';

/// ☠️ Measured (EXP-23): `SetRoomCalibrationStatus(1)` on a bonded set where ANY
/// member holds no stored tuning DESTROYS the tunings that are there — four
/// cells, unrecoverably, because a tuning commits for the set as a whole. The
/// same write on a changed-but-COMPLETE set (Q19) was harmless.
///
/// That incomplete state is the normal one right after bonding an untuned
/// speaker, which is exactly when a user reaches for this switch. Turning it
/// OFF has never been destructive, so only the enable is blocked.
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

  testWidgets('an INCOMPLETE set cannot be switched on', (tester) async {
    final s = await pump(tester, {a.uuid: tuned, b.uuid: untuned});
    expect(s.onChanged, isNull,
        reason: 'enabling here would clear A\'s stored tuning for good');
  });

  testWidgets('a COMPLETE set can be switched on', (tester) async {
    final s = await pump(tester, {a.uuid: tuned, b.uuid: tuned});
    expect(s.onChanged, isNotNull);
  });

  testWidgets('an incomplete set that is already ON can still be switched OFF',
      (tester) async {
    // Turning it off has never been measured as destructive, and leaving a user
    // unable to undo a state they are already in would be worse.
    final s = await pump(tester, {a.uuid: active, b.uuid: untuned});
    expect(s.onChanged, isNotNull);
    expect(s.value, isTrue);
  });

  testWidgets('the blocked case says why', (tester) async {
    await pump(tester, {a.uuid: tuned, b.uuid: untuned});
    expect(find.textContaining('clears the ones that are'), findsOneWidget);
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
