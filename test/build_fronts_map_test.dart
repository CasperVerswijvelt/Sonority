import 'package:flutter_test/flutter_test.dart';
import 'package:soyes/data/models/sonos_models.dart';
import 'package:soyes/data/sonos/sonos_repository.dart';

void main() {
  final repo = SonosRepository();

  const beamUuid = 'RINCON_BEAM01400';
  const flUuid = 'RINCON_FL01400';
  const frUuid = 'RINCON_FR01400';

  SonosDevice dev(String uuid, String model) =>
      SonosDevice(uuid: uuid, roomName: uuid, modelName: model, ip: '1.2.3.4');

  test('adds fronts to a real Beam layout, keeping CC + rears + sub', () {
    // Exactly the layout read from the live system via tool/spike.dart.
    const existing =
        '$beamUuid:CC;RINCON_S101400:LR;RINCON_S201400:RR;RINCON_SUB01400:SW';
    final soundbar = ZoneGroupMember(
      uuid: beamUuid,
      zoneName: 'Woonkamer',
      htSatChanMapSet: existing,
    );

    final map = repo.buildDedicatedFrontsMap(
      soundbar: soundbar,
      soundbarDevice: dev(beamUuid, 'Sonos Beam'),
      leftSpeaker: dev(flUuid, 'Sonos One SL'),
      rightSpeaker: dev(frUuid, 'Sonos One SL'),
    );

    expect(
      map.encode(),
      '$beamUuid:CC;RINCON_S101400:LR;RINCON_S201400:RR;RINCON_SUB01400:SW;'
      '$flUuid:LF;$frUuid:RF',
    );
    expect(map.primary!.uuid, beamUuid, reason: 'soundbar stays primary/center');
    expect(map.hasFronts, isTrue);
  });

  test('bare soundbar (no satellites) becomes center + two fronts', () {
    final soundbar = ZoneGroupMember(uuid: beamUuid, zoneName: 'Woonkamer');

    final map = repo.buildDedicatedFrontsMap(
      soundbar: soundbar,
      soundbarDevice: dev(beamUuid, 'Sonos Beam'),
      leftSpeaker: dev(flUuid, 'Sonos One SL'),
      rightSpeaker: dev(frUuid, 'Sonos One SL'),
    );

    expect(map.encode(), '$beamUuid:CC;$flUuid:LF;$frUuid:RF');
  });

  test('re-applying replaces existing fronts rather than duplicating', () {
    const withFronts = '$beamUuid:CC;OLD_FL:LF;OLD_FR:RF;RINCON_SUB01400:SW';
    final soundbar = ZoneGroupMember(
      uuid: beamUuid,
      zoneName: 'Woonkamer',
      htSatChanMapSet: withFronts,
    );

    final map = repo.buildDedicatedFrontsMap(
      soundbar: soundbar,
      soundbarDevice: dev(beamUuid, 'Sonos Beam'),
      leftSpeaker: dev(flUuid, 'Sonos One SL'),
      rightSpeaker: dev(frUuid, 'Sonos One SL'),
    );

    expect(map.encode(),
        '$beamUuid:CC;RINCON_SUB01400:SW;$flUuid:LF;$frUuid:RF');
    expect(map.entries.where((e) => e.uuid == 'OLD_FL'), isEmpty);
  });
}
