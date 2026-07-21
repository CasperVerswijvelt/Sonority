import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:xml/xml.dart' show XmlElement;

import '../data/models/sonos_models.dart';
import '../data/sonos/av_transport.dart';
import '../data/sonos/channel_map.dart';
import '../data/sonos/device_properties.dart';
import '../data/sonos/identify_service.dart';
import '../data/sonos/led_identify.dart';
import '../data/sonos/room_calibration.dart';
import '../data/sonos/soap_client.dart';
import '../data/sonos/sonos_repository.dart';
import '../data/sonos/zone_layout.dart' show buildGroupMap;
import '../data/sonos/zone_topology.dart';
import '../features/profiles/profile.dart';
import '../features/profiles/profile_controller.dart';
import '../features/profiles/profile_store.dart';
import '../state/sonos_controller.dart';

/// Demo mode feeds the UI a hand-crafted fake Sonos system + profiles so
/// marketing screenshots need no LAN, no real hardware, and no staging/revert
/// ritual (see docs/MARKETING-ASSETS.md §2). Enable with
/// `--dart-define=DEMO=true`; off (and tree-shaken out) otherwise.
const kDemoMode = bool.fromEnvironment('DEMO');

/// The provider overrides demo mode swaps in: the repository (topology +
/// Trueplay reads), the profile store, and the identify clients. Everything on
/// screen derives from these.
List<Override> demoOverrides() => [
      sonosRepositoryProvider.overrideWithValue(_DemoSonosRepository()),
      profileStoreProvider.overrideWithValue(_DemoProfileStore()),
      // Identify taps fail instantly with the normal "could not reach"
      // feedback instead of spinning through ~30s of SOAP timeouts.
      ledIdentifyProvider.overrideWithValue(LedIdentifyClient(_demoSoap)),
      identifyServiceProvider
          .overrideWithValue(IdentifyServiceClient(_demoSoap)),
    ];

final _demoSoap = _DemoSoapClient();

/// Throws on any SOAP call, so NOTHING in a demo build can emit network I/O —
/// including repository write methods and any read method added later.
class _DemoSoapClient extends SonosSoapClient {
  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async =>
      throw StateError('demo mode: no network I/O ($action)');
}

// ponytail: demo is navigation-only — write flows (apply/bond/separate/rename)
// fail fast on _DemoSoapClient instead of succeeding against fake state. Fake
// the write semantics (mutate demoSystem) if a demo of a full apply is ever
// needed. Known leak: SpeakerSettingsClient is constructed inside
// SonosController, so the profile-create "save speaker settings" toggle still
// times out against the (unrouteable TEST-NET) demo IPs.
class _DemoSonosRepository extends SonosRepository {
  _DemoSonosRepository()
      : super(
          topology: ZoneTopologyClient(_demoSoap),
          deviceProps: DevicePropertiesClient(_demoSoap),
          calibration: RoomCalibrationClient(_demoSoap),
          avTransport: AvTransportClient(_demoSoap),
        );

  @override
  Future<SonosSystem> discover() async => demoSystem;

  @override
  Future<SonosSystem> refresh(SonosSystem previous, String ip) async =>
      demoSystem;

  // Bonding dedicated fronts makes Sonos invalidate Trueplay across the whole
  // HT set (every member drops to available=0) and we can't restore it — so the
  // Living-Room HT honestly reads "not tuned". Standalone rooms keep a real
  // tuning so the read/toggle feature is still demoable on the room detail.
  static final _bondedFrontsIps = {
    '192.0.2.10', // Arc coordinator
    for (final s in _htSatellites) s.ip,
  };

  @override
  Future<RoomCalibration> roomCalibration(String ip) async =>
      _bondedFrontsIps.contains(ip)
          ? const RoomCalibration(available: false, enabled: false)
          : const RoomCalibration(available: true, enabled: true);

  @override
  Future<void> setRoomCalibration(String ip, bool on) async {}
}

/// In-memory store seeded with the demo profiles; edits stick for the session.
class _DemoProfileStore extends ProfileStore {
  List<Profile> _profiles = demoProfiles();

  @override
  Future<List<Profile>> load() async => _profiles;

  @override
  Future<void> save(List<Profile> profiles) async => _profiles = profiles;
}

// ---------------------------------------------------------------------------
// The demo system: one hero home theater with dedicated fronts (the app's
// flagship config), a stereo pair, a 3-speaker zone (incl. app-blocked
// Play:1s), and three standalone rooms for the group-creation flow.
//
// IPs are RFC 5737 TEST-NET-1 (192.0.2.0/24) — reserved for documentation and
// never assigned, so even a network call that slips past the demo SOAP client
// can't reach a real device on someone's LAN.
// ---------------------------------------------------------------------------

