import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sonos_models.dart';
import 'channel_map.dart' show ChannelMap;
import 'device_description.dart';
import 'device_properties.dart';
import 'front_layout.dart' as front_layout;
import 'soap_client.dart';
import 'ssdp_discovery.dart';
import 'zone_topology.dart';

/// Orchestrates discovery, topology reads, and the bonding actions, and keeps
/// a per-soundbar restore point so the user can always undo.
class SonosRepository {
  final SsdpDiscovery _ssdp;
  final DeviceDescriptionClient _descriptions;
  final ZoneTopologyClient _topology;
  final DevicePropertiesClient _deviceProps;

  SonosRepository({
    SsdpDiscovery? ssdp,
    DeviceDescriptionClient? descriptions,
    ZoneTopologyClient? topology,
    DevicePropertiesClient? deviceProps,
  })  : _ssdp = ssdp ?? SsdpDiscovery(),
        _descriptions = descriptions ?? DeviceDescriptionClient(),
        _topology = topology ?? ZoneTopologyClient(SonosSoapClient()),
        _deviceProps = deviceProps ?? DevicePropertiesClient(SonosSoapClient());

  /// Full discovery: find players, read their descriptions, then read the
  /// system topology from any one of them.
  Future<SonosSystem> discover() async {
    final locations = await _ssdp.discover();
    if (locations.isEmpty) {
      throw Exception('No Sonos devices found. Check Wi-Fi and local network access.');
    }

    final devices = await Future.wait(
      locations.map((loc) async {
        try {
          return await _descriptions.fetch(loc);
        } catch (_) {
          return null;
        }
      }),
    );
    final found = devices.whereType<SonosDevice>().toList();
    if (found.isEmpty) {
      throw Exception('Found Sonos players but could not read their descriptions.');
    }

    final devicesByUuid = {for (final d in found) d.uuid: d};
    final groups = await _topology.getZoneGroups(found.first.ip!);
    return SonosSystem(groups: groups, devicesByUuid: devicesByUuid);
  }

  /// Re-read topology from a known device IP (cheaper than full discovery).
  Future<SonosSystem> refresh(SonosSystem previous, String ip) async {
    final groups = await _topology.getZoneGroups(ip);
    return SonosSystem(groups: groups, devicesByUuid: previous.devicesByUuid);
  }

  /// See [front_layout.buildDedicatedFrontsMap]. Delegated to a Flutter-free
  /// helper so CLI tools can reuse it without pulling in shared_preferences.
  ChannelMap buildDedicatedFrontsMap({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required SonosDevice leftSpeaker,
    required SonosDevice rightSpeaker,
  }) =>
      front_layout.buildDedicatedFrontsMap(
        soundbar: soundbar,
        soundbarDevice: soundbarDevice,
        leftSpeaker: leftSpeaker,
        rightSpeaker: rightSpeaker,
      );

  /// Applies dedicated front speakers, snapshotting current state first.
  Future<void> applyDedicatedFronts({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
    required SonosDevice leftSpeaker,
    required SonosDevice rightSpeaker,
  }) async {
    final ip = soundbarDevice.ip;
    if (ip == null) throw Exception('Soundbar IP unknown; rescan and retry.');

    final map = buildDedicatedFrontsMap(
      soundbar: soundbar,
      soundbarDevice: soundbarDevice,
      leftSpeaker: leftSpeaker,
      rightSpeaker: rightSpeaker,
    );
    await _deviceProps.addHtSatellite(soundbarIp: ip, map: map);
  }

  /// Removes the dedicated front satellites currently bonded to [soundbar].
  Future<void> removeDedicatedFronts({
    required ZoneGroupMember soundbar,
    required SonosDevice soundbarDevice,
  }) async {
    final ip = soundbarDevice.ip;
    if (ip == null) throw Exception('Soundbar IP unknown; rescan and retry.');

    // Derive removal targets from the HTSatChanMapSet (authoritative) rather
    // than the <Satellite> list, which can be transiently empty after changes.
    final frontUuids = soundbar.frontSatelliteUuids.isNotEmpty
        ? soundbar.frontSatelliteUuids
        : soundbar.satellites.where((s) => s.isFront).map((s) => s.uuid).toList();
    for (final uuid in frontUuids) {
      await _deviceProps.removeHtSatellite(soundbarIp: ip, satelliteUuid: uuid);
    }
  }

  /// Creates a (possibly mismatched) stereo pair. Snapshots both rooms' zone
  /// attributes first so the original names can be restored on separation —
  /// Sonos usually restores them, but this makes it a guarantee.
  Future<void> createStereoPair({
    required SonosDevice left,
    required SonosDevice right,
  }) async {
    final leftIp = left.ip, rightIp = right.ip;
    if (leftIp == null || rightIp == null) {
      throw Exception('Speaker IP unknown; rescan and retry.');
    }
    final leftAttrs = await _deviceProps.getZoneAttributes(leftIp);
    final rightAttrs = await _deviceProps.getZoneAttributes(rightIp);
    await _savePairSnapshot(left.uuid, right.uuid, leftAttrs, rightAttrs);
    await _deviceProps.createStereoPair(
        ip: leftIp, leftUuid: left.uuid, rightUuid: right.uuid);
  }

  /// Separates a stereo pair and restores both rooms' original names (from the
  /// snapshot taken at creation) if Sonos didn't bring them back itself.
  Future<void> separateStereoPair({
    required SonosDevice left,
    required SonosDevice right,
  }) async {
    final leftIp = left.ip, rightIp = right.ip;
    if (leftIp == null || rightIp == null) {
      throw Exception('Speaker IP unknown; rescan and retry.');
    }
    await _deviceProps.separateStereoPair(
        ip: leftIp, leftUuid: left.uuid, rightUuid: right.uuid);

    final snap = await _loadPairSnapshot(left.uuid, right.uuid);
    if (snap != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      // Right speaker is the one whose name gets absorbed; restore both to be safe.
      if ((await _deviceProps.getZoneAttributes(rightIp)).zoneName !=
          snap.right.zoneName) {
        await _deviceProps.setZoneAttributes(rightIp, snap.right);
      }
      if ((await _deviceProps.getZoneAttributes(leftIp)).zoneName !=
          snap.left.zoneName) {
        await _deviceProps.setZoneAttributes(leftIp, snap.left);
      }
    }
  }

  String _pairKey(String a, String b) {
    final s = [a, b]..sort();
    return 'pair_snapshot_${s[0]}_${s[1]}';
  }

  Future<void> _savePairSnapshot(
      String leftUuid, String rightUuid, ZoneAttributes l, ZoneAttributes r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pairKey(leftUuid, rightUuid),
      jsonEncode({
        'left': {'name': l.zoneName, 'icon': l.icon, 'config': l.configuration},
        'right': {'name': r.zoneName, 'icon': r.icon, 'config': r.configuration},
      }),
    );
  }

  Future<({ZoneAttributes left, ZoneAttributes right})?> _loadPairSnapshot(
      String leftUuid, String rightUuid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pairKey(leftUuid, rightUuid));
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    ZoneAttributes parse(Map<String, dynamic> j) => ZoneAttributes(
        zoneName: j['name'] as String,
        icon: j['config'] == null ? '' : (j['icon'] as String? ?? ''),
        configuration: j['config'] as String? ?? '');
    return (left: parse(m['left']), right: parse(m['right']));
  }
}
