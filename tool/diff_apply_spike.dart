// SPIKE — validates the diff-based HT apply on real hardware before we wire it
// into the engine. Answers three questions the strip-then-rebuild path never
// tested:
//
//   (a) NO-OP   : when the target equals the live layout, diffHtLayout reports
//                 isNoOp + nothing to remove → we can issue ZERO writes.
//   (b) ADDITIVE: remove ONE satellite (the sub), then AddHTSatellite the full
//                 target (a superset, drops nobody) WITHOUT stripping the rest.
//                 Does the sub re-bond while fronts/rears stay put?
//   (c) CHANGE  : swap two surround UUIDs (LR↔RR). diffHtLayout flags both as
//                 toRemove → remove both, then AddHTSatellite the swapped target.
//                 Does it converge?
//
// ⚠️  WITH --confirm THIS MUTATES YOUR REAL HOME THEATER and Sonos will
// INVALIDATE TRUEPLAY across the set (documented gotcha). It snapshots the
// current HTSatChanMapSet up front and restores it in a finally — strip to bare
// then re-add the snapshot — so it ends where it started. If it can't restore it
// prints the snapshot for manual recovery via the Sonos app.
//
// Usage (same Wi-Fi as your Sonos):
//   dart run tool/diff_apply_spike.dart --bar "Woonkamer"            # dry run: (a) only
//   dart run tool/diff_apply_spike.dart --bar RINCON_…01400 --confirm
//
// Selector: a unique room name or a RINCON_ uuid (use a uuid when a room name is
// shared by several devices, e.g. a multi-speaker Woonkamer).

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/channel_map.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/front_layout.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

import 'discover_util.dart';

Future<void> main(List<String> argv) async {
  final args = parseArgs(argv, flags: {'confirm'});
  final barSel = args['bar'];
  final confirm = args.containsKey('confirm');
  if (barSel == null) {
    print('Usage: dart run tool/diff_apply_spike.dart --bar <room|uuid> [--confirm]');
    exit(64);
  }

  final devices = await discoverDevices();
  if (devices.isEmpty) {
    print('❌ No devices found.');
    exit(1);
  }
  final barDevice = resolveDevice(devices, barSel, mustBeSoundbar: true);

  final topology = ZoneTopologyClient(SonosSoapClient());
  final props = DevicePropertiesClient(SonosSoapClient());

  var bar = await _member(topology, barDevice.ip!, barDevice.uuid);
  if (bar == null) {
    print('❌ Soundbar ${barDevice.roomName} not found in topology.');
    exit(1);
  }
  final snapshot = bar.htSatChanMapSet ?? '(none)';
  print('📸 Snapshot (RESTORE POINT): $snapshot\n');

  // ── (a) NO-OP — pure diff check, never writes ──────────────────────────────
  final noOp = diffHtLayout(current: bar, target: ChannelMap.parse(snapshot));
  print('(a) NO-OP: isNoOp=${noOp.isNoOp}, toRemove=${noOp.toRemove}');
  print(noOp.isNoOp && noOp.toRemove.isEmpty
      ? '   ✅ Re-applying the current layout needs ZERO writes.'
      : '   ❌ Expected a no-op for target==current.');

  if (!confirm) {
    print('\n✅ DRY RUN — only the no-op check ran. Re-run with --confirm for (b)+(c).');
    return;
  }

  final barIp = barDevice.ip!;
  try {
    // ── (b) ADDITIVE — drop the sub, re-add the full map without stripping ────
    final subUuids = bar.uuidsForChannel(SonosChannel.sub);
    if (subUuids.isEmpty) {
      print('\n(b) ADDITIVE: skipped — no sub bonded to drop.');
    } else {
      print('\n(b) ADDITIVE: removing sub ${subUuids.first}, then AddHTSatellite '
          'the full snapshot (superset) WITHOUT stripping fronts/rears…');
      await props.removeHtSatellite(soundbarIp: barIp, satelliteUuid: subUuids.first);
      await _settleLong();
      final r = await _bondVerify(props, topology, barDevice, ChannelMap.parse(snapshot));
      _report('(b)', r);
      bar = await _restore(props, topology, barDevice, snapshot);
    }

    // ── (c) CHANGE — swap LR↔RR via diff (remove both, add swapped) ───────────
    final assign = Map<SonosChannel, String>.from(bar!.channelAssignments);
    final lr = assign[SonosChannel.leftRear];
    final rr = assign[SonosChannel.rightRear];
    if (lr == null || rr == null) {
      print('\n(c) CHANGE: skipped — needs both rear surrounds bonded.');
    } else {
      assign[SonosChannel.leftRear] = rr;
      assign[SonosChannel.rightRear] = lr;
      final swapped = buildLayoutMap(
        soundbar: bar,
        soundbarDevice: barDevice,
        desired: assign,
        preserveExisting: false,
      );
      final diff = diffHtLayout(current: bar, target: swapped);
      print('\n(c) CHANGE: swap LR↔RR. diff.toRemove=${diff.toRemove} '
          '(expect both surrounds). Removing them, then AddHTSatellite swapped…');
      await props.removeHtSatellites(barIp, diff.toRemove);
      await _settleLong();
      final r = await _bondVerify(props, topology, barDevice, swapped);
      _report('(c)', r);
    }
  } catch (e) {
    print('❌ Failed mid-spike: $e');
  } finally {
    final restored = await _restore(props, topology, barDevice, snapshot);
    final ok = restored?.htSatChanMapSet == snapshot;
    print(ok
        ? '\n🎉 Restored to the original layout.'
        : '\n⚠️  Final layout differs from snapshot — check the Sonos app.\n   Original: $snapshot');
  }
}

