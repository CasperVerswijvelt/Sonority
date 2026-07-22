import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/demo/demo_mode.dart';

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
