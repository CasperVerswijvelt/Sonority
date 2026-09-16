import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/trueplay_control.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/trueplay_controller.dart';

import 'trueplay_harness.dart';

/// The control reads once from `initState`, but the home-theater page's State
/// survives the nested fronts route, so returning from an apply rebuilds it
/// with a DIFFERENT bonded set. Without a re-read the new member renders from
/// the pre-bond cache (or not at all) until the user pulls to refresh.
void main() {
  const on = RoomCalibration(available: true, enabled: true);

  SonosDevice dev(String uuid) => SonosDevice(
      uuid: uuid, roomName: 'R', modelName: 'Sonos One', ip: '1.2.3.4');
  final a = dev('A');
  final b = dev('B');
  final c = dev('C');

  late RecordingTrueplay fake;

  Future<void> pump(WidgetTester tester, List<SonosDevice> devices) =>
      tester.pumpWidget(ProviderScope(
        overrides: [
          trueplayControllerProvider.overrideWith(() => fake),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TrueplayControl(devices: devices)),
        ),
      ));

  setUp(() => fake = RecordingTrueplay({'A': on, 'B': on, 'C': on}));

  testWidgets('a changed speaker set is re-read', (tester) async {
    await pump(tester, [a, b]);
    await tester.pumpAndSettle();
    expect(fake.loads, [
      {'A', 'B'}
    ]);

    // An apply bonded C in; the page rebuilds with the new set.
    await pump(tester, [a, b, c]);
    await tester.pumpAndSettle();
    expect(fake.loads.last, {'A', 'B', 'C'});
    // …and no provider was touched during the build phase. Riverpod throws for
    // that, and `didUpdateWidget` runs inside it. Calling `load` straight
    // through instead of post-frame threw in every debug build.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unchanged set is not re-read on every rebuild',
      (tester) async {
    await pump(tester, [a, b]);
    await tester.pumpAndSettle();
    await pump(tester, [a, b]);
    await tester.pumpAndSettle();
    expect(fake.loads, hasLength(1));
  });

  testWidgets('reordering the same speakers is not a change', (tester) async {
    await pump(tester, [a, b]);
    await tester.pumpAndSettle();
    await pump(tester, [b, a]);
    await tester.pumpAndSettle();
    expect(fake.loads, hasLength(1), reason: 'membership, not order');
  });
}
