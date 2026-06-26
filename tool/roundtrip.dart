// LIVE write round-trip for the dedicated-front unlock.
//
// ⚠️  WITH --confirm THIS RECONFIGURES YOUR REAL HOME THEATER. It is designed
// to be self-restoring: it snapshots the current layout, applies dedicated
// fronts, verifies them, then removes them to return the system to exactly the
// original state, verifying that too. If anything fails mid-way it prints the
// snapshot + the manual RemoveHTSatellite command to recover.
//
// Default (no --confirm) = DRY RUN: prints the exact AddHTSatellite map it
// would send and the restore plan, and writes nothing.
//
// Usage (run on the same Wi-Fi as your Sonos):
//   dart run tool/roundtrip.dart --bar "Woonkamer" --left "Gym" --right "Zolder"
//   dart run tool/roundtrip.dart --bar "Woonkamer" --left "Gym" --right "Zolder" --confirm
//
// Single-Amp fronts (one Amp drives both passive front speakers, AMP:LF,RF):
//   dart run tool/roundtrip.dart --bar "Woonkamer" --amp "Studio"
//   dart run tool/roundtrip.dart --bar "Woonkamer" --amp "Studio" --confirm
//
// --bar/--left/--right/--amp accept a room name (must be unique) or a RINCON_ UUID.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_description.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/front_layout.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final barSel = args['bar'];
  final leftSel = args['left'];
  final rightSel = args['right'];
  final ampSel = args['amp'];
  final confirm = args.containsKey('confirm');
  final applyOnly = args.containsKey('apply-only');
  final removeOnly = args.containsKey('remove-only');
  final ampMode = ampSel != null;

  if (barSel == null || (ampMode ? false : (leftSel == null || rightSel == null))) {
    print('Usage: dart run tool/roundtrip.dart --bar <room|uuid> '
        '(--left <room|uuid> --right <room|uuid> | --amp <room|uuid>) [--confirm]');
    exit(64);
  }

  print('🔎 Discovering system…');
  final locations = await SsdpDiscovery().discover();
  final descriptions = DeviceDescriptionClient();
  final devices = <SonosDevice>[];
  for (final loc in locations) {
    try {
      devices.add(await descriptions.fetch(loc));
    } catch (_) {}
  }
  if (devices.isEmpty) {
    print('❌ No devices found.');
    exit(1);
  }
  final anyIp = devices.first.ip!;
  final topology = ZoneTopologyClient(SonosSoapClient());
  var groups = await topology.getZoneGroups(anyIp);

  // Resolve the soundbar member + device.
  final soundbarDevice = _resolveDevice(devices, barSel, mustBeSoundbar: true);
  final soundbar = _findMember(groups, soundbarDevice.uuid);
  if (soundbar == null) {
    print('❌ Soundbar ${soundbarDevice.roomName} not found in topology.');
    exit(1);
  }
  // Front devices: a single Amp (both channels) or a left/right pair.
  final List<SonosDevice> fronts = ampMode
      ? [_resolveDevice(devices, ampSel)]
      : [_resolveDevice(devices, leftSel!), _resolveDevice(devices, rightSel!)];

  print('\nPlan:');
  print('  Soundbar : ${soundbarDevice.roomName} (${soundbarDevice.modelName}) '
      '${soundbarDevice.uuid} @ ${soundbar.ip}');
  if (ampMode) {
    final amp = fronts.first;
    print('  Fronts   : ${amp.roomName} (${amp.modelName}) ${amp.uuid} '
        '→ drives both L/R (AMP:LF,RF)');
  } else {
    print('  Front L  : ${fronts[0].roomName} (${fronts[0].modelName}) ${fronts[0].uuid}');
    print('  Front R  : ${fronts[1].roomName} (${fronts[1].modelName}) ${fronts[1].uuid}');
  }

  final snapshot = soundbar.htSatChanMapSet ?? '(none)';
  print('\n📸 Current HTSatChanMapSet (restore point):\n   $snapshot');

  final targetMap = ampMode
      ? buildAmpFrontsMap(
          soundbar: soundbar,
          soundbarDevice: soundbarDevice,
          ampDevice: fronts.first,
        )
      : buildDedicatedFrontsMap(
          soundbar: soundbar,
          soundbarDevice: soundbarDevice,
          leftSpeaker: fronts[0],
          rightSpeaker: fronts[1],
        );
  final mode = removeOnly
      ? 'REMOVE-ONLY (un-bond the fronts)'
      : applyOnly
          ? 'APPLY-ONLY (bond fronts, leave active)'
          : 'ROUND-TRIP (apply then restore)';
  print('\n📝 Would send AddHTSatellite with:\n   ${targetMap.encode()}');
  print('🧹 Remove command: RemoveHTSatellite ${fronts.map((d) => d.uuid).join(', ')}');
  print('🎚️  Mode: $mode');

  if (!ampMode) _sanityCheck(fronts[0], fronts[1]);
  if (ampMode && !fronts.first.isAmp) {
    print('⚠️  Note: ${fronts.first.modelName} is not an Amp; AMP:LF,RF assumes '
        'one device that drives both passive front speakers.');
  }

  if (!confirm) {
    print('\n✅ DRY RUN complete — nothing was changed. '
        'Re-run with --confirm (optionally --apply-only / --remove-only).');
    return;
  }

  final barIp = soundbar.ip;
  if (barIp == null) {
    print('❌ Soundbar IP unknown.');
    exit(1);
  }
  final deviceProps = DevicePropertiesClient(SonosSoapClient());

  // --remove-only: just un-bond the fronts and verify.
  if (removeOnly) {
    await _remove(deviceProps, topology, barIp, soundbarDevice, fronts,
        expected: snapshot);
    print('\n🎉 Remove complete.');
    return;
  }

  try {
    print('\n➡️  Applying dedicated fronts…');
    await deviceProps.addHtSatellite(soundbarIp: barIp, map: targetMap);
    await _settle();
    groups = await topology.getZoneGroups(barIp);
    final afterAdd = _findMember(groups, soundbarDevice.uuid);
    final ok = afterAdd?.hasDedicatedFronts ?? false;
    print(ok
        ? '   ✅ Verified: dedicated fronts are active.'
        : '   ⚠️  Could not confirm fronts in topology — check the Sonos app.');
    if (afterAdd?.htSatChanMapSet != null) {
      print('   Now: ${afterAdd!.htSatChanMapSet}');
    }
  } catch (e) {
    print('❌ AddHTSatellite failed: $e');
    print('   System should be unchanged. If not, restore with the Sonos app.');
    exit(1);
  }

  if (applyOnly) {
    final frontArgs = ampMode
        ? '--amp "$ampSel"'
        : '--left "$leftSel" --right "$rightSel"';
    print('\n🔊 Fronts are live — go listen! When you want them gone, run:');
    print('   dart run tool/roundtrip.dart --bar "$barSel" '
        '$frontArgs --confirm --remove-only');
    return;
  }

  await _remove(deviceProps, topology, barIp, soundbarDevice, fronts,
      expected: snapshot);
  print('\n🎉 Round-trip complete.');
}

