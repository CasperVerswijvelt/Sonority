// Plays the identify chime on one speaker — validates the IdentifyService path
// (in-app HTTP server + AVTransport) against real hardware.
//
//   dart run tool/chirp.dart <room name | RINCON_uuid | ip>
//
// Use a standalone speaker. Interrupts whatever that speaker is playing.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:soyes/data/models/sonos_models.dart';
import 'package:soyes/data/sonos/device_description.dart';
import 'package:soyes/data/sonos/identify_service.dart';
import 'package:soyes/data/sonos/ssdp_discovery.dart';

Future<void> main(List<String> argv) async {
  final target = argv.isNotEmpty ? argv.first : null;
  if (target == null) {
    print('Usage: dart run tool/chirp.dart <room|uuid|ip>');
    exit(64);
  }

  print('🔎 Discovering…');
  final locations = await SsdpDiscovery().discover();
  final desc = DeviceDescriptionClient();
  final devices = <SonosDevice>[];
  for (final l in locations) {
    try {
      devices.add(await desc.fetch(l));
    } catch (_) {}
  }

  String? ip;
  String label = target;
  final byIp = devices.where((d) => d.ip == target);
  final byUuid = devices.where((d) => d.uuid == target);
  final byRoom =
      devices.where((d) => d.roomName.toLowerCase() == target.toLowerCase());
  if (byIp.isNotEmpty) {
    ip = byIp.first.ip;
    label = byIp.first.roomName;
  } else if (byUuid.isNotEmpty) {
    ip = byUuid.first.ip;
    label = byUuid.first.roomName;
  } else if (byRoom.length == 1) {
    ip = byRoom.first.ip;
    label = byRoom.first.roomName;
  } else if (byRoom.length > 1) {
    print('❌ "$target" matches ${byRoom.length} devices — use an IP or uuid.');
    exit(1);
  }

  if (ip == null) {
    print('❌ Could not resolve "$target".');
    exit(1);
  }

  print('🔊 Chiming on $label ($ip)…');
  final svc = IdentifyService(null, (m) => print('   · $m'));
  try {
    await svc.chirp(ip);
    print('   Sent. You should hear a ding-dong now.');
    // Keep the local server alive while the speaker fetches + plays.
    await Future<void>.delayed(const Duration(seconds: 4));
  } catch (e) {
    print('❌ Failed: $e');
    exitCode = 1;
  } finally {
    await svc.dispose();
  }
}
