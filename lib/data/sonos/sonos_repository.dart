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

  static const _restoreKeyPrefix = 'restore_point_';

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

    await _saveRestorePoint(soundbar);

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

  Future<void> _saveRestorePoint(ZoneGroupMember soundbar) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = jsonEncode({
      'uuid': soundbar.uuid,
      'htSatChanMapSet': soundbar.htSatChanMapSet,
      'satelliteUuids': soundbar.satellites.map((s) => s.uuid).toList(),
    });
    await prefs.setString('$_restoreKeyPrefix${soundbar.uuid}', snapshot);
  }

  /// The raw `HTSatChanMapSet` captured before the last change, if any.
  Future<String?> lastRestoreMapSet(String soundbarUuid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_restoreKeyPrefix$soundbarUuid');
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded['htSatChanMapSet'] as String?;
  }
}
