// Stereo-pair round-trip test (incl. the "are room names restored?" question).
//
//   dart run tool/stereopair.dart --left <room|uuid> --right <room|uuid>            # dry run
//   dart run tool/stereopair.dart --left <room|uuid> --right <room|uuid> --confirm  # LIVE
//
// With --confirm it: snapshots both room names -> CreateStereoPair -> reads
// topology -> SeparateStereoPair -> checks whether each speaker's name returned
// on its own, and restores via SetZoneAttributes if Sonos didn't. This both
// validates the feature and answers empirically whether names survive.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_description.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final leftSel = args['left'];
  final rightSel = args['right'];
  final confirm = args.containsKey('confirm');
  if (leftSel == null || rightSel == null) {
    print('Usage: dart run tool/stereopair.dart --left <room|uuid> --right <room|uuid> [--confirm]');
    exit(64);
  }

  print('🔎 Discovering…');
  final locations = await SsdpDiscovery().discover();
  final descriptions = DeviceDescriptionClient();
  final devices = <SonosDevice>[];
  for (final loc in locations) {
    try {
      devices.add(await descriptions.fetch(loc));
    } catch (_) {}
  }
  final left = _resolve(devices, leftSel);
  final right = _resolve(devices, rightSel);
  if (left.uuid == right.uuid) {
    print('❌ Left and right must differ.');
    exit(64);
  }
  final props = DevicePropertiesClient(SonosSoapClient());

  // Snapshot both names up front.
  final leftAttrs = await props.getZoneAttributes(left.ip!);
  final rightAttrs = await props.getZoneAttributes(right.ip!);

  print('\nPlan:');
  print('  LEFT  : ${left.roomName} (${left.modelName}) ${left.uuid} @ ${left.ip}');
  print('  RIGHT : ${right.roomName} (${right.modelName}) ${right.uuid} @ ${right.ip}');
  print('  ChannelMapSet: ${left.uuid}:LF,LF;${right.uuid}:RF,RF');
  print('📸 Snapshot names — left="${leftAttrs.zoneName}" right="${rightAttrs.zoneName}"');
  if (left.modelName != right.modelName) {
    print('🎚️  Mismatched models (${left.modelName} + ${right.modelName}) — the unlock.');
  }

  if (!confirm) {
    print('\n✅ DRY RUN — nothing changed. Re-run with --confirm for the live round-trip.');
    return;
  }

  final topo = ZoneTopologyClient(SonosSoapClient());

  print('\n➡️  Creating stereo pair… (polling up to ~21s for topology to settle)');
  await props.createStereoPair(ip: left.ip!, leftUuid: left.uuid, rightUuid: right.uuid);
  var hidden = false;
  for (var i = 0; i < 7; i++) {
    await Future<void>.delayed(const Duration(seconds: 3));
    final groups = await topo.getZoneGroups(left.ip!);
    final visible = groups.expand((g) => g.members).map((m) => m.uuid).toSet();
    hidden = !visible.contains(right.uuid);
    print('   [${(i + 1) * 3}s] right hidden=$hidden');
    if (hidden) break;
  }
  print(hidden
      ? '   ✅ Pair formed (right speaker hidden) — mismatched pairing is allowed.'
      : '   ⚠️  Right speaker never hid — the mismatched pair may have been rejected.');

  print('\n⬅️  Separating…');
  await props.separateStereoPair(ip: left.ip!, leftUuid: left.uuid, rightUuid: right.uuid);
  await _settle();

  final leftAfter = await props.getZoneAttributes(left.ip!);
  final rightAfter = await props.getZoneAttributes(right.ip!);
  print('   After separate — left="${leftAfter.zoneName}" right="${rightAfter.zoneName}"');

  final leftOk = leftAfter.zoneName == leftAttrs.zoneName;
  final rightOk = rightAfter.zoneName == rightAttrs.zoneName;
  print('   Sonos restored names natively? left=${leftOk ? "yes" : "NO"} right=${rightOk ? "yes" : "NO"}');

  if (!leftOk) {
    await props.setZoneAttributes(left.ip!, leftAttrs);
    print('   🔧 Restored left -> "${leftAttrs.zoneName}"');
  }
  if (!rightOk) {
    await props.setZoneAttributes(right.ip!, rightAttrs);
    print('   🔧 Restored right -> "${rightAttrs.zoneName}"');
  }
  print('\n🎉 Done. Names are back to the originals.');
}

Future<void> _settle() => Future<void>.delayed(const Duration(seconds: 4));

SonosDevice _resolve(List<SonosDevice> devices, String sel) {
  if (sel.startsWith('RINCON_')) {
    final m = devices.where((d) => d.uuid == sel);
    if (m.isEmpty) {
      print('❌ No device $sel');
      exit(1);
    }
    return m.first;
  }
  final byName = devices.where((d) => d.roomName.toLowerCase() == sel.toLowerCase()).toList();
  if (byName.isEmpty) {
    print('❌ No device in room "$sel".');
    exit(1);
  }
  if (byName.length > 1) {
    print('❌ "$sel" matches ${byName.length} devices — use a RINCON_ uuid.');
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
    if (key == 'confirm') {
      out[key] = 'true';
    } else if (i + 1 < argv.length) {
      out[key] = argv[++i];
    }
  }
  return out;
}
