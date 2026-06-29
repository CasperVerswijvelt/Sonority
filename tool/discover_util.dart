// Shared helpers for the CLI tools: SSDP discovery, speaker resolution, and
// tiny arg/timing utilities — so the discover+match logic lives in one place.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_description.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';

/// Discovers all players and fetches each one's device description, silently
/// skipping any whose description fetch fails. The shared read path for tools.
Future<List<SonosDevice>> discoverDevices() async {
  final locations = await SsdpDiscovery().discover();
  final desc = DeviceDescriptionClient();
  final devices = <SonosDevice>[];
  for (final l in locations) {
    try {
      devices.add(await desc.fetch(l));
    } catch (_) {}
  }
  return devices;
}

/// Discovers all players and resolves [target] (room name, `RINCON_…` uuid, or
/// IP) to its IP + room label. Prints progress/diagnostics and returns null if
/// nothing (or more than one room) matched.
Future<({String ip, String label})?> resolveSpeaker(String target) async {
  print('🔎 Discovering…');
  final devices = await discoverDevices();

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

/// Resolves [selector] (room name or `RINCON_…` uuid) against an already
/// discovered [devices] list to a single [SonosDevice]. Prints an error and
/// exits the process on no/ambiguous match (tools want fail-fast here).
SonosDevice resolveDevice(List<SonosDevice> devices, String selector,
    {bool mustBeSoundbar = false}) {
  if (selector.startsWith('RINCON_')) {
    final match = devices.where((d) => d.uuid == selector);
    if (match.isEmpty) {
      print('❌ No device with uuid $selector');
      exit(1);
    }
    return match.first;
  }
  final byName = devices
      .where((d) => d.roomName.toLowerCase() == selector.toLowerCase())
      .where((d) => !mustBeSoundbar || d.isSoundbar)
      .toList();
  if (byName.isEmpty) {
    print('❌ No ${mustBeSoundbar ? "soundbar" : "device"} in room "$selector". '
        'Use a RINCON_ uuid instead.');
    exit(1);
  }
  if (byName.length > 1) {
    print('❌ Room "$selector" matches ${byName.length} devices: '
        '${byName.map((d) => "${d.modelName} ${d.uuid}").join(", ")}. '
        'Use a RINCON_ uuid to disambiguate.');
    exit(1);
  }
  return byName.first;
}

/// Minimal `--key value` / `--flag` parser. Names in [flags] are treated as
/// boolean (`'true'` when present); everything else consumes the next token.
Map<String, String> parseArgs(List<String> argv,
    {Set<String> flags = const {}}) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) continue;
    final key = a.substring(2);
    if (flags.contains(key)) {
      out[key] = 'true';
    } else if (i + 1 < argv.length) {
      out[key] = argv[++i];
    }
  }
  return out;
}

/// Fixed wait for Sonos topology to begin settling after a write.
Future<void> settle() => Future<void>.delayed(const Duration(seconds: 4));
