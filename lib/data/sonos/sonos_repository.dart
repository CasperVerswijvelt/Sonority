import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../models/sonos_models.dart';
import 'av_transport.dart';
import 'cancellation.dart';
import 'channel_map.dart' show ChannelMap;
import 'device_description.dart';
import 'device_properties.dart';
import 'diagnostics_log.dart';
import 'key_value_store.dart';
import 'room_calibration.dart';
import 'soap_client.dart';
import 'ssdp_discovery.dart';
import 'zone_layout.dart';
import 'zone_topology.dart';

/// Orchestrates discovery, topology reads, and the bonding actions. Persists
/// only the pre-group room *names* (so they can be restored when a stereo pair /
/// zone is separated); HT bonding keeps no persisted snapshot, so undoing an HT
/// change relies on the in-memory previous [SonosSystem].
class SonosRepository {
  final SsdpDiscovery _ssdp;
  final DeviceDescriptionClient _descriptions;
  final ZoneTopologyClient _topology;
  final DevicePropertiesClient _deviceProps;
  final RoomCalibrationClient _calibration;
  final AvTransportClient _avTransport;
  final KeyValueStore _store;

  SonosRepository({
    SsdpDiscovery? ssdp,
    DeviceDescriptionClient? descriptions,
    ZoneTopologyClient? topology,
    DevicePropertiesClient? deviceProps,
    RoomCalibrationClient? calibration,
    AvTransportClient? avTransport,
    KeyValueStore? store,
  })  : _ssdp = ssdp ?? SsdpDiscovery(),
        _descriptions = descriptions ?? DeviceDescriptionClient(),
        _topology = topology ?? ZoneTopologyClient(SonosSoapClient()),
        _deviceProps = deviceProps ?? DevicePropertiesClient(SonosSoapClient()),
        _calibration = calibration ?? RoomCalibrationClient(SonosSoapClient()),
        _avTransport = avTransport ?? AvTransportClient(SonosSoapClient()),
        _store = store ?? InMemoryKeyValueStore();

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
        } catch (e) {
          // Non-fatal: a device that fails its description fetch is dropped here
          // and recovered topology-only later. Log so it's diagnosable.
          developer.log('device_description fetch failed for $loc: $e',
              name: 'sonority.discover');
          DiagnosticsLog.add('discovery: device_description fetch failed for $loc: $e');
          return null;
        }
      }),
    );
    final found = devices.whereType<SonosDevice>().toList();
    if (found.isEmpty) {
      throw Exception('Found Sonos players but could not read their descriptions.');
    }

    final devicesByUuid = {for (final d in found) d.uuid: d};
    // Topology is a system-wide query any player can answer; try each until one
    // responds so a single unreachable device doesn't fail the whole discovery.
    List<ZoneGroup>? groups;
    Object? lastErr;
    for (final d in found) {
      final ip = d.ip;
      if (ip == null) continue;
      try {
        groups = await _topology.getZoneGroups(ip);
        break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (groups == null) {
      throw Exception('Could not read the Sonos topology from any player: $lastErr');
    }
    DiagnosticsLog.add(
        'discovery: ${found.length} device(s) described, topology has '
        '${groups.expand((g) => g.members).length} member(s) in ${groups.length} group(s)');

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

  /// Raw, double-decoded `GetZoneGroupState` XML from the player at [ip] — for
  /// the diagnostics bundle. Reuses the topology client so the bundle builder
  /// doesn't re-instantiate SOAP plumbing.
  Future<String> rawTopology(String ip) => _topology.getRawState(ip);

  /// Raw `device_description.xml` body from the player at [ip] — for the
  /// diagnostics bundle. Uses the well-known Sonos description path.
  Future<String> rawDeviceDescription(String ip) =>
      _descriptions.fetchRaw('http://$ip:${SonosSoapClient.port}/xml/device_description.xml');

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

  // A full 5.1 rebuild from a bare bar measured a steady 6 re-asserts on
  // hardware (single-call beat staged, which needed up to 24 — see CLAUDE.md);
  // 10 leaves headroom. Incremental adds converge in 1–2.
  static const _bondRetries = 10;
  static const _bondSettle = Duration(seconds: 16);

  /// Writes [target] to the coordinator and VERIFIES every requested channel
  /// actually landed, RE-ASSERTING up to [_bondRetries] times if Sonos silently
  /// drops satellites that don't finish joining (the Phase 0 finding — see
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
    for (var attempt = 1; attempt <= _bondRetries; attempt++) {
      cancel?.throwIfCancelled();
      try {
        await _deviceProps.addHtSatellite(soundbarIp: ip, map: target);
      } on TimeoutException {
        // Big bonding calls time out at 8s but the write still takes effect.
        onNote?.call('attempt $attempt: write timed out, verifying');
      } on SonosSoapException catch (e) {
        // Only UPnPError 800 ("satellite still mid-reshuffle") is the documented
        // transient fault. A malformed map (402) or an invalid action for this
        // coordinator (401) will never converge — surface it immediately instead
        // of retrying for ~160s and masking it as "channels never joined".
        if (e.faultCode != '800') rethrow;
        onNote?.call('attempt $attempt: write error 800 (mid-reshuffle), re-asserting');
      } catch (e) {
        // Bonding is eventually-consistent (confirmed on hardware): a write can
        // partially apply then settle, or return a transient UPnPError (e.g. 800
        // — "can't add a satellite that's still mid-reshuffle") while leaving some
        // channels bonded. Re-asserting the SAME map then converges (took ~4
        // tries on a real Beam rebuild). So treat ANY write error as "go verify",
        // and only fail if the topology never reaches the target.
        onNote?.call('attempt $attempt: write error ($e), re-asserting');
      }
      await interruptibleDelay(_bondSettle, cancel);
      try {
        system = system == null ? await discover() : await refresh(system, ip);
      } catch (e) {
        onNote?.call('attempt $attempt: topology read failed ($e), retrying');
        continue;
      }
      final member = system.memberByUuid(coordinator.uuid);
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

  /// Creates a bonded **speaker group** (stereo pair / zone / custom L-R layout)
  /// from [members] (≥2, each with a channel) plus an optional [sub]. The first
  /// member is the coordinator (stays the visible room); the rest go hidden.
  /// Snapshots every member's + the sub's name first so they restore on
  /// separation — Sonos absorbs them all into the coordinator's name.
  Future<void> createGroup({
    required List<({SonosDevice device, GroupChannel channel})> members,
    SonosDevice? sub,
  }) async {
    if (members.length < 2) {
      throw Exception('A group needs at least 2 speakers.');
    }
    final all = [for (final m in members) m.device, if (sub != null) sub];
    if (all.any((d) => d.ip == null)) {
      throw Exception('Speaker IP unknown; rescan and retry.');
    }
    final attrs = <String, ZoneAttributes>{};
    for (final d in all) {
      attrs[d.uuid] = await _deviceProps.getZoneAttributes(d.ip!);
    }
    await _saveZoneSnapshot(attrs);
    await _deviceProps.addBondedZones(
      ip: members.first.device.ip!,
      channelMapSet: buildGroupMap(
        [for (final m in members) (uuid: m.device.uuid, channel: m.channel)],
        subUuid: sub?.uuid,
      ),
    );
  }

  /// Detaches [ip] from any larger playback group into its own standalone group.
  /// Required before [separateGroup] — Sonos won't dissolve a bond while the
  /// coordinator is a non-coordinator member of another playback group (the call
  /// returns OK but no-ops). The caller should poll until standalone.
  Future<void> detachFromGroup(String ip) =>
      _avTransport.becomeCoordinatorOfStandaloneGroup(ip);

  /// Separates a bonded group and restores each member's original name. Dissolves
  /// using the group's LIVE [channelMapSet] (a custom map won't round-trip
  /// through a recipe). [members] are all bonded speakers (incl. any Sub),
  /// coordinator first, resolved by the caller for name restore + IPs. The group
  /// must already be its own coordinator — call [detachFromGroup] + settle first.
  Future<void> separateGroup({
    required List<SonosDevice> members,
    required String channelMapSet,
  }) async {
    if (members.isEmpty) return;
    final coordIp = members.first.ip;
    if (coordIp == null) throw Exception('Speaker IP unknown; rescan and retry.');
    await _deviceProps.separateBondedZones(
        ip: coordIp, channelMapSet: channelMapSet);
    await _restoreZoneNames(members);
  }

  /// Restores each member's saved room name after a group is dissolved (Sonos
  /// absorbs member names into the coordinator's on separate, and doesn't put
  /// them back). No-op when no snapshot was persisted — e.g. the group was
  /// created outside the app or prefs were cleared.
  Future<void> _restoreZoneNames(List<SonosDevice> members) async {
    final snap = await _loadZoneSnapshot([for (final m in members) m.uuid]);
    if (snap == null) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final m in members) {
      final want = snap[m.uuid];
      final ip = m.ip;
      if (want == null || ip == null) continue;
      if ((await _deviceProps.getZoneAttributes(ip)).zoneName != want.zoneName) {
        await _deviceProps.setZoneAttributes(ip, want);
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
        // A member of a bonded group (stereo pair / zone / custom): dissolve the
        // whole group. Detach from any playback group first, then SeparateStereoPair
        // with the LIVE map (the working group-removal — see [separateGroup]).
        if (m.isGroup && m.channelMapUuids.contains(uuid)) {
          final ip = m.ip;
          final cms = m.channelMapSet;
          if (ip != null && cms != null) {
            await _avTransport.becomeCoordinatorOfStandaloneGroup(ip);
            await Future<void>.delayed(const Duration(seconds: 4));
            await _deviceProps.separateBondedZones(ip: ip, channelMapSet: cms);
            // Same as separateGroup: Sonos leaves members under the coordinator's
            // absorbed name — restore them from the snapshot if we have one.
            final members = [
              m.uuid,
              ...m.channelMapUuids.where((u) => u != m.uuid),
            ].map(system.device).whereType<SonosDevice>().toList();
            await _restoreZoneNames(members);
          }
          return;
        }
      }
    }
  }

  /// Sets a speaker's room name (used to restore names on profile-apply), only
  /// writing if it differs — preserving the current icon/configuration.
  /// Returns whether a write actually happened (false = name already matched).
  Future<bool> setRoomName({required String ip, required String name}) async {
    final attrs = await _deviceProps.getZoneAttributes(ip);
    if (attrs.zoneName == name) return false;
    await _deviceProps.setZoneAttributes(
      ip,
      ZoneAttributes(
          zoneName: name, icon: attrs.icon, configuration: attrs.configuration),
    );
    return true;
  }

  String _zoneKey(Iterable<String> uuids) {
    final s = uuids.toList()..sort();
    return 'zone_snapshot_${s.join('_')}';
  }

  Future<void> _saveZoneSnapshot(Map<String, ZoneAttributes> attrs) async {
    await _store.setString(
      _zoneKey(attrs.keys),
      jsonEncode({
        for (final e in attrs.entries)
          e.key: {
            'name': e.value.zoneName,
            'icon': e.value.icon,
            'config': e.value.configuration,
          },
      }),
    );
  }

  Future<Map<String, ZoneAttributes>?> _loadZoneSnapshot(
      List<String> uuids) async {
    final raw = await _store.getString(_zoneKey(uuids));
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        e.key: ZoneAttributes(
          zoneName: (e.value as Map)['name'] as String,
          icon: (e.value)['icon'] as String? ?? '',
          configuration: (e.value)['config'] as String? ?? '',
        ),
    };
  }

}
