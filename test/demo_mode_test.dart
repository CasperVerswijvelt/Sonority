import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/demo/demo_mode.dart';
import 'package:sonority/state/sonos_controller.dart';

/// The demo channel-map strings are hand-written and typo-prone; assert the
/// fake system classifies exactly as the screenshots need it to.
void main() {
  test('demo system classifies as intended', () {
    // Two home theaters: the flagship 5.1 (Living Room) + a lighter Beam +
    // rears setup (Bedroom).
    expect(demoSystem.homeTheaters.map((m) => m.zoneName).toSet(),
        {'Living Room', 'Bedroom'});
    final ht =
        demoSystem.homeTheaters.firstWhere((m) => m.zoneName == 'Living Room');
    expect(ht.hasDedicatedFronts, isTrue);
    expect(ht.channelAssignments.keys,
        containsAll(SonosChannel.values.where((c) => c != SonosChannel.center)));
    expect(ht.subUuids, hasLength(1));
    // Bedroom is surrounds-only — no dedicated fronts, no sub.
    final bedroom =
        demoSystem.homeTheaters.firstWhere((m) => m.zoneName == 'Bedroom');
    expect(bedroom.hasDedicatedFronts, isFalse);
    expect(bedroom.subUuids, isEmpty);

    expect(demoSystem.stereoPairs.map((m) => m.zoneName), ['Office']);
    expect(demoSystem.zones.map((m) => m.zoneName), ['Upstairs']);
    expect(demoSystem.zones.single.zoneMemberUuids, hasLength(3));
    expect(demoSystem.speakerGroups, hasLength(2));

    // Three standalone rooms feed the group-creation screenshot.
    final standalone =
        demoSystem.allMembers.where((m) => !m.isHomeTheater && !m.isGroup);
    expect(standalone.map((m) => m.zoneName).toSet(),
        {'Kitchen', 'Guest Room', 'Bathroom'});
    expect(demoSystem.zoneableSpeakers, hasLength(3));
    // The Sub is bonded into the HT, so nothing should be offered as bondable.
    expect(demoSystem.bondableSubs, isEmpty);
  });

  test('every uuid in every map resolves to a device', () {
    for (final g in demoSystem.groups) {
      for (final m in g.members) {
        expect(demoSystem.device(m.uuid), isNotNull, reason: m.uuid);
        for (final uuid in [
          ...m.channelMapUuids,
          ...m.channelAssignments.values,
          ...m.satellites.map((s) => s.uuid),
        ]) {
          expect(demoSystem.device(uuid), isNotNull, reason: uuid);
        }
      }
    }
  });

  // Demo mode must not emit real network I/O: the demo IPs are unrouteable
  // TEST-NET, so any client that isn't stubbed silently waits out its full
  // timeout (this leaked twice — SpeakerSettingsClient, then
  // DeviceDescriptionClient — and made a diagnostics bundle take >15min).
  // Every speaker-facing client reached through the overrides must fail fast.
  group('demo mode emits no network I/O', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer(overrides: demoOverrides()));
    tearDown(() => container.dispose());

    test('speaker settings reads resolve instantly and empty', () async {
      final settings = await container
          .read(speakerSettingsProvider)
          .read('192.0.2.10', volume: true)
          .timeout(const Duration(seconds: 1));
      expect(settings.bass, isNull);
      expect(settings.volume, isNull);
      expect(settings.eq, isEmpty);
    });

    test('raw device descriptions fail fast instead of hanging', () {
      // The bundle wraps this in _tryFetch, so throwing is the correct outcome.
      expect(
        container
            .read(sonosRepositoryProvider)
            .rawDeviceDescription('192.0.2.10')
            .timeout(const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('demo profiles resolve cleanly against the demo system', () {
    for (final p in demoProfiles()) {
      for (final e in p.entities) {
        for (final uuid in e.involvedUuids) {
          expect(demoSystem.device(uuid), isNotNull,
              reason: '${p.name}: $uuid');
        }
      }
    }
  });
}