extension on DevicePropertiesClient {
  Future<void> removeHtSatellites(String ip, Iterable<String> uuids) async {
    for (final u in uuids) {
      await removeHtSatellite(soundbarIp: ip, satelliteUuid: u);
    }
  }
}

/// Re-asserts [target] until every channel verifies (mirrors the engine's
/// bondAndVerify — tools can't import the repository, which pulls in Flutter).
Future<({bool ok, int attempts, List<SonosChannel> missing})> _bondVerify(
  DevicePropertiesClient props,
  ZoneTopologyClient topology,
  SonosDevice bar,
  ChannelMap target, {
  int retries = 8,
}) async {
  final wanted = <SonosChannel, Set<String>>{};
  for (final e in target.entries.skip(1)) {
    for (final ch in e.channels) {
      (wanted[ch] ??= <String>{}).add(e.uuid);
    }
  }
  var missing = wanted.keys.toList();
  for (var attempt = 1; attempt <= retries; attempt++) {
    try {
      await props.addHtSatellite(soundbarIp: bar.ip!, map: target);
    } on TimeoutException {
      print('     attempt $attempt: write timed out, verifying');
    } catch (e) {
      print('     attempt $attempt: write error ($e), verifying');
    }
    await _settleLong();
    final m = await _member(topology, bar.ip!, bar.uuid);
    missing = [
      for (final w in wanted.entries)
        if (!(m?.uuidsForChannel(w.key).toSet() ?? const <String>{})
            .containsAll(w.value))
          w.key,
    ];
    if (missing.isEmpty) {
      return (ok: true, attempts: attempt, missing: const <SonosChannel>[]);
    }
    print('     attempt $attempt: ${missing.map((c) => c.token).join('/')} not bonded yet');
  }
  return (ok: false, attempts: retries, missing: missing);
}

void _report(String tag, ({bool ok, int attempts, List<SonosChannel> missing}) r) {
  print(r.ok
      ? '   ✅ $tag converged in ${r.attempts} attempt(s) WITHOUT a strip.'
      : '   ❌ $tag did NOT converge after ${r.attempts}: missing '
          '${r.missing.map((c) => c.token).join(', ')}.');
}

/// Strip the bar to bare, then re-add [snapshot] and settle — the known-good
/// recovery used between sub-tests and in the finally.
Future<ZoneGroupMember?> _restore(
  DevicePropertiesClient props,
  ZoneTopologyClient topology,
  SonosDevice bar,
  String snapshot,
) async {
  print('   ⬅️  restoring…');
  final cur = await _member(topology, bar.ip!, bar.uuid);
  final sats = <String>{
    ...?cur?.channelAssignments.values,
    ...?cur?.satellites.map((s) => s.uuid),
  };
  for (final u in sats) {
    try {
      await props.removeHtSatellite(soundbarIp: bar.ip!, satelliteUuid: u);
    } catch (_) {}
  }
  await _settleLong();
  if (snapshot != '(none)') {
    final orig = ChannelMap.parse(snapshot);
    if (orig.entries.length > 1) {
      await _bondVerify(props, topology, bar, orig);
    }
  }
  return _member(topology, bar.ip!, bar.uuid);
}

Future<ZoneGroupMember?> _member(
    ZoneTopologyClient topology, String ip, String uuid) async {
  final groups = await topology.getZoneGroups(ip);
  for (final g in groups) {
    for (final m in g.members) {
      if (m.uuid == uuid) return m;
    }
  }
  return null;
}

/// Bonding is eventually-consistent with a ~15s topology lag — settle longer
/// than discover_util.settle()'s 4s before re-reading after a bonding write.
Future<void> _settleLong() => Future<void>.delayed(const Duration(seconds: 16));
