import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_description.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

const _aUrl = 'http://192.168.1.10:1400/xml/device_description.xml';
const _bUrl = 'http://192.168.1.11:1400/xml/device_description.xml';

// SSDP and the description fetch are lossy; topology is authoritative. The
// repo re-fetches any topology member it's missing from its topology-provided
// Location, and keeps the device (flagged unreachable) if even that fails.
class _FakeSsdp extends SsdpDiscovery {
  @override
  Future<Set<String>> discover({Duration timeout = const Duration(seconds: 4)}) async =>
      {_aUrl, _bUrl};
}

class _FakeDescriptions extends DeviceDescriptionClient {
  final Set<String> alwaysFail;
  final Set<String> failOnce;
  final calls = <String, int>{};

  _FakeDescriptions({this.alwaysFail = const {}, this.failOnce = const {}});

  @override
  Future<SonosDevice> fetch(String locationUrl) async {
    final n = (calls[locationUrl] = (calls[locationUrl] ?? 0) + 1);
    if (alwaysFail.contains(locationUrl)) throw Exception('unreachable');
    if (failOnce.contains(locationUrl) && n == 1) throw Exception('transient');
    if (locationUrl == _aUrl) {
      return const SonosDevice(
          uuid: 'RINCON_A01400', roomName: 'Living', modelName: 'Sonos One', ip: '192.168.1.10');
    }
    if (locationUrl == _bUrl) {
      return const SonosDevice(
          uuid: 'RINCON_B01400', roomName: 'Bureau', modelName: 'Sonos One', ip: '192.168.1.11');
    }
    throw Exception('unexpected url $locationUrl');
  }
}

class _FakeTopology extends ZoneTopologyClient {
  _FakeTopology() : super(SonosSoapClient());

  @override
  Future<List<ZoneGroup>> getZoneGroups(String ip) async => const [
        ZoneGroup(coordinatorUuid: 'RINCON_A01400', members: [
          ZoneGroupMember(uuid: 'RINCON_A01400', zoneName: 'Living', location: _aUrl),
          ZoneGroupMember(uuid: 'RINCON_B01400', zoneName: 'Bureau', location: _bUrl),
        ]),
      ];
}

SonosRepository _repo(_FakeDescriptions descriptions) => SonosRepository(
      ssdp: _FakeSsdp(),
      descriptions: descriptions,
      topology: _FakeTopology(),
    );

void main() {
  test('recovers a topology member whose first description fetch failed', () async {
    final descriptions = _FakeDescriptions(failOnce: {_bUrl});
    final system = await _repo(descriptions).discover();

    // B's first fetch threw; the topology pass re-fetched it (second call).
    expect(descriptions.calls[_bUrl], 2);
    expect(system.device('RINCON_B01400')?.reachable, isTrue);
    final bondable = system.bondableSpeakers.map((d) => d.uuid).toSet();
    expect(bondable, containsAll(['RINCON_A01400', 'RINCON_B01400']));
  });

  test('keeps an undescribable member, flagged unreachable, still bondable', () async {
    final descriptions = _FakeDescriptions(alwaysFail: {_bUrl});
    final system = await _repo(descriptions).discover();

    // Both the SSDP pass and the topology re-fetch were attempted and failed.
    expect(descriptions.calls[_bUrl], 2);
    final b = system.device('RINCON_B01400');
    expect(b, isNotNull);
    expect(b!.reachable, isFalse); // surfaced disabled-with-warning in the UI
    expect(b.roomName, 'Bureau'); // name carried over from topology
    // Still present so the UI can render it (old code dropped it entirely).
    expect(system.bondableSpeakers.map((d) => d.uuid), contains('RINCON_B01400'));
  });
}
