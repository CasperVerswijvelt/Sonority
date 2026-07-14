// PHASE 0 SPIKE — answers the gating unknown for in-app full HT setup AND the
// Phase 3 "apply a saved profile" primitive in one shot:
//
//   "Can a single AddHTSatellite rebuild a FULL home-theater map
//    (CC + LF/RF + LR/RR + SW) from a BARE soundbar — i.e. bond rears + sub +
//    fronts from scratch — rather than only appending fronts to an existing
//    rears/sub config (all the engine has ever done)?"
//
// ⚠️  WITH --confirm THIS TEARS DOWN AND REBUILDS YOUR REAL HOME THEATER, and
// Sonos will INVALIDATE TRUEPLAY across the whole set (documented gotcha). It is
// self-restoring: it snapshots the current HTSatChanMapSet, strips the bar to
// bare (RemoveHTSatellite every satellite), then re-applies the snapshot in ONE
// AddHTSatellite call and verifies every channel landed exactly as before. If a
// role is missing it prints the snapshot so you can rebuild via the Sonos app.
//
// By default it rebuilds the CURRENT layout (the realistic profile-apply test).
// Optionally pass explicit roles to build a DIFFERENT layout from bare instead.
//
// Usage (same Wi-Fi as your Sonos):
//   dart run tool/full_layout.dart --bar "Woonkamer"                       # dry run
//   dart run tool/full_layout.dart --bar RINCON_542A1B98B52201400 --confirm
//   dart run tool/full_layout.dart --bar <bar> --rear-left A --rear-right B --sub S --confirm
//
// Selectors accept a unique room name or a RINCON_ uuid (use uuids when a room
// name is shared by several devices, e.g. a multi-speaker Woonkamer).

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/channel_map.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

import 'discover_util.dart';

