import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sonos_models.dart';
import 'cancellation.dart';
import 'channel_map.dart' show ChannelMap;
import 'device_description.dart';
import 'device_properties.dart';
import 'room_calibration.dart';
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
  final RoomCalibrationClient _calibration;

  SonosRepository({
    SsdpDiscovery? ssdp,
    DeviceDescriptionClient? descriptions,
    ZoneTopologyClient? topology,
    DevicePropertiesClient? deviceProps,
    RoomCalibrationClient? calibration,
  })  : _ssdp = ssdp ?? SsdpDiscovery(),
        _descriptions = descriptions ?? DeviceDescriptionClient(),
        _topology = topology ?? ZoneTopologyClient(SonosSoapClient()),
        _deviceProps = deviceProps ?? DevicePropertiesClient(SonosSoapClient()),
        _calibration = calibration ?? RoomCalibrationClient(SonosSoapClient());

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

    // Topology is authoritative; SSDP and the per-device description fetch are
    // both lossy. Re-fetch any visible member we don't yet have a description
    // for, straight from its topology-provided Location — this recovers a
    // transient fetch failure and any device SSDP's multicast missed entirely.
    final missing = [
      for (final g in groups)
        for (final m in g.members)
          if (!m.invisible &&
              m.location != null &&
              !devicesByUuid.containsKey(m.uuid))
            m,
    ];
    if (missing.isNotEmpty) {
      final recovered = await Future.wait(missing.map((m) async {
        try {
          return await _descriptions.fetch(m.location!);
        } catch (_) {
          // Re-fetch failed too. Keep the device — it's in the authoritative
          // topology — but flag it unreachable (model/capabilities unknown) so
          // the UI surfaces it disabled with a warning instead of dropping it
          // silently.
          return SonosDevice(
            uuid: m.uuid,
            roomName: m.zoneName,
            modelName: '',
            ip: m.ip,
            reachable: false,
          );
        }
      }));
      for (final d in recovered) {
        devicesByUuid[d.uuid] = d;
      }
    }

    return SonosSystem(groups: groups, devicesByUuid: devicesByUuid);
  }

  /// Re-read topology from a known device IP (cheaper than full discovery).
  Future<SonosSystem> refresh(SonosSystem previous, String ip) async {
    final groups = await _topology.getZoneGroups(ip);
    return SonosSystem(groups: groups, devicesByUuid: previous.devicesByUuid);
  }

  /// Reads Trueplay / room-calibration state for one speaker.
  Future<RoomCalibration> roomCalibration(String ip) =>
      _calibration.getStatus(ip);

  /// Switches a speaker's stored Trueplay calibration on/off (non-destructive).
  Future<void> setRoomCalibration(String ip, bool on) =>
      _calibration.setEnabled(ip, on);

  /// Writes [target] to the coordinator and VERIFIES every requested channel
  /// actually landed, RE-ASSERTING up to [retries] times if Sonos silently drops
  /// satellites that don't finish joining (the Phase 0 finding — see
  /// [[phase0-ht-bonding-finding]]). The 8s SOAP timeout fires on big bonding
  /// calls but the write still takes effect, so a timeout is treated as "go
  /// verify", not "failed". Returns the verified [SonosSystem]; throws naming the
  /// channels that never bonded if it can't converge.
  ///
  /// Staging (e.g. rears+sub first, then fronts) is the caller's job: call this
  /// once per stage. [onNote] surfaces per-attempt progress for the UI.
  Future<SonosSystem> bondAndVerify({
    required SonosDevice coordinator,
    required ChannelMap target,
    required SonosSystem? previous,
    // A full 5.1 rebuild from a bare bar measured a steady 6 re-asserts on
    // hardware (single-call beat staged, which needed up to 24 — see CLAUDE.md);
    // 10 leaves headroom. Incremental adds converge in 1–2.
    int retries = 10,
    Duration settle = const Duration(seconds: 16),
    void Function(String note)? onNote,
    CancellationToken? cancel,
  }) async {
    final ip = coordinator.ip;
    if (ip == null) throw Exception('Coordinator IP unknown; rescan and retry.');

    // Desired channel → set of UUIDs, skipping the CC primary
    // (target.entries.first). A set per channel so dual subs (two SW entries)
    // are both required, not collapsed to one.
    final wanted = <SonosChannel, Set<String>>{};
    for (final e in target.entries.skip(1)) {
      for (final ch in e.channels) {
        (wanted[ch] ??= <String>{}).add(e.uuid);
      }
    }

    SonosSystem? system = previous;
    List<SonosChannel> missing = wanted.keys.toList();
    for (var attempt = 1; attempt <= retries; attempt++) {
      cancel?.throwIfCancelled();
      try {
        await _deviceProps.addHtSatellite(soundbarIp: ip, map: target);
      } on TimeoutException {
        // Big bonding calls time out at 8s but the write still takes effect.
        onNote?.call('attempt $attempt: write timed out, verifying');
      } catch (e) {
        // Bonding is eventually-consistent (confirmed on hardware): a write can
        // partially apply then settle, or return a transient UPnPError (e.g. 800
        // — "can't add a satellite that's still mid-reshuffle") while leaving some
        // channels bonded. Re-asserting the SAME map then converges (took ~4
        // tries on a real Beam rebuild). So treat ANY write error as "go verify",
        // and only fail if the topology never reaches the target.
        onNote?.call('attempt $attempt: write error, re-asserting');
      }
      await interruptibleDelay(settle, cancel);
      try {
        system = system == null ? await discover() : await refresh(system, ip);
      } catch (_) {
        onNote?.call('attempt $attempt: topology read failed, retrying');
        continue;
      }
      final member = system.allMembers
          .where((m) => m.uuid == coordinator.uuid)
          .cast<ZoneGroupMember?>()
          .firstOrNull;
      missing = [
        for (final e in wanted.entries)
          if (!(member?.uuidsForChannel(e.key).toSet() ?? const <String>{})
              .containsAll(e.value))
            e.key,
      ];
      if (missing.isEmpty) {
        onNote?.call(attempt == 1 ? 'bonded' : 're-asserted after $attempt tries');
        return system;
      }
      onNote?.call(
          'attempt $attempt: ${missing.map((c) => c.token).join('/')} not bonded yet');
    }
    throw Exception('Bonding did not complete — these channels never joined: '
        '${missing.map((c) => c.token).join(', ')}. Try again, or finish in the Sonos app.');
  }

  /// Unbonds the given satellite [uuids] from the soundbar at [soundbarIp].
  Future<void> removeHtSatellites({
    required String soundbarIp,
    required Iterable<String> uuids,
    CancellationToken? cancel,
  }) async {
    for (final uuid in uuids) {
      cancel?.throwIfCancelled();
      await _deviceProps.removeHtSatellite(soundbarIp: soundbarIp, satelliteUuid: uuid);
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

  /// Frees [uuid] from whatever role it currently holds so it can be re-bonded
  /// elsewhere (profile-apply conflict resolution): unbonds it if it's a
  /// satellite, or separates the pair if it's a pair member. No-op if it's
  /// already standalone. Caller should settle + re-read afterward.
  Future<void> freeSpeaker(SonosSystem system, String uuid) async {
    for (final g in system.groups) {
      for (final m in g.members) {
        // A satellite (front/rear/sub) of an HT primary.
        if (m.uuid != uuid &&
            (m.channelAssignments.values.contains(uuid) ||
                m.satellites.any((s) => s.uuid == uuid))) {
          final ip = m.ip;
          if (ip != null) {
            await _deviceProps.removeHtSatellite(soundbarIp: ip, satelliteUuid: uuid);
          }
          return;
        }
        // A half of a stereo pair.
        if (m.isStereoPair && m.stereoPairUuids.contains(uuid)) {
          final uuids = m.stereoPairUuids;
          final ip = system.device(uuids.first)?.ip ?? m.ip;
          if (ip != null && uuids.length == 2) {
            await _deviceProps.separateStereoPair(
                ip: ip, leftUuid: uuids[0], rightUuid: uuids[1]);
          }
          return;
        }
      }
    }
  }

  /// Sets a speaker's room name (used to restore names on profile-apply), only
  /// writing if it differs — preserving the current icon/configuration.
  Future<void> setRoomName({required String ip, required String name}) async {
    final attrs = await _deviceProps.getZoneAttributes(ip);
    if (attrs.zoneName == name) return;
    await _deviceProps.setZoneAttributes(
      ip,
      ZoneAttributes(
          zoneName: name, icon: attrs.icon, configuration: attrs.configuration),
    );
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
