import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
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
}
