import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:xml/xml.dart';

/// `freeSpeaker` at the WRITE layer, not the decision layer.
///
/// Every other free test stops at `mustFreeBeforeBonding`, which is a pure
/// model read. That is how the dual-sub fix shipped half done: `ownerOf` was
/// patched to see both subs, `freeSpeaker` kept its own copy of the same
/// condition without the fix, and the result was a decision layer saying "free
/// this sub" over a write layer that issued no `RemoveHTSatellite` at all. The
/// only thing that catches that is asserting on the calls actually made.
const bar = 'RINCON_BAR01400';
const sub1 = 'RINCON_SUB101400';
const sub2 = 'RINCON_SUB201400';
const rear = 'RINCON_REAR01400';

/// Records every write, and answers the reads `freeSpeaker` makes along the way.
class _Soap extends SonosSoapClient {
  final calls = <({String action, String ip, Map<String, String> args})>[];

  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    calls.add((action: action, ip: ip, args: args));
    return XmlDocument.parse('<Body/>').rootElement;
  }

  Iterable<String> get removedSatellites => calls
      .where((c) => c.action == 'RemoveHTSatellite')
      .map((c) => c.args['SatelliteUUID'] ?? c.args.values.first);
}

void main() {
  // The mid-settle window the dual-sub fix exists for: the authoritative map
  // carries both subs, and the <Satellite> list has briefly vanished.
  SonosSystem midSettle() => SonosSystem(
        groups: [
          ZoneGroup(coordinatorUuid: bar, members: const [
            ZoneGroupMember(
              uuid: bar,
              zoneName: 'Woonkamer',
              htSatChanMapSet: '$bar:CC;$rear:LR;$sub1:SW;$sub2:SW',
              location: 'http://1.2.3.4:1400/xml/device_description.xml',
              satellites: [],
            ),
          ]),
        ],
        devicesByUuid: const {
          bar: SonosDevice(
              uuid: bar,
              roomName: 'Woonkamer',
              modelName: 'Sonos Beam',
              ip: '1.2.3.4'),
        },
      );

  for (final sub in [sub1, sub2]) {
    test('freeSpeaker unbonds $sub from a dual-sub home theater', () async {
      final soap = _Soap();
      final sys = midSettle();

      // The decision layer says this sub must be freed...
      expect(
        sys.mustFreeBeforeBonding(sub, keep: const {}, absorbing: false),
        isTrue,
      );

      // ...so the write layer has to actually issue the removal. `sub1` is the
      // one the channel-keyed map drops, and it silently wrote nothing.
      await SonosRepository(deviceProps: DevicePropertiesClient(soap)).freeSpeaker(sys, sub);
      expect(soap.removedSatellites, [sub],
          reason: 'the decision and the write must not disagree');
    });
  }

  test('a rear surround still frees, and only the one asked for', () async {
    final soap = _Soap();
    await SonosRepository(deviceProps: DevicePropertiesClient(soap)).freeSpeaker(midSettle(), rear);
    expect(soap.removedSatellites, [rear]);
  });

  test('a speaker that is already standalone writes nothing', () async {
    final soap = _Soap();
    await SonosRepository(deviceProps: DevicePropertiesClient(soap)).freeSpeaker(midSettle(), 'RINCON_FREE');
    expect(soap.calls, isEmpty);
  });

  test('the soundbar itself is not a satellite of its own home theater',
      () async {
    final soap = _Soap();
    await SonosRepository(deviceProps: DevicePropertiesClient(soap)).freeSpeaker(midSettle(), bar);
    expect(soap.calls, isEmpty,
        reason: 'holdsSatellite excludes the member itself');
  });
}
