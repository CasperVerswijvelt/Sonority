// Plays the identify chime on one speaker — validates the IdentifyService path
// (in-app HTTP server + AVTransport) against real hardware.
//
//   dart run tool/chirp.dart <room name | RINCON_uuid | ip>
//
// Use a standalone speaker. Interrupts whatever that speaker is playing.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/sonos/identify_service.dart';

import 'discover_util.dart';

Future<void> main(List<String> argv) async {
  final target = argv.isNotEmpty ? argv.first : null;
  if (target == null) {
    print('Usage: dart run tool/chirp.dart <room|uuid|ip>');
    exit(64);
  }

  final resolved = await resolveSpeaker(target);
  if (resolved == null) exit(1);
  final (:ip, :label) = resolved;

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
