import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';

/// Regression: a freed (standalone) Sub is its own `Invisible` group member —
/// it must still be offered by [SonosSystem.bondableSubs]. A bonded Sub (a
/// satellite of the soundbar) must not be.
void main() {
  const beam = 'RINCON_BEAM01400';
  const sub = 'RINCON_SUB01400';

  SonosDevice dev(String uuid, String model) =>
      SonosDevice(uuid: uuid, roomName: 'Room', modelName: model, ip: '1.2.3.4');

  final devices = {
    beam: dev(beam, 'Sonos Beam'),
    sub: dev(sub, 'Sonos Sub'),
  };

  test('freed Sub (own Invisible group member) is bondable', () {
    final system = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: beam, members: [
          ZoneGroupMember(uuid: beam, zoneName: 'Woonkamer'),
        ]),
        // The freed Sub: its own group, Invisible (Subs have no visible room).
        ZoneGroup(coordinatorUuid: sub, members: [
          const ZoneGroupMember(uuid: sub, zoneName: 'Sub', invisible: true),
        ]),
      ],
      devicesByUuid: devices,
    );
    expect(system.bondableSubs.map((d) => d.uuid), [sub]);
  });

  test('bonded Sub (satellite of the bar) is NOT bondable', () {
    final system = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: beam, members: [
          ZoneGroupMember(
            uuid: beam,
            zoneName: 'Woonkamer',
            htSatChanMapSet: '$beam:CC;$sub:SW',
            satellites: const [
              SonosSatellite(
                  uuid: sub, zoneName: 'Woonkamer', channels: [SonosChannel.sub]),
            ],
          ),
        ]),
      ],
      devicesByUuid: devices,
    );
    expect(system.bondableSubs, isEmpty);
  });
}