const _arc = 'RINCON_DEMO_ARC000001400';
const _frontL = 'RINCON_DEMO_FL000001400';
const _frontR = 'RINCON_DEMO_FR000001400';
const _rearL = 'RINCON_DEMO_RL000001400';
const _rearR = 'RINCON_DEMO_RR000001400';
const _sub = 'RINCON_DEMO_SUB000001400';
const _officeL = 'RINCON_DEMO_OFL000A1400';
const _officeR = 'RINCON_DEMO_OFR000A1400';
const _up1 = 'RINCON_DEMO_UP1000001400';
const _up2 = 'RINCON_DEMO_UP2000001400';
const _up3 = 'RINCON_DEMO_UP3000001400';
const _kitchen = 'RINCON_DEMO_KIT000001400';
const _bedroom = 'RINCON_DEMO_BED000001400';
const _bathroom = 'RINCON_DEMO_BATH00001400';
// A second, simpler home theater (Bedroom): a Beam with two rear surrounds and
// no dedicated fronts, so the overview shows a main viewing area plus a bedroom.
const _beam = 'RINCON_DEMO_BEAM00001400';
const _bedRearL = 'RINCON_DEMO_BEDL00001400';
const _bedRearR = 'RINCON_DEMO_BEDR00001400';

const _devices = <SonosDevice>[
  SonosDevice(uuid: _arc, roomName: 'Living Room', modelName: 'Sonos Arc', ip: '192.0.2.10'),
  SonosDevice(uuid: _frontL, roomName: 'Living Room', modelName: 'Sonos Era 100', ip: '192.0.2.11'),
  SonosDevice(uuid: _frontR, roomName: 'Living Room', modelName: 'Sonos Era 100', ip: '192.0.2.12'),
  SonosDevice(uuid: _rearL, roomName: 'Living Room', modelName: 'Sonos Era 300', ip: '192.0.2.13'),
  SonosDevice(uuid: _rearR, roomName: 'Living Room', modelName: 'Sonos Era 300', ip: '192.0.2.14'),
  SonosDevice(uuid: _sub, roomName: 'Living Room', modelName: 'Sonos Sub', ip: '192.0.2.15'),
  SonosDevice(uuid: _officeL, roomName: 'Office', modelName: 'Sonos One', ip: '192.0.2.20'),
  SonosDevice(uuid: _officeR, roomName: 'Office', modelName: 'Sonos One', ip: '192.0.2.21'),
  SonosDevice(uuid: _up1, roomName: 'Upstairs', modelName: 'Sonos Era 100', ip: '192.0.2.30'),
  SonosDevice(uuid: _up2, roomName: 'Upstairs', modelName: 'Sonos Play:1', ip: '192.0.2.31'),
  SonosDevice(uuid: _up3, roomName: 'Upstairs', modelName: 'Sonos Play:1', ip: '192.0.2.32'),
  SonosDevice(uuid: _kitchen, roomName: 'Kitchen', modelName: 'Sonos One', ip: '192.0.2.40'),
  SonosDevice(uuid: _bedroom, roomName: 'Guest Room', modelName: 'Sonos Five', ip: '192.0.2.41'),
  SonosDevice(uuid: _bathroom, roomName: 'Bathroom', modelName: 'Sonos One SL', ip: '192.0.2.42'),
  SonosDevice(uuid: _beam, roomName: 'Bedroom', modelName: 'Sonos Beam', modelNumber: 'S31', ip: '192.0.2.50'),
  SonosDevice(uuid: _bedRearL, roomName: 'Bedroom', modelName: 'Sonos One', ip: '192.0.2.51'),
  SonosDevice(uuid: _bedRearR, roomName: 'Bedroom', modelName: 'Sonos One', ip: '192.0.2.52'),
];

String _location(String ip) => 'http://$ip:1400/xml/device_description.xml';

const _htSatellites = [
  SonosSatellite(uuid: _frontL, zoneName: 'Living Room', channels: [SonosChannel.leftFront], ip: '192.0.2.11'),
  SonosSatellite(uuid: _frontR, zoneName: 'Living Room', channels: [SonosChannel.rightFront], ip: '192.0.2.12'),
  SonosSatellite(uuid: _rearL, zoneName: 'Living Room', channels: [SonosChannel.leftRear], ip: '192.0.2.13'),
  SonosSatellite(uuid: _rearR, zoneName: 'Living Room', channels: [SonosChannel.rightRear], ip: '192.0.2.14'),
  SonosSatellite(uuid: _sub, zoneName: 'Living Room', channels: [SonosChannel.sub], ip: '192.0.2.15'),
];

