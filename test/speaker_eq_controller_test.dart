import 'package:flutter_riverpod/flutter_riverpod.dart';
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

const _bar = SonosDevice(
    uuid: 'RINCON_BAR', roomName: 'Living', modelName: 'Sonos Beam', ip: '1.1.1.1');
const _sub = SonosDevice(
    uuid: 'RINCON_SUB', roomName: 'Living', modelName: 'Sonos Sub', ip: '1.1.1.2');
const _rear = SonosDevice(
    uuid: 'RINCON_REAR', roomName: 'Living', modelName: 'Sonos One', ip: '1.1.1.3');

/// Records every write; answers GetDeviceConfig with a plausible vocabulary.
class _FakeApply extends TrueplayApplyClient {
  final applied = <String, SpectralTuning>{};
  final cleared = <String>[];
  int posts = 0;

  /// Per-RINCON override, so a test can make one member unreadable or
  /// degenerate. `null` means "GetDeviceConfig returns no config".
  final Map<String, TrueplayDeviceConfig?> configs = {};

  /// HTTP status applySpectral returns.
  int status = 200;

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
    return status;
  }

  @override
  Future<int> clearAllTunings({
    required String ip,
    required String rincon,
    bool live = false,
  }) async {
    cleared.add(rincon);
    return 200;
  }
}

/// Models the oracle honestly: a tuning reads back as stored once one has been
/// written and not since cleared. [foreign] stands in for a tuning Sonority did
/// not author (a Trueplay calibration measured in the Sonos app).
class _FakeRepo implements SonosRepository {
  final _FakeApply? apply;
  final bool foreign;
  _FakeRepo({this.apply, this.foreign = false});

  bool get available =>
      foreign ||
      (apply != null && apply!.applied.isNotEmpty && apply!.cleared.isEmpty);

  @override
  Future<RoomCalibration> roomCalibration(String ip) async =>
      RoomCalibration(available: available, enabled: false);

