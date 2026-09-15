// Read-only probe for the spectral-tuning (`:1443`) path — run this BEFORE
// trusting an EQ apply on unfamiliar hardware.
//
//   dart run tool/spectral_probe.dart              # every discovered speaker
//   dart run tool/spectral_probe.dart <room|uuid|ip>
//
// Why this exists: six of the ten rules in CLAUDE.md's "Spectral tuning" section
// fail with an **HTTP 200 and nothing stored**, so the app cannot tell you it got
// them wrong. The two that are per-model and per-layout — the channel ids and the
// per-channel sample rate — are exactly what this dumps. Anything surprising here
// (a channel list you didn't expect, a rate that isn't 44100 or 8138, a section
// ceiling below 16) is a reason to look before applying.
//
// WRITES NOTHING. `GetDeviceConfig` is a read, and the `:1400` calibration status
// is a read; no tuning is applied, enabled or cleared.

// ignore_for_file: avoid_print

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/data/sonos/trueplay_apply.dart';

import 'discover_util.dart';

Future<void> main(List<String> args) async {
  final target = args.where((a) => !a.startsWith('-')).firstOrNull;

  List<SonosDevice> devices;
  if (target == null) {
    print('🔎 Discovering…');
    devices = await discoverDevices();
  } else {
    final hit = await resolveSpeaker(target);
    if (hit == null) return;
    devices = (await discoverDevices()).where((d) => d.ip == hit.ip).toList();
  }
  if (devices.isEmpty) {
    print('No speakers found.');
    return;
  }

  final apply = const TrueplayApplyClient();
  final calibration = RoomCalibrationClient();

  for (final d in devices..sort((a, b) => a.roomName.compareTo(b.roomName))) {
    final ip = d.ip;
    print('\n── ${d.roomName} · ${d.typeLabel} · ${ip ?? 'no ip'}');
    if (ip == null) continue;

    try {
      final c = await calibration.getStatus(ip);
      print('   tuning stored: ${c.available} · enabled: ${c.enabled}');
      if (c.available) {
        print('   ⚠️  applying an EQ here REPLACES this tuning permanently — '
            'coefficients cannot be read back off a speaker.');
      }
    } catch (e) {
      print('   calibration status unreadable: $e');
    }

    try {
      final r = await apply.readDeviceConfig(ip: ip, rincon: d.uuid);
      final cfg = r.config;
      if (cfg == null) {
        print('   GetDeviceConfig → HTTP ${r.status}, unparseable:');
        print('   ${r.raw.length > 200 ? '${r.raw.substring(0, 200)}…' : r.raw}');
        continue;
      }
      print('   model ${cfg.model} · maxSections ${cfg.maxSections}');
      for (var i = 0; i < cfg.channels.length; i++) {
        final rate = cfg.sampleRates.length > i ? cfg.sampleRates[i] : null;
        final note = rate == 8138 ? '  ← sub rate' : '';
        print('   channel ${cfg.channels[i]}  @ ${rate ?? '?'} Hz$note');
      }
      if (cfg.channels.isEmpty) {
        print('   no tunable channels — nothing can be authored for this '
            'speaker in its current role (an unbonded Sub reads like this).');
      }
    } catch (e) {
      print('   GetDeviceConfig failed: $e');
    }
  }
  print('\nRead-only: nothing was applied, enabled or cleared.');
}
