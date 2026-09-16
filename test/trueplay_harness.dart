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
  String Function(SonosDevice)? label,
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
        home: Scaffold(
          body: TrueplayControl(devices: devices, label: label),
        ),
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

/// Records the device sets `load` was asked for, so a test can assert the
/// widget re-read when its speakers changed.
///
/// It also MUTATES provider state synchronously, exactly as the real
/// `TrueplayController.load` does (`_setBusy` runs before its first await).
/// That is load-bearing: Riverpod throws when provider state is touched during
/// the build phase, and `didUpdateWidget` runs inside it — without this the
/// test passes whether the widget defers the read or not.
class RecordingTrueplay extends FakeTrueplay {
  final loads = <Set<String>>[];
  RecordingTrueplay(super.cal, {super.busy});

  @override
  Future<void> load(Iterable<SonosDevice> devices) async {
    final uuids = devices.map((d) => d.uuid).toSet();
    loads.add(uuids);
    state = state.copyWith(busy: {...state.busy, ...uuids});
    await Future<void>.delayed(Duration.zero);
    state = state.copyWith(busy: const {});
  }
}
