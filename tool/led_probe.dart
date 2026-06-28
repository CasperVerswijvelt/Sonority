// Blinks a speaker's status LED to identify it — validates the LedIdentifyClient
// path (DeviceProperties GetLEDState/SetLEDState) against real hardware, and
// confirms the actions exist by dumping the DeviceProperties SCPD.
//
//   dart run tool/led_probe.dart <room name | RINCON_uuid | ip>
//
// Non-destructive: it captures the current LED state and restores it after
// blinking. Works on any Sonos that exposes SetLEDState.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sonority/data/sonos/led_identify.dart';
import 'package:xml/xml.dart';

import 'discover_util.dart';

Future<void> main(List<String> argv) async {
  final target = argv.isNotEmpty ? argv.first : null;
  if (target == null) {
    print('Usage: dart run tool/led_probe.dart <room|uuid|ip>');
    exit(64);
  }

  final resolved = await resolveSpeaker(target);
  if (resolved == null) exit(1);
  final (:ip, :label) = resolved;

  // Confirm the LED actions exist on this model (SCPD dump).
  await _dumpLedActions(ip);

  final led = LedIdentifyClient(null, (m) => print('   · $m'));
  try {
    final before = await led.getLedState(ip);
    print('💡 LED on $label ($ip) is currently ${before == null ? 'unknown' : (before ? 'on' : 'off')}.');
    print('   Blinking… watch the speaker.');
    await led.blink(ip);
    final after = await led.getLedState(ip);
    print('   Done. LED is now ${after == null ? 'unknown' : (after ? 'on' : 'off')} '
        '(should match the original).');
  } catch (e) {
    print('❌ Failed: $e');
    exitCode = 1;
  }
}

/// Fetches the DeviceProperties SCPD and lists any LED-related actions, so we
/// can confirm SetLEDState/GetLEDState are supported on this hardware.
Future<void> _dumpLedActions(String ip) async {
  try {
    final res = await http
        .get(Uri.parse('http://$ip:1400/xml/DeviceProperties1.xml'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      print('   SCPD fetch failed: HTTP ${res.statusCode}');
      return;
    }
    final doc = XmlDocument.parse(res.body);
    final led = doc.findAllElements('action').where(
        (a) => (a.getElement('name')?.innerText ?? '').contains('LED'));
    if (led.isEmpty) {
      print('   ⚠️  No *LED* actions found in DeviceProperties SCPD.');
      return;
    }
    print('   DeviceProperties LED actions:');
    for (final a in led) {
      print('     • ${a.getElement('name')?.innerText}');
    }
  } catch (e) {
    print('   SCPD dump skipped: $e');
  }
}
