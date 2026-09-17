import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_description.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

const _aUrl = 'http://192.168.1.10:1400/xml/device_description.xml';
const _bUrl = 'http://192.168.1.11:1400/xml/device_description.xml';
const _subUrl = 'http://192.168.1.12:1400/xml/device_description.xml';

// SSDP and the description fetch are lossy; topology is authoritative. The
// repo re-fetches any topology member it's missing from its topology-provided
// Location, and keeps the device (flagged unreachable) if even that fails.
class _FakeSsdp extends SsdpDiscovery {
  @override
  Future<Set<String>> discover({Duration timeout = const Duration(seconds: 4)}) async =>
      {_aUrl, _bUrl};
}

/// SSDP sees only player A: the other member exists in topology alone.
class _FakeSsdpAOnly extends SsdpDiscovery {
  @override
  Future<Set<String>> discover({Duration timeout = const Duration(seconds: 4)}) async =>
      {_aUrl};
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
    if (locationUrl == _subUrl) {
      return const SonosDevice(
          uuid: 'RINCON_SUB01400', roomName: 'Living', modelName: 'Sonos Sub', ip: '192.168.1.12');
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

/// A stereo pair whose hidden right half SSDP missed. The pair coordinator
/// carries the ChannelMapSet; the other half is its own `Invisible="1"` member,
/// reachable only through that member's Location.
class _FakeHiddenHalfTopology extends ZoneTopologyClient {
  _FakeHiddenHalfTopology() : super(SonosSoapClient());

  @override
  Future<List<ZoneGroup>> getZoneGroups(String ip) async => const [
        ZoneGroup(coordinatorUuid: 'RINCON_A01400', members: [
          ZoneGroupMember(
            uuid: 'RINCON_A01400',
            zoneName: 'Living',
            location: _aUrl,
            channelMapSet: 'RINCON_A01400:LF,LF;RINCON_B01400:RF,RF',
          ),
          ZoneGroupMember(
            uuid: 'RINCON_B01400',
            zoneName: 'Living',
            location: _bUrl,
            invisible: true,
            channelMapSet: 'RINCON_A01400:LF,LF;RINCON_B01400:RF,RF',
          ),
        ]),
      ];
}

SonosRepository _repo(_FakeDescriptions descriptions) => SonosRepository(
      ssdp: _FakeSsdp(),
      descriptions: descriptions,
      topology: _FakeTopology(),
    );

/// A soundbar with a bonded Sub. SSDP announces only the bar, so the Sub is
/// reachable ONLY through its `<Satellite>` Location.
class _FakeSatelliteTopology extends ZoneTopologyClient {
  _FakeSatelliteTopology() : super(SonosSoapClient());

  @override
  Future<List<ZoneGroup>> getZoneGroups(String ip) async => const [
        ZoneGroup(coordinatorUuid: 'RINCON_A01400', members: [
          ZoneGroupMember(
            uuid: 'RINCON_A01400',
            zoneName: 'Living',
            location: _aUrl,
            htSatChanMapSet: 'RINCON_A01400:CC;RINCON_SUB01400:SW',
            satellites: [
              SonosSatellite(
                uuid: 'RINCON_SUB01400',
                zoneName: 'Living',
                channels: [SonosChannel.sub],
                location: _subUrl,
              ),
            ],
          ),
        ]),
      ];
}

/// Mid-settle (the ~15s topology lag), one speaker reads twice: the Sub is
/// still the bar's `<Satellite>` and already its own member again. One speaker,
/// one Location, so it must be fetched once.
class _FakeDoubleListedTopology extends ZoneTopologyClient {
  _FakeDoubleListedTopology() : super(SonosSoapClient());

  @override
  Future<List<ZoneGroup>> getZoneGroups(String ip) async => [
        ...await _FakeSatelliteTopology().getZoneGroups(ip),
        const ZoneGroup(coordinatorUuid: 'RINCON_SUB01400', members: [
          ZoneGroupMember(
            uuid: 'RINCON_SUB01400',
            zoneName: 'Sub',
            location: _subUrl,
            invisible: true,
          ),
        ]),
      ];
}

void main() {
  // A satellite is a `<Satellite>` child, not a member, so a members-only
  // recovery sweep left an SSDP-missed Sub absent from `devicesByUuid`, and
  // the HT setup flow builds its target map from RESOLVED devices, so the next
  // apply would have dropped the SW channel and unbonded the user's Sub with no
  // warning. Seen on real hardware.
  test('recovers a SATELLITE that SSDP missed entirely', () async {
    final descriptions = _FakeDescriptions();
    final system = await SonosRepository(
      ssdp: _FakeSsdpAOnly(),
      descriptions: descriptions,
      topology: _FakeSatelliteTopology(),
    ).discover();

    expect(descriptions.calls[_subUrl], 1, reason: 'fetched from its topology Location');
    final sub = system.device('RINCON_SUB01400');
    expect(sub, isNotNull, reason: 'the Sub must resolve, or an apply silently drops it');
    expect(sub!.modelName, 'Sonos Sub');
    expect(sub.reachable, isTrue);
  });

  test('a speaker listed twice mid-settle is fetched once', () async {
    final descriptions = _FakeDescriptions();
    final system = await SonosRepository(
      ssdp: _FakeSsdpAOnly(),
      descriptions: descriptions,
      topology: _FakeDoubleListedTopology(),
    ).discover();

    expect(descriptions.calls[_subUrl], 1,
        reason: 'member + satellite are the same speaker, one Location');
    expect(system.device('RINCON_SUB01400'), isNotNull,
        reason: 'deduped, not dropped');
  });

  test('an undescribable satellite is kept, flagged unreachable', () async {
    final descriptions = _FakeDescriptions(alwaysFail: {_subUrl});
    final system = await SonosRepository(
      ssdp: _FakeSsdpAOnly(),
      descriptions: descriptions,
      topology: _FakeSatelliteTopology(),
    ).discover();

    final sub = system.device('RINCON_SUB01400');
    expect(sub, isNotNull);
    expect(sub!.reachable, isFalse);
  });

  // A hidden pair half / zone member is an `Invisible="1"` MEMBER, and the
  // sweep used to skip those. A group edit builds its target from RESOLVED
  // devices and silently drops what it can't resolve, so a rename would have
  // dissolved the pair and rebuilt it WITHOUT the missing half.
  test('recovers an INVISIBLE member that SSDP missed', () async {
    final descriptions = _FakeDescriptions();
    final system = await SonosRepository(
      ssdp: _FakeSsdpAOnly(),
      descriptions: descriptions,
      topology: _FakeHiddenHalfTopology(),
    ).discover();

    expect(descriptions.calls[_bUrl], 1, reason: 'fetched from its Location');
    final half = system.device('RINCON_B01400');
    expect(half, isNotNull,
        reason: 'unresolved, a group edit would have left it behind');
    expect(half!.modelName, 'Sonos One');
    // Still hidden where hiding belongs: the room list, not the device map.
    expect(system.allMembers.map((m) => m.uuid), ['RINCON_A01400']);
    // And a resolved hidden half must not become a bond candidate.
    expect(system.bondableSpeakers.map((d) => d.uuid),
        isNot(contains('RINCON_B01400')));
  });

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
