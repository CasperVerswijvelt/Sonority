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
/// [fake] receives the controller this harness built, so a test can assert on
/// the WRITES it recorded — `Switch.value` is derived from [cal] and therefore
/// reads the same whether or not a toggle fired.
Widget trueplayHarness(
  List<SonosDevice> devices,
  Map<String, RoomCalibration> cal, {
  Set<String> busy = const {},
  void Function(FakeTrueplay)? fake,
}) =>
    ProviderScope(
      overrides: [
        trueplayControllerProvider.overrideWith(() {
          final f = FakeTrueplay(cal, busy: busy);
          fake?.call(f);
          return f;
        }),
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

  /// Every `setEnabled` this fake received, in order.
  final writes = <bool>[];

  FakeTrueplay(this.cal, {this.busy = const {}});

  @override
  TrueplayState build() => TrueplayState(byUuid: cal, busy: busy);

  @override
  Future<void> load(Iterable<SonosDevice> devices) async {}

  @override
  Future<void> setEnabled(Iterable<SonosDevice> devices, bool on) async {
    writes.add(on);
  }
}