Future<void> _remove(
  DevicePropertiesClient deviceProps,
  ZoneTopologyClient topology,
  String barIp,
  SonosDevice soundbarDevice,
  List<SonosDevice> fronts, {
  required String expected,
}) async {
  try {
    print('\n⬅️  Removing the front${fronts.length == 1 ? '' : 's'}…');
    for (final f in fronts) {
      await deviceProps.removeHtSatellite(soundbarIp: barIp, satelliteUuid: f.uuid);
    }
    await _settle();
    final groups = await topology.getZoneGroups(barIp);
    final after = _findMember(groups, soundbarDevice.uuid);
    final restored = after?.htSatChanMapSet ?? '(none)';
    final back = !(after?.hasDedicatedFronts ?? false);
    print('   Now: $restored');
    print(back && restored == expected
        ? '   ✅ Verified: system restored to the original layout.'
        : '   ⚠️  Layout differs from the snapshot — compare above and check the app.');
  } catch (e) {
    print('❌ Remove failed: $e');
    print('   Recover manually — on the soundbar at $barIp call '
        'RemoveHTSatellite for ${fronts.map((d) => d.uuid).join(' and ')}, '
        'or re-pair via the Sonos app.');
    exit(1);
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(seconds: 4));

void _sanityCheck(SonosDevice left, SonosDevice right) {
  if (left.uuid == right.uuid) {
    print('❌ Left and right must be different speakers.');
    exit(64);
  }
  if (left.modelName != right.modelName) {
    print('⚠️  Note: ${left.modelName} ≠ ${right.modelName}. A matched pair is '
        'recommended for real use (fine for a round-trip test).');
  }
}

ZoneGroupMember? _findMember(List<ZoneGroup> groups, String uuid) {
  for (final g in groups) {
    for (final m in g.members) {
      if (m.uuid == uuid) return m;
    }
  }
  return null;
}

SonosDevice _resolveDevice(List<SonosDevice> devices, String selector,
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

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) continue;
    final key = a.substring(2);
    const flags = {'confirm', 'apply-only', 'remove-only'};
    if (flags.contains(key)) {
      out[key] = 'true';
    } else if (i + 1 < argv.length) {
      out[key] = argv[++i];
    }
  }
  return out;
}
