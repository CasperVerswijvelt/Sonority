import 'package:flutter_riverpod/misc.dart' show Override;

import '../data/models/sonos_models.dart';
import '../data/sonos/room_calibration.dart';
import '../data/sonos/sonos_repository.dart';
import '../features/profiles/profile.dart';
import '../features/profiles/profile_controller.dart';
import '../features/profiles/profile_store.dart';
import '../state/sonos_controller.dart';

/// Demo mode feeds the UI a hand-crafted fake Sonos system + profiles so
/// marketing screenshots need no LAN, no real hardware, and no staging/revert
/// ritual (see docs/MARKETING-ASSETS.md §2). Enable with
/// `--dart-define=DEMO=true`; off (and tree-shaken out) otherwise.
const kDemoMode = bool.fromEnvironment('DEMO');

/// The two provider overrides demo mode swaps in: the repository (topology +
/// Trueplay reads) and the profile store. Everything on screen derives from
/// these.
List<Override> demoOverrides() => [
      sonosRepositoryProvider.overrideWithValue(_DemoSonosRepository()),
      profileStoreProvider.overrideWithValue(_DemoProfileStore()),
    ];

// ponytail: read-only demo — the bonding/write methods stay inherited and
// would just time out against the fake IPs. Fine for screenshots; stub them
// if a demo of the apply flow is ever needed.
class _DemoSonosRepository extends SonosRepository {
  @override
  Future<SonosSystem> discover() async => demoSystem;

  @override
  Future<SonosSystem> refresh(SonosSystem previous, String ip) async =>
      demoSystem;

  @override
  Future<RoomCalibration> roomCalibration(String ip) async =>
      const RoomCalibration(available: true, enabled: true);

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

const _devices = <SonosDevice>[
  SonosDevice(uuid: _arc, roomName: 'Living Room', modelName: 'Sonos Arc', ip: '10.0.0.10'),
  SonosDevice(uuid: _frontL, roomName: 'Living Room', modelName: 'Sonos Era 100', ip: '10.0.0.11'),
  SonosDevice(uuid: _frontR, roomName: 'Living Room', modelName: 'Sonos Era 100', ip: '10.0.0.12'),
  SonosDevice(uuid: _rearL, roomName: 'Living Room', modelName: 'Sonos Era 300', ip: '10.0.0.13'),
  SonosDevice(uuid: _rearR, roomName: 'Living Room', modelName: 'Sonos Era 300', ip: '10.0.0.14'),
  SonosDevice(uuid: _sub, roomName: 'Living Room', modelName: 'Sonos Sub', ip: '10.0.0.15'),
  SonosDevice(uuid: _officeL, roomName: 'Office', modelName: 'Sonos One', ip: '10.0.0.20'),
  SonosDevice(uuid: _officeR, roomName: 'Office', modelName: 'Sonos One', ip: '10.0.0.21'),
  SonosDevice(uuid: _up1, roomName: 'Upstairs', modelName: 'Sonos Era 100', ip: '10.0.0.30'),
  SonosDevice(uuid: _up2, roomName: 'Upstairs', modelName: 'Sonos Play:1', ip: '10.0.0.31'),
  SonosDevice(uuid: _up3, roomName: 'Upstairs', modelName: 'Sonos Play:1', ip: '10.0.0.32'),
  SonosDevice(uuid: _kitchen, roomName: 'Kitchen', modelName: 'Sonos One', ip: '10.0.0.40'),
  SonosDevice(uuid: _bedroom, roomName: 'Bedroom', modelName: 'Sonos Five', ip: '10.0.0.41'),
  SonosDevice(uuid: _bathroom, roomName: 'Bathroom', modelName: 'Sonos One SL', ip: '10.0.0.42'),
];

String _location(String ip) => 'http://$ip:1400/xml/device_description.xml';

/// Living Room: Arc as center + dedicated Era 100 fronts + Era 300 rears + Sub
/// — the 5.1-with-fronts config the official Sonos app refuses to create.
final demoHomeTheater = ZoneGroupMember(
  uuid: _arc,
  zoneName: 'Living Room',
  location: _location('10.0.0.10'),
  htSatChanMapSet:
      '$_arc:CC;$_frontL:LF;$_frontR:RF;$_rearL:LR;$_rearR:RR;$_sub:SW',
  satellites: [
    SonosSatellite(uuid: _frontL, zoneName: 'Living Room', channels: const [SonosChannel.leftFront], ip: '10.0.0.11'),
    SonosSatellite(uuid: _frontR, zoneName: 'Living Room', channels: const [SonosChannel.rightFront], ip: '10.0.0.12'),
    SonosSatellite(uuid: _rearL, zoneName: 'Living Room', channels: const [SonosChannel.leftRear], ip: '10.0.0.13'),
    SonosSatellite(uuid: _rearR, zoneName: 'Living Room', channels: const [SonosChannel.rightRear], ip: '10.0.0.14'),
    SonosSatellite(uuid: _sub, zoneName: 'Living Room', channels: const [SonosChannel.sub], ip: '10.0.0.15'),
  ],
);

/// Office: a stereo pair of two Sonos Ones (right half hidden, as on hardware).
final demoStereoPair = ZoneGroupMember(
  uuid: _officeL,
  zoneName: 'Office',
  location: _location('10.0.0.20'),
  channelMapSet: '$_officeL:LF,LF;$_officeR:RF,RF',
);

/// Upstairs: a 3-speaker full-range zone mixing an Era 100 with two Play:1s —
/// models the official app blocks from zones (fine on hardware).
final demoZone = ZoneGroupMember(
  uuid: _up1,
  zoneName: 'Upstairs',
  location: _location('10.0.0.30'),
  channelMapSet: '$_up1:LF,RF;$_up2:LF,RF;$_up3:LF,RF',
);

final demoSystem = SonosSystem(
  groups: [
    ZoneGroup(coordinatorUuid: _arc, members: [demoHomeTheater]),
    ZoneGroup(coordinatorUuid: _officeL, members: [
      demoStereoPair,
      ZoneGroupMember(uuid: _officeR, zoneName: 'Office', location: _location('10.0.0.21'), invisible: true),
    ]),
    ZoneGroup(coordinatorUuid: _up1, members: [
      demoZone,
      ZoneGroupMember(uuid: _up2, zoneName: 'Upstairs', location: _location('10.0.0.31'), invisible: true),
      ZoneGroupMember(uuid: _up3, zoneName: 'Upstairs', location: _location('10.0.0.32'), invisible: true),
    ]),
    ZoneGroup(coordinatorUuid: _kitchen, members: [
      ZoneGroupMember(uuid: _kitchen, zoneName: 'Kitchen', location: _location('10.0.0.40')),
    ]),
    ZoneGroup(coordinatorUuid: _bedroom, members: [
      ZoneGroupMember(uuid: _bedroom, zoneName: 'Bedroom', location: _location('10.0.0.41')),
    ]),
    ZoneGroup(coordinatorUuid: _bathroom, members: [
      ZoneGroupMember(uuid: _bathroom, zoneName: 'Bathroom', location: _location('10.0.0.42')),
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
        entities: [EntitySnapshot.fromMember(demoHomeTheater)],
      ),
      Profile(
        id: 'demo-music-everywhere',
        name: 'Music everywhere',
        iconId: 'music',
        color: 1,
        entities: [
          EntitySnapshot.fromMember(demoStereoPair),
          EntitySnapshot.fromMember(demoZone),
        ],
      ),
    ];
