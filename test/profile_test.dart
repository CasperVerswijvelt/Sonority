import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/speaker_settings.dart';
import 'package:sonority/features/profiles/profile.dart';

void main() {
  const beam = 'RINCON_BEAM01400';
  const fl = 'RINCON_FL01400';
  const fr = 'RINCON_FR01400';
  const sub = 'RINCON_SUB01400';

  test('snapshots a home theater: kind, map, involved uuids', () {
    final m = ZoneGroupMember(
      uuid: beam,
      zoneName: 'Woonkamer',
      htSatChanMapSet: '$beam:CC;$fl:LF;$fr:RF;$sub:SW',
    );
    final snap = EntitySnapshot.fromMember(m);
    expect(snap.kind, EntityKind.homeTheater);
    expect(snap.primaryUuid, beam);
    expect(snap.label, 'Woonkamer');
    expect(snap.involvedUuids, {beam, fl, fr, sub});
  });

  test('snapshots a stereo pair from its ChannelMapSet', () {
    final m = ZoneGroupMember(
      uuid: fl,
      zoneName: 'Keuken',
      channelMapSet: '$fl:LF,LF;$fr:RF,RF',
    );
    final snap = EntitySnapshot.fromMember(m);
    expect(snap.kind, EntityKind.stereoPair);
    expect(snap.involvedUuids, {fl, fr});
  });

  test('snapshots a single unbonded speaker', () {
    final m = ZoneGroupMember(uuid: fl, zoneName: 'Bureau');
    final snap = EntitySnapshot.fromMember(m);
    expect(snap.kind, EntityKind.single);
    expect(snap.mapSet, isNull);
    expect(snap.involvedUuids, {fl});
  });

  test('Profile round-trips through JSON', () {
    final profile = Profile(
      id: 'p1',
      name: 'Cinema',
      entities: [
        EntitySnapshot.fromMember(ZoneGroupMember(
          uuid: beam,
          zoneName: 'Woonkamer',
          htSatChanMapSet: '$beam:CC;$fl:LF;$fr:RF;$sub:SW',
        )),
        EntitySnapshot.fromMember(
            ZoneGroupMember(uuid: 'RINCON_X01400', zoneName: 'Bureau')),
      ],
    );
    final back = Profile.fromJson(
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>);
    expect(back.id, 'p1');
    expect(back.name, 'Cinema');
    expect(back.entities.length, 2);
    expect(back.entities.first.kind, EntityKind.homeTheater);
    expect(back.entities.first.mapSet, '$beam:CC;$fl:LF;$fr:RF;$sub:SW');
    expect(back.entities[1].kind, EntityKind.single);
    expect(back.entities.first.names[beam], 'Woonkamer');
  });

  test('captured speaker settings round-trip through JSON', () {
    final snap = EntitySnapshot.fromMember(ZoneGroupMember(
      uuid: fl,
      zoneName: 'Bureau',
    )).copyWith(settings: {
      fl: const SpeakerSettings(
          bass: 3,
          treble: -2,
          loudness: true,
          eq: {'NightMode': 1, 'AudioDelay': 2},
          volume: 25),
    });
    final profile = Profile(id: 'p2', name: 'Tuned', entities: [snap]);
    final back = Profile.fromJson(
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>);
    final s = back.entities.first.settings[fl]!;
    expect(s.bass, 3);
    expect(s.treble, -2);
    expect(s.loudness, isTrue);
    expect(s.volume, 25);
    expect(s.eq, {'NightMode': 1, 'AudioDelay': 2});
    expect(back.entities.first.settingsSummary, 'Audio settings + volume saved');
    expect(back.hasAudioSettings, isTrue);
    expect(back.hasVolume, isTrue);
  });

  test('legacy profile without a settings key deserializes to empty', () {
    final legacy = {
      'id': 'p3',
      'name': 'Old',
      'entities': [
        {
          'kind': 'single',
          'primaryUuid': fl,
          'mapSet': null,
          'names': {fl: 'Bureau'},
        }
      ],
    };
    final back = Profile.fromJson(legacy);
    expect(back.entities.first.settings, isEmpty);
    expect(back.entities.first.settingsSummary, '');
    // Omitted from JSON when empty.
    expect(back.entities.first.toJson().containsKey('settings'), isFalse);
  });

  test('settingsSummary reflects audio-only vs volume-only', () {
    final base = EntitySnapshot.fromMember(ZoneGroupMember(uuid: fl, zoneName: 'x'));
    expect(base.copyWith(settings: {fl: const SpeakerSettings(bass: 1)}).settingsSummary,
        'Audio settings saved');
    expect(
        base.copyWith(settings: {fl: const SpeakerSettings(volume: 10)}).settingsSummary,
        'Volume saved');
  });
}