Future<void> main(List<String> argv) async {
  final args = parseArgs(argv, flags: {'confirm'});
  final barSel = args['bar'];
  final confirm = args.containsKey('confirm');
  if (barSel == null) {
    print('Usage: dart run tool/full_layout.dart --bar <room|uuid> '
        '[--left .. --right .. --rear-left .. --rear-right .. --sub ..] [--confirm]');
    exit(64);
  }

  print('🔎 Discovering system…');
  final devices = await discoverDevices();
  if (devices.isEmpty) {
    print('❌ No devices found.');
    exit(1);
  }
  final anyIp = devices.first.ip!;
  final topology = ZoneTopologyClient(SonosSoapClient());
  var groups = await topology.getZoneGroups(anyIp);

  final barDevice = resolveDevice(devices, barSel, mustBeSoundbar: true);
  final bar = _findMember(groups, barDevice.uuid);
  final barIp = bar?.ip;
  if (bar == null || barIp == null) {
    print('❌ Soundbar ${barDevice.roomName} not found / no IP.');
    exit(1);
  }

  final snapshot = bar.htSatChanMapSet ?? '(none)';

  // Explicit roles → build a different layout from bare; otherwise rebuild the
  // current one (the realistic profile-apply test).
  final roles = <(SonosChannel, SonosDevice)>[
    if (args['left'] != null) (SonosChannel.leftFront, resolveDevice(devices, args['left']!)),
    if (args['right'] != null) (SonosChannel.rightFront, resolveDevice(devices, args['right']!)),
    if (args['rear-left'] != null) (SonosChannel.leftRear, resolveDevice(devices, args['rear-left']!)),
    if (args['rear-right'] != null) (SonosChannel.rightRear, resolveDevice(devices, args['rear-right']!)),
    if (args['sub'] != null) (SonosChannel.sub, resolveDevice(devices, args['sub']!)),
  ];
  final rebuild = roles.isEmpty;
  final target = rebuild
      ? ChannelMap.parse(snapshot)
      : ChannelMap([
          ChannelMapEntry.fromChannels(barDevice.uuid, [SonosChannel.center]),
          for (final (ch, dev) in roles) ChannelMapEntry.fromChannels(dev.uuid, [ch]),
        ]);

  if (rebuild && target.entries.length <= 1) {
    print('❌ Bar has no satellites to rebuild — pass explicit roles to test a '
        'from-scratch layout (--rear-left/--rear-right/--sub/--left/--right).');
    exit(64);
  }

  print('\nPlan (${rebuild ? 'REBUILD current layout' : 'BUILD new layout'} from bare):');
  print('  Soundbar : ${barDevice.roomName} (${barDevice.modelName}) ${barDevice.uuid} @ $barIp');
  for (final e in target.entries.skip(1)) {
    final d = devices.where((x) => x.uuid == e.uuid).cast<SonosDevice?>().firstWhere((_) => true, orElse: () => null);
    print('  ${e.tokens.join(',').padRight(5)}: ${d?.roomName ?? '?'} (${d?.modelName ?? '?'}) ${e.uuid}');
  }
  print('\n📸 Current HTSatChanMapSet (RESTORE POINT — keep this):\n   $snapshot');
  print('\n📝 Sequence: strip bar to bare → ONE AddHTSatellite with:\n   ${target.encode()}');
  print('⚠️  This tears down your real 5.1 and WIPES TRUEPLAY across the set.');

  if (!confirm) {
    print('\n✅ DRY RUN — nothing changed. Re-run with --confirm when ready.');
    return;
  }

  final props = DevicePropertiesClient(SonosSoapClient());
  try {
    // 1. Strip to bare — the from-scratch precondition.
    final current = ChannelMap.parse(snapshot);
    if (current.entries.length > 1) {
      print('\n🧨 Stripping bar to bare…');
      for (final e in current.entries.skip(1)) {
        await props.removeHtSatellite(soundbarIp: barIp, satelliteUuid: e.uuid);
      }
      await _settle();
      groups = await topology.getZoneGroups(barIp);
      final bare = _findMember(groups, barDevice.uuid);
      print((bare?.channelAssignments.isEmpty ?? true)
          ? '   ✅ Bar is bare.'
          : '   ⚠️  Bar still shows satellites — proceeding.');
    }

    // 2. The test: one AddHTSatellite with the full map.
    print('\n➡️  Applying full map in ONE AddHTSatellite call…');
    await props.addHtSatellite(soundbarIp: barIp, map: target);
    await _settle();
    groups = await topology.getZoneGroups(barIp);
    final after = _findMember(groups, barDevice.uuid);
    final assigned = after?.channelAssignments ?? const {};
    print('   Topology now: ${after?.htSatChanMapSet ?? '(none)'}');

    print('\n   === RESULT (the Phase 0 answer) ===');
    var allOk = true;
    for (final e in target.entries.skip(1)) {
      for (final ch in e.channels) {
        final ok = assigned[ch] == e.uuid;
        allOk = allOk && ok;
        print('     ${ok ? '✅' : '❌'} ${ch.token}: expected ${e.uuid} → got ${assigned[ch] ?? '(missing)'}');
      }
    }
    print(allOk
        ? '   ✅ YES — one AddHTSatellite rebuilt the FULL layout from bare. '
            'In-app full HT setup + profile-apply are feasible.'
        : '   ❌ NO — some roles did not land from a single call. HT surround/sub '
            'steps must fall back to finishing in the Sonos app.');
    print('   ===================================');

    if (rebuild && after?.htSatChanMapSet == snapshot) {
      print('\n🎉 System is back to its original layout (rebuild == restore).');
    } else if (rebuild) {
      print('\n⚠️  Rebuilt map differs from snapshot — compare above. '
          'Original:\n   $snapshot');
    } else {
      // Built a different layout: tear it down and restore the original.
      await _restore(props, topology, barIp, barDevice, target, snapshot);
    }
  } catch (e) {
    print('❌ Failed mid-test: $e');
    print('   Attempt restore via the Sonos app using the snapshot:\n   $snapshot');
    exit(1);
  }
}

Future<void> _restore(
  DevicePropertiesClient props,
  ZoneTopologyClient topology,
  String barIp,
  SonosDevice barDevice,
  ChannelMap applied,
  String snapshot,
) async {
  print('\n⬅️  Restoring original layout…');
  for (final e in applied.entries.skip(1)) {
    await props.removeHtSatellite(soundbarIp: barIp, satelliteUuid: e.uuid);
  }
  await _settle();
  final orig = snapshot == '(none)' ? null : ChannelMap.parse(snapshot);
  if (orig != null && orig.entries.length > 1) {
    await props.addHtSatellite(soundbarIp: barIp, map: orig);
    await _settle();
  }
  final groups = await topology.getZoneGroups(barIp);
  final restored = _findMember(groups, barDevice.uuid)?.htSatChanMapSet ?? '(none)';
  print(restored == snapshot
      ? '   ✅ Restored to the original layout.'
      : '   ⚠️  Differs from snapshot — check the Sonos app. Original:\n   $snapshot');
}

Future<void> _settle() => Future<void>.delayed(const Duration(seconds: 5));

ZoneGroupMember? _findMember(List<ZoneGroup> groups, String uuid) {
  for (final g in groups) {
    for (final m in g.members) {
      if (m.uuid == uuid) return m;
    }
  }
  return null;
}
