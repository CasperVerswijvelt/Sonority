// Shared helper for the CLI tools: discover the system and resolve a
// room-name / RINCON-uuid / IP argument to a speaker IP. Used by chirp.dart,
// led_probe.dart, etc. so the discover+match logic lives in one place.

// ignore_for_file: avoid_print

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_description.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';

/// Discovers all players and resolves [target] (room name, `RINCON_…` uuid, or
/// IP) to its IP + room label. Prints progress/diagnostics and returns null if
/// nothing (or more than one room) matched.
Future<({String ip, String label})?> resolveSpeaker(String target) async {
  print('🔎 Discovering…');
  final locations = await SsdpDiscovery().discover();
  final desc = DeviceDescriptionClient();
  final devices = <SonosDevice>[];
  for (final l in locations) {
    try {
      devices.add(await desc.fetch(l));
    } catch (_) {}
  }

  final byIp = devices.where((d) => d.ip == target);
  final byUuid = devices.where((d) => d.uuid == target);
  final byRoom =
      devices.where((d) => d.roomName.toLowerCase() == target.toLowerCase());

  SonosDevice? match;
  if (byIp.isNotEmpty) {
    match = byIp.first;
  } else if (byUuid.isNotEmpty) {
    match = byUuid.first;
  } else if (byRoom.length == 1) {
    match = byRoom.first;
  } else if (byRoom.length > 1) {
    print('❌ "$target" matches ${byRoom.length} devices — use an IP or uuid.');
    return null;
  }

  final ip = match?.ip;
  if (match == null || ip == null) {
    print('❌ Could not resolve "$target".');
    return null;
  }
  return (ip: ip, label: match.roomName);
}
