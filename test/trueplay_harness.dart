import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/trueplay_control.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/trueplay_controller.dart';

/// A [TrueplayControl] wired to canned calibration readings, with no network.
///
/// Shared by the toggle-gate and per-speaker-breakdown tests so there is one
/// fake controller rather than one per test file.
Widget trueplayHarness(
  List<SonosDevice> devices,
  Map<String, RoomCalibration> cal, {
  Set<String> busy = const {},
}) =>
    ProviderScope(
      overrides: [
        trueplayControllerProvider
            .overrideWith(() => FakeTrueplay(cal, busy: busy)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TrueplayControl(devices: devices)),
      ),
    );

class FakeTrueplay extends TrueplayController {
  final Map<String, RoomCalibration> cal;
  final Set<String> busy;
  FakeTrueplay(this.cal, {this.busy = const {}});

  @override
  TrueplayState build() => TrueplayState(byUuid: cal, busy: busy);

  @override
  Future<void> load(Iterable<SonosDevice> devices) async {}
}
