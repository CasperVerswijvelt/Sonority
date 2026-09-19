import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/custom_eq.dart';
import 'package:sonority/data/sonos/key_value_store.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/trueplay_apply.dart';
import 'package:sonority/data/sonos/trueplay_codec.dart';
import 'package:sonority/state/sonos_controller.dart'
    show sonosRepositoryProvider;
import 'package:sonority/state/speaker_eq_controller.dart';

/// Fakes for the EQ path, shared by the controller tests and the screen's
/// widget tests — the screen test's whole point is to assert on the writes that
/// did or didn't go out, which needs the same recording fakes.

const barDevice = SonosDevice(
    uuid: 'RINCON_BAR', roomName: 'Living', modelName: 'Sonos Beam', ip: '1.1.1.1');
const subDevice = SonosDevice(
    uuid: 'RINCON_SUB', roomName: 'Living', modelName: 'Sonos Sub', ip: '1.1.1.2');
const rearDevice = SonosDevice(
    uuid: 'RINCON_REAR', roomName: 'Living', modelName: 'Sonos One', ip: '1.1.1.3');

/// Records every write; answers GetDeviceConfig with a plausible vocabulary.
class FakeApply extends TrueplayApplyClient {
  final applied = <String, SpectralTuning>{};
  final cleared = <String>[];
  int posts = 0;

  /// Per-RINCON override, so a test can make one member unreadable or
  /// degenerate. `null` means "GetDeviceConfig returns no config".
  final Map<String, TrueplayDeviceConfig?> configs = {};

  /// HTTP status applySpectral returns.
  int status = 200;

  /// IPs written to, so the fake oracle can answer per speaker.
  final appliedIps = <String>{};
  final clearedIps = <String>{};

  @override
  Future<({int status, TrueplayDeviceConfig? config, String raw})>
      readDeviceConfig({
    required String ip,
    required String rincon,
    String apiKey = kSonosGuestApiKey,
  }) async {
    if (configs.containsKey(rincon)) {
      return (status: 200, config: configs[rincon], raw: '');
    }
    // The sub reports its own single channel at its own (much lower) rate.
    final cfg = rincon == 'RINCON_SUB'
        ? const TrueplayDeviceConfig(
            channels: [4],
            sampleRates: [kSubSampleRate],
            model: 'S13',
            maxSections: 8)
        : const TrueplayDeviceConfig(
            channels: [1, 2, 3],
            sampleRates: [44100, 44100, 44100],
            model: 'S31',
            maxSections: 16);
    return (status: 200, config: cfg, raw: '');
  }

  @override
  Future<int> applySpectral({
    required String ip,
    required String rincon,
    required SpectralTuning tuning,
    bool live = false,
  }) async {
    posts++;
    applied[rincon] = tuning;
    if (status == 200) appliedIps.add(ip);
    return status;
  }

  @override
  Future<int> clearAllTunings({
    required String ip,
    required String rincon,
    bool live = false,
  }) async {
    cleared.add(rincon);
    clearedIps.add(ip);
    return 200;
  }
}

/// Models the oracle honestly and PER SPEAKER: a tuning reads back as stored on
/// the speakers it was actually written to, and `enabled` only flips when
/// something calls `setRoomCalibration`. Both matter — a fake that ignores `ip`
/// cannot catch a poll that checks one member, and one whose `setRoomCalibration`
/// is an empty body cannot catch the enable step going missing entirely.
class FakeRepo implements SonosRepository {
  final FakeApply? apply;

  /// A tuning Sonority did not author (measured in the Sonos app).
  final bool foreign;

  /// IPs whose enable call should fail, to exercise a partial enable.
  final Set<String> refuseEnable;

  /// IPs that stop answering `GetRoomCalibrationStatus` the moment their enable
  /// is attempted — a speaker that drops off during the enable step, which is
  /// the *same* speaker whose enable fails. Both halves of the real failure.
  final Set<String> vanishOnEnable;

  final enabled = <String>{};
  final enableCalls = <({String ip, bool on})>[];
  final _gone = <String>{};

  FakeRepo({
    this.apply,
    this.foreign = false,
    this.refuseEnable = const {},
    this.vanishOnEnable = const {},
  });

  bool _availableAt(String ip) =>
      foreign ||
      (apply != null &&
          apply!.appliedIps.contains(ip) &&
          !apply!.clearedIps.contains(ip));

  @override
  Future<RoomCalibration> roomCalibration(String ip) async {
    if (_gone.contains(ip)) throw StateError('connection refused');
    return RoomCalibration(
      available: _availableAt(ip),
      enabled: enabled.contains(ip),
    );
  }

  @override
  Future<void> setRoomCalibration(String ip, bool on) async {
    enableCalls.add((ip: ip, on: on));
    if (vanishOnEnable.contains(ip)) {
      _gone.add(ip);
      throw StateError('connection refused');
    }
    if (refuseEnable.contains(ip)) throw StateError('refused');
    on ? enabled.add(ip) : enabled.remove(ip);
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// One nominated IP never reports a stored tuning, however many times it is
/// written — a satellite that answers 200 and commits nothing.
class PartialStoreRepo implements SonosRepository {
  final FakeApply apply;
  final String blindIp;
  PartialStoreRepo(this.apply, this.blindIp);

  @override
  Future<RoomCalibration> roomCalibration(String ip) async => RoomCalibration(
        available: ip != blindIp && apply.appliedIps.contains(ip),
        enabled: false,
      );
  @override
  Future<void> setRoomCalibration(String ip, bool on) async {}
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Every calibration read throws, as a speaker does for ~20-30s after bonding.
class UnreadableRepo implements SonosRepository {
  @override
  Future<RoomCalibration> roomCalibration(String ip) async =>
      throw StateError('connection refused');
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The overrides every EQ test needs: the :1443 client, the durable store and
/// the repository behind the oracle.
List<Override> eqOverrides(FakeApply apply, {SonosRepository? repo}) => [
      trueplayApplyProvider.overrideWithValue(apply),
      eqStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      sonosRepositoryProvider.overrideWithValue(repo ?? FakeRepo(apply: apply)),
    ];

ProviderContainer eqContainer(FakeApply apply, {SonosRepository? repo}) {
  final c = ProviderContainer(overrides: eqOverrides(apply, repo: repo));
  addTearDown(c.dispose);
  return c;
}