/// Living Room: Arc as center + dedicated Era 100 fronts + Era 300 rears + Sub
/// — the 5.1-with-fronts config the official Sonos app refuses to create. The
/// map string is derived from the typed satellite list (one source of truth).
final demoHomeTheater = ZoneGroupMember(
  uuid: _arc,
  zoneName: 'Living Room',
  location: _location('192.0.2.10'),
  htSatChanMapSet: ChannelMap([
    ChannelMapEntry.fromChannels(_arc, [SonosChannel.center]),
    for (final s in _htSatellites) ChannelMapEntry.fromChannels(s.uuid, s.channels),
  ]).encode(),
  satellites: _htSatellites,
);

const _bedroomSatellites = [
  SonosSatellite(uuid: _bedRearL, zoneName: 'Bedroom', channels: [SonosChannel.leftRear], ip: '192.0.2.51'),
  SonosSatellite(uuid: _bedRearR, zoneName: 'Bedroom', channels: [SonosChannel.rightRear], ip: '192.0.2.52'),
];

/// Bedroom: a Beam as center + two Sonos One rear surrounds (no dedicated
/// fronts, no sub) — a lighter second home theater alongside the flagship one.
final demoBedroomTheater = ZoneGroupMember(
  uuid: _beam,
  zoneName: 'Bedroom',
  location: _location('192.0.2.50'),
  htSatChanMapSet: ChannelMap([
    ChannelMapEntry.fromChannels(_beam, [SonosChannel.center]),
    for (final s in _bedroomSatellites) ChannelMapEntry.fromChannels(s.uuid, s.channels),
  ]).encode(),
  satellites: _bedroomSatellites,
);

/// Office: a stereo pair of two Sonos Ones (right half hidden, as on hardware).
final demoStereoPair = ZoneGroupMember(
  uuid: _officeL,
  zoneName: 'Office',
  location: _location('192.0.2.20'),
  channelMapSet: buildGroupMap([
    (uuid: _officeL, channel: GroupChannel.left),
    (uuid: _officeR, channel: GroupChannel.right),
  ]),
);

/// Upstairs: a 3-speaker full-range zone mixing an Era 100 with two Play:1s —
/// models the official app blocks from zones (fine on hardware).
final demoZone = ZoneGroupMember(
  uuid: _up1,
  zoneName: 'Upstairs',
  location: _location('192.0.2.30'),
  channelMapSet: buildGroupMap([
    for (final u in [_up1, _up2, _up3]) (uuid: u, channel: GroupChannel.both),
  ]),
);

final demoSystem = SonosSystem(
  groups: [
    ZoneGroup(coordinatorUuid: _arc, members: [demoHomeTheater]),
    ZoneGroup(coordinatorUuid: _beam, members: [demoBedroomTheater]),
    ZoneGroup(coordinatorUuid: _officeL, members: [
      demoStereoPair,
      ZoneGroupMember(uuid: _officeR, zoneName: 'Office', location: _location('192.0.2.21'), invisible: true),
    ]),
    ZoneGroup(coordinatorUuid: _up1, members: [
      demoZone,
      ZoneGroupMember(uuid: _up2, zoneName: 'Upstairs', location: _location('192.0.2.31'), invisible: true),
      ZoneGroupMember(uuid: _up3, zoneName: 'Upstairs', location: _location('192.0.2.32'), invisible: true),
    ]),
    ZoneGroup(coordinatorUuid: _kitchen, members: [
      ZoneGroupMember(uuid: _kitchen, zoneName: 'Kitchen', location: _location('192.0.2.40')),
    ]),
    ZoneGroup(coordinatorUuid: _bedroom, members: [
      ZoneGroupMember(uuid: _bedroom, zoneName: 'Guest Room', location: _location('192.0.2.41')),
    ]),
    ZoneGroup(coordinatorUuid: _bathroom, members: [
      ZoneGroupMember(uuid: _bathroom, zoneName: 'Bathroom', location: _location('192.0.2.42')),
    ]),
  ],
  devicesByUuid: {for (final d in _devices) d.uuid: d},
);

/// Seed profiles, snapshotted straight off the demo members so their map
/// strings can never drift from the system above.
List<Profile> demoProfiles() => [
      Profile(
        id: 'demo-movie-night',
        name: 'Movie night',
        iconId: 'movie',
        color: 2,
        updatedAt: DateTime.now().subtract(const Duration(days: 3)),
        entities: [EntitySnapshot.fromMember(demoHomeTheater)],
      ),
      Profile(
        id: 'demo-music-everywhere',
        name: 'Music everywhere',
        iconId: 'music',
        color: 1,
        updatedAt: DateTime.now().subtract(const Duration(days: 14)),
        entities: [
          EntitySnapshot.fromMember(demoStereoPair),
          EntitySnapshot.fromMember(demoZone),
        ],
      ),
    ];