  @override
  Future<void> setRoomCalibration(String ip, bool on) async {}

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container(_FakeApply apply, {_FakeRepo? repo}) {
  final c = ProviderContainer(overrides: [
    trueplayApplyProvider.overrideWithValue(apply),
    eqStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
    sonosRepositoryProvider.overrideWithValue(repo ?? _FakeRepo(apply: apply)),
  ]);
  addTearDown(c.dispose);
  return c;
}

List<double> _cut(int band) =>
    List<double>.filled(kEqBands.length, 0)..[band] = -9;

void main() {
  group('apply', () {
    test('every member is written, including ones the user left flat', () async {
      final apply = _FakeApply();
      final c = _container(apply);
      final ok = await c.read(speakerEqControllerProvider.notifier).apply(
            entityId: 'RINCON_BAR',
            members: const [_bar, _sub, _rear],
            // Only the bar was edited.
            offsets: {'RINCON_BAR': _cut(4)},
          );

      expect(ok, isTrue);
      expect(apply.applied.keys,
          containsAll(['RINCON_BAR', 'RINCON_SUB', 'RINCON_REAR']),
          reason: 'a member missing from the batch drops the whole apply');
      // The untouched members carry a real, do-nothing tuning.
      for (final uuid in ['RINCON_SUB', 'RINCON_REAR']) {
        final ch = apply.applied[uuid]!.channels;
        expect(ch, isNotEmpty);
        expect(ch.every((c) => c.biquads.isNotEmpty), isTrue);
      }
    });

    test('the whole batch shares one session id', () async {
      final apply = _FakeApply();
      final c = _container(apply);
      await c.read(speakerEqControllerProvider.notifier).apply(
            entityId: 'RINCON_BAR',
            members: const [_bar, _sub, _rear],
            offsets: {'RINCON_BAR': _cut(4)},
          );
      expect(apply.applied.values.map((t) => t.deviceId).toSet(), hasLength(1));
    });

    test('each channel is authored against its own reported vocabulary',
        () async {
      final apply = _FakeApply();
      final c = _container(apply);
      await c.read(speakerEqControllerProvider.notifier).apply(
            entityId: 'RINCON_BAR',
            members: const [_bar, _sub],
            offsets: {'RINCON_BAR': _cut(4), 'RINCON_SUB': _cut(0)},
          );

      expect(apply.applied['RINCON_BAR']!.channels.map((c) => c.channel),
          [1, 2, 3]);
      final sub = apply.applied['RINCON_SUB']!.channels;
      expect(sub.map((c) => c.channel), [4]);
      expect(sub.single.biquads.length, lessThanOrEqualTo(8),
          reason: 'the sub reports a lower section ceiling');
    });

    test('offsets are stored so the screen can reopen where it left off',
        () async {
      final apply = _FakeApply();
      final c = _container(apply);
      final n = c.read(speakerEqControllerProvider.notifier);
      await n.apply(
        entityId: 'RINCON_BAR',
        members: const [_bar],
        offsets: {'RINCON_BAR': _cut(4)},
      );
      expect(await n.loadStored('RINCON_BAR'), {'RINCON_BAR': _cut(4)});
    });

    test('a tuning that never stores is reported as a failure', () async {
      final apply = _FakeApply();
      // The oracle never flips: exactly what a silent HTTP 200 looks like.
      final c = _container(apply, repo: _FakeRepo());
      final n = c.read(speakerEqControllerProvider.notifier);
      final ok = await n.apply(
        entityId: 'RINCON_BAR',
        members: const [_bar],
        offsets: {'RINCON_BAR': _cut(4)},
      );
      expect(ok, isFalse);
      expect(c.read(speakerEqControllerProvider).error, isNotNull);
    });
  });

  // Each of these failed SILENTLY before: the speakers answer HTTP 200 and
  // store nothing, so a half-written batch looks exactly like a successful one.
  group('batch integrity', () {
    test('a member that reports no channels aborts before ANY write', () async {
      final apply = _FakeApply()..configs['RINCON_REAR'] = null;
      final c = _container(apply);
      final ok = await c.read(speakerEqControllerProvider.notifier).apply(
            entityId: 'RINCON_BAR',
            members: const [_bar, _rear],
            offsets: {'RINCON_BAR': _cut(4)},
          );
      expect(ok, isFalse);
      expect(apply.posts, 0,
          reason: 'a partial batch stores nothing, and enabling one '
              'destroys the tunings on the members left out');
    });

    test('a degenerate device config aborts rather than applying nothing',
        () async {
      // maxSections 0 would fit to a single passthrough — the oracle still
      // flips, so the user would be told "Applied" for a silent no-op.
      final apply = _FakeApply()
        ..configs['RINCON_BAR'] = const TrueplayDeviceConfig(
            channels: [1], sampleRates: [44100], model: 'S31', maxSections: 0);
      final c = _container(apply);
      final ok = await c.read(speakerEqControllerProvider.notifier).apply(
            entityId: 'RINCON_BAR',
            members: const [_bar],
            offsets: {'RINCON_BAR': _cut(4)},
          );
      expect(ok, isFalse);
      expect(apply.posts, 0);
    });

    test('a zero sample rate aborts', () async {
      final apply = _FakeApply()
        ..configs['RINCON_BAR'] = const TrueplayDeviceConfig(
            channels: [1], sampleRates: [0], model: 'S31', maxSections: 16);
      final c = _container(apply);
      expect(
        await c.read(speakerEqControllerProvider.notifier).apply(
            entityId: 'RINCON_BAR',
            members: const [_bar],
            offsets: {'RINCON_BAR': _cut(4)}),
        isFalse,
      );
      expect(apply.posts, 0);
    });

    test('a non-200 from the write is a failure, not a silent success',
        () async {
      final apply = _FakeApply()..status = 499;
      final c = _container(apply);
      expect(
        await c.read(speakerEqControllerProvider.notifier).apply(
            entityId: 'RINCON_BAR',
            members: const [_bar],
            offsets: {'RINCON_BAR': _cut(4)}),
        isFalse,
      );
    });
  });

  group('stored offsets', () {
    test('a stored curve with the wrong band count is discarded', () async {
      final store = InMemoryKeyValueStore();
      final right = List<double>.filled(kEqBands.length, 0).join(',');
      await store.setString('eq:E',
          '{"v":1,"offsets":{"RINCON_BAR":[1,2,3],"RINCON_REAR":[$right]}}');
      final c = ProviderContainer(overrides: [
        trueplayApplyProvider.overrideWithValue(_FakeApply()),
        eqStoreProvider.overrideWithValue(store),
        sonosRepositoryProvider.overrideWithValue(_FakeRepo()),
      ]);
      addTearDown(c.dispose);
      final loaded =
          await c.read(speakerEqControllerProvider.notifier).loadStored('E');
      expect(loaded.keys, ['RINCON_REAR'],
          reason: 'a short list would RangeError in release, where the '
              'length check is only an assert');
    });
  });

  group('pre-flight', () {
    test('a foreign tuning must be confirmed before it is destroyed', () async {
      final c = _container(_FakeApply(), repo: _FakeRepo(foreign: true));
      expect(
        await c.read(speakerEqControllerProvider.notifier).preflight(
            entityId: 'RINCON_BAR', members: const [_bar, _rear]),
        EqPreflight.wouldOverwrite,
      );
    });

    test('our own tuning needs no confirmation', () async {
      final apply = _FakeApply();
      final c = _container(apply, repo: _FakeRepo(foreign: true));
      final n = c.read(speakerEqControllerProvider.notifier);
      await n.apply(
        entityId: 'RINCON_BAR',
        members: const [_bar],
        offsets: {'RINCON_BAR': _cut(4)},
      );
      expect(
        await n.preflight(entityId: 'RINCON_BAR', members: const [_bar]),
        EqPreflight.ok,
      );
    });

    test('a speaker with nothing to tune is refused', () async {
      final c = _container(_FakeApply());
      expect(
        await c.read(speakerEqControllerProvider.notifier).preflight(
            entityId: 'X', members: const [SonosDevice(
                uuid: 'RINCON_LONE', roomName: 'Sub', modelName: 'Sonos Sub')]),
        EqPreflight.nothingTunable,
      );
    });
  });

  group('live apply scheduling', () {
    test('a burst of slider releases collapses to one write', () async {
      final apply = _FakeApply();
      final c = _container(apply, repo: _FakeRepo(foreign: true));
      final n = c.read(speakerEqControllerProvider.notifier);

      for (var i = 1; i <= 6; i++) {
        n.requestLiveApply(
          entityId: 'RINCON_BAR',
          members: const [_bar],
          offsets: {'RINCON_BAR': _cut(i % kEqBands.length)},
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(apply.posts, 1, reason: 'dragging must not hammer the speakers');
      // And it carried the LAST value, not the first.
      expect(await n.loadStored('RINCON_BAR'),
          {'RINCON_BAR': _cut(6 % kEqBands.length)});
    });

    test('cancelling a pending apply writes nothing', () async {
      final apply = _FakeApply();
      final c = _container(apply, repo: _FakeRepo(foreign: true));
      final n = c.read(speakerEqControllerProvider.notifier);
      n.requestLiveApply(
        entityId: 'RINCON_BAR',
        members: const [_bar],
        offsets: {'RINCON_BAR': _cut(2)},
      );
      n.cancelPending();
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(apply.posts, 0);
    });
  });

  group('remove', () {
    test('clears every member and forgets the stored offsets', () async {
      final apply = _FakeApply();
      final c = _container(apply);
      final n = c.read(speakerEqControllerProvider.notifier);
      await n.apply(
        entityId: 'RINCON_BAR',
        members: const [_bar, _rear],
        offsets: {'RINCON_BAR': _cut(4)},
      );
      final ok = await n.remove(entityId: 'RINCON_BAR', members: const [_bar, _rear]);

      expect(ok, isTrue);
      expect(apply.cleared, ['RINCON_BAR', 'RINCON_REAR']);
      expect(await n.loadStored('RINCON_BAR'), isEmpty);
    });
  });
}
