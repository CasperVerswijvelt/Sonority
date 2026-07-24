// Group in-place re-assert spike — does `AddBondedZones` reconfigure a LIVE
// speaker group in place (add / remove / reassign members WITHOUT dissolving),
// the way `AddHTSatellite` does for home theaters? Never tested before.
//
//   dart run tool/group_reassert_spike.dart            # dry run (plan only)
//   dart run tool/group_reassert_spike.dart --confirm  # LIVE, self-restoring
//
// Self-restoring: snapshots every existing zone + all involved room names up
// front, dissolves them to free 3 standalone speakers, runs the experiment on a
// throwaway A+B(+C) zone, then in a `finally` rebuilds the ORIGINAL zones
// exactly and restores names, verifying the end state. ⚠️ touches only zoneable
// speakers already in zones; never the home theater.
//
// Prints, per step, whether Sonos accepted the re-assert, how many attempts /
// faults it took, and the resulting topology (coordinator ChannelMapSet + each
// watched member's visibility) — so we can see if a removed member frees cleanly
// or is left orphaned Invisible.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/av_transport.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

import 'discover_util.dart';

late final DevicePropertiesClient props;
late final AvTransportClient av;
late final ZoneTopologyClient topo;
late final String anyIp;
final ipByUuid = <String, String>{};

/// One member's live standing in the topology.
enum Standing { coordinatorVisible, memberVisible, invisible, absent }

Future<void> main(List<String> argv) async {
  final args = parseArgs(argv, flags: {'confirm'});
  final confirm = args.containsKey('confirm');

  print('🔎 Discovering…');
  final devices = await discoverDevices();
  for (final d in devices) {
    if (d.ip != null) ipByUuid[d.uuid] = d.ip!;
  }
  if (ipByUuid.isEmpty) {
    print('❌ No reachable Sonos devices.');
    exit(1);
  }
  anyIp = ipByUuid.values.first;
  props = DevicePropertiesClient(SonosSoapClient());
  av = AvTransportClient(SonosSoapClient());
  topo = ZoneTopologyClient(SonosSoapClient());

  // Snapshot every existing zone (distinct ChannelMapSet), coordinator first.
  final zones = await _readZones();
  if (zones.isEmpty) {
    print('❌ No existing zones to borrow speakers from. Create ≥1 zone first.');
    exit(1);
  }
  final poolUuids = <String>[];
  for (final z in zones) {
    for (final u in z.memberUuids) {
      if (!poolUuids.contains(u)) poolUuids.add(u);
    }
  }
  print('\n📋 Existing zones (will be dissolved, then rebuilt exactly):');
  for (final z in zones) {
    print('   • coord ${_label(z.coordUuid)}  map=${z.map}');
  }
  if (poolUuids.length < 3) {
    print('\n❌ Need ≥3 zoneable speakers across existing zones; found '
        '${poolUuids.length}. Add another speaker to a zone and retry.');
    exit(1);
  }
  // SSDP/description fetch is flaky; a missing pool-member IP would crash mid-run.
  // Re-discover (merging) until every zone member resolves, then bail clearly.
  for (var attempt = 0; attempt < 4 && poolUuids.any((u) => !ipByUuid.containsKey(u)); attempt++) {
    for (final d in await discoverDevices()) {
      if (d.ip != null) ipByUuid[d.uuid] = d.ip!;
    }
  }
  final unresolved = poolUuids.where((u) => !ipByUuid.containsKey(u)).toList();
  if (unresolved.isNotEmpty) {
    print('\n❌ Could not resolve IPs for: ${unresolved.join(", ")}. '
        'Discovery flaked — nothing changed, just retry.');
    exit(1);
  }

  // Snapshot names for every pool speaker so we can restore them.
  final names = <String, ZoneAttributes>{};
  for (final u in poolUuids) {
    try {
      names[u] = await props.getZoneAttributes(ipByUuid[u]!);
    } catch (_) {}
  }

  final a = poolUuids[0], b = poolUuids[1], c = poolUuids[2];
  print('\n🧪 Experiment speakers:');
  print('   A (coord) = ${_label(a)}');
  print('   B         = ${_label(b)}');
  print('   C         = ${_label(c)}  (the add/remove subject)');

  if (!confirm) {
    print('\n✅ DRY RUN — nothing changed. Re-run with --confirm for the live '
        'experiment (self-restoring).');
    return;
  }

  // How many repetitions of each successful op (prove it's not a one-off).
  final rounds = int.tryParse(args['rounds'] ?? '') ?? 6;

  final report = <String>[];
  final reassignAttempts = <int>[]; // one per reassign op
  final addAttempts = <int>[]; // one per add trial
  var reassignFails = 0, addFails = 0;
  final zoneMap = '$a:LF,RF;$b:LF,RF';
  final pairMap = '$a:LF,LF;$b:RF,RF';
  final addMap = '$a:LF,RF;$b:LF,RF;$c:LF,RF';
  try {
    // Free all pool speakers: dissolve every existing zone.
    print('\n🔻 Dissolving existing zones to free speakers…');
    for (final z in zones) {
      await _dissolve(z.coordUuid, z.map);
    }
    await _restoreNames(names); // names come back standalone; belt-and-suspenders

    // Baseline zone A+B.
    report.add((await _reassert('baseline A+B (zone)', a, zoneMap,
            watch: [a, b, c]))
        .line);

    // ---- REASSIGN STRESS: cycle zone↔pair-shape `rounds` times (same members,
    // no dissolve between — a clean cyclic reassignment). ----
    print('\n════ Reassign stress: $rounds cycles (zone↔pair) ════');
    for (var i = 1; i <= rounds; i++) {
      final r1 = await _reassert('cycle $i → pair-shape', a, pairMap, watch: [a, b]);
      final r2 = await _reassert('cycle $i → zone', a, zoneMap, watch: [a, b]);
      for (final r in [r1, r2]) {
        reassignAttempts.add(r.attempts);
        if (!r.ok) reassignFails++;
      }
      report..add(r1.line)..add(r2.line);
    }

    // ---- ADD STRESS: `rounds` independent trials of adding C in place. Reset
    // between trials by dissolving to standalone + rebuilding the A+B baseline. ----
    print('\n════ Add stress: $rounds trials (add C to a live A+B zone) ════');
    for (var i = 1; i <= rounds; i++) {
      // Reset to a clean A+B zone: dissolve whatever's on A, rebuild baseline.
      final live = await _coordMap(a);
      if ((live ?? '').isNotEmpty) await _dissolve(a, live!);
      await _reassert('trial $i reset A+B', a, zoneMap, watch: [a, b]);
      final r = await _reassert('trial $i add C', a, addMap, watch: [a, b, c]);
      addAttempts.add(r.attempts);
      if (!r.ok) addFails++;
      report.add(r.line);
    }

    // ---- REMOVE (single, confirms the one op that does NOT work in place). ----
    print('\n════ Remove (expected to fail in place) ════');
    final rem = await _reassert('remove C in place', a, zoneMap, watch: [a, b, c]);
    report.add(rem.line);
  } catch (e, st) {
    report.add('💥 harness error: $e\n$st');
  } finally {
    // ---- RESTORE: dissolve whatever experimental zone exists on A, then
    // rebuild the ORIGINAL zones exactly, then restore all names. ----
    print('\n🧹 Restoring original state…');
    final liveA = await _coordMap(a);
    if ((liveA ?? '').isNotEmpty) {
      await _dissolve(a, liveA!);
    }
    for (final z in zones) {
      await _rebuild(z.coordUuid, z.map, z.memberUuids);
    }
    await _restoreNames(names);
    print('\n🔬 Final topology:');
    for (final z in await _readZones()) {
      print('   • coord ${_label(z.coordUuid)}  map=${z.map}');
    }
  }

  print('\n================ RESULTS ================');
  for (final r in report) {
    print(r);
  }
  print('\n---------------- SUMMARY ----------------');
  print('reassign (same members): ${reassignAttempts.length - reassignFails}/'
      '${reassignAttempts.length} applied  attempts=$reassignAttempts');
  print('add member (in place):   ${addAttempts.length - addFails}/'
      '${addAttempts.length} applied  attempts=$addAttempts');
  print('remove member (in place): expected to FAIL (must dissolve).');
  print('========================================');
}

/// Re-asserts [map] on [coordUuid] (retrying transient faults) and polls the
/// topology until it matches. Returns whether it applied + attempt/fault counts.
Future<({bool ok, int attempts, int faults, String line})> _reassert(
    String label, String coordUuid, String map,
    {required List<String> watch}) async {
  print('\n→ $label\n   map=$map');
  final ip = ipByUuid[coordUuid]!;
  var faults = 0;
  var tries = 0;
  String? liveMap;
  var settled = false;
  for (tries = 1; tries <= 6 && !settled; tries++) {
    try {
      await props.addBondedZones(ip: ip, channelMapSet: map);
    } catch (e) {
      faults++;
      print('   attempt $tries faulted: ${e.toString().split(',').first}');
    }
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      liveMap = await _coordMap(coordUuid);
      if (liveMap != null && _sameMap(liveMap, map)) {
        settled = true;
        break;
      }
    }
    if (!settled) print('   attempt $tries: map not yet matching ($liveMap)');
  }
  final standings = <String>[];
  for (final u in watch) {
    standings.add('${_shortLabel(u)}=${(await _standing(u)).name}');
  }
  final attempts = tries - 1;
  final verdict = settled ? '✅ applied' : '❌ NOT applied';
  final line = '$verdict  ${label.padRight(36)} attempts=$attempts faults=$faults'
      '  standing: ${standings.join('  ')}';
  print('   $verdict in $attempts attempt(s), $faults fault(s)');
  return (ok: settled, attempts: attempts, faults: faults, line: line);
}

/// Detach the coordinator into its own group, then SeparateStereoPair, polling
/// until the map is gone.
Future<void> _dissolve(String coordUuid, String map) async {
  final ip = ipByUuid[coordUuid];
  if (ip == null) return;
  try {
    await av.becomeCoordinatorOfStandaloneGroup(ip);
  } catch (_) {}
  await Future<void>.delayed(const Duration(seconds: 5));
  try {
    await props.separateBondedZones(ip: ip, channelMapSet: map);
  } catch (_) {}
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(const Duration(seconds: 3));
    if ((await _coordMap(coordUuid) ?? '').isEmpty) return;
  }
  print('   ⚠️  ${_label(coordUuid)} still bonded after dissolve attempt.');
}

/// Rebuild a zone from bare, re-asserting until the coordinator carries [map].
Future<void> _rebuild(String coordUuid, String map, List<String> members) async {
  final ip = ipByUuid[coordUuid];
  if (ip == null) return;
  for (var attempt = 0; attempt < 8; attempt++) {
    if (_sameMap(await _coordMap(coordUuid) ?? '', map)) return;
    try {
      await props.addBondedZones(ip: ip, channelMapSet: map);
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 6));
  }
  final ok = _sameMap(await _coordMap(coordUuid) ?? '', map);
  print(ok
      ? '   ✅ rebuilt ${_label(coordUuid)}'
      : '   ❌ FAILED to rebuild ${_label(coordUuid)} — MANUAL FIX map=$map');
}

Future<void> _restoreNames(Map<String, ZoneAttributes> names) async {
  for (final e in names.entries) {
    final ip = ipByUuid[e.key];
    if (ip == null) continue;
    try {
      if ((await props.getZoneAttributes(ip)).zoneName != e.value.zoneName) {
        await props.setZoneAttributes(ip, e.value);
      }
    } catch (_) {}
  }
}

/// Distinct zones currently in topology, coordinator first (from the map order).
Future<List<({String coordUuid, String map, List<String> memberUuids})>>
    _readZones() async {
  final groups = await topo.getZoneGroups(anyIp);
  final seenMaps = <String>{};
  final out = <({String coordUuid, String map, List<String> memberUuids})>[];
  for (final m in groups.expand((g) => g.members)) {
    final cms = m.channelMapSet;
    if (cms == null || cms.isEmpty || !seenMaps.add(cms)) continue;
    final uuids = cms
        .split(';')
        .where((p) => p.contains(':'))
        .map((p) => p.substring(0, p.indexOf(':')).trim())
        .toList();
    if (uuids.length >= 2) {
      out.add((coordUuid: uuids.first, map: cms, memberUuids: uuids));
    }
  }
  return out;
}

/// The live ChannelMapSet carried by [coordUuid], or null if it carries none.
Future<String?> _coordMap(String coordUuid) async {
  try {
    final m = (await topo.getZoneGroups(anyIp))
        .expand((g) => g.members)
        .where((x) => x.uuid == coordUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    final cms = m?.channelMapSet;
    return (cms ?? '').isEmpty ? null : cms;
  } catch (_) {
    return null;
  }
}

Future<Standing> _standing(String uuid) async {
  try {
    final groups = await topo.getZoneGroups(anyIp);
    final m = groups
        .expand((g) => g.members)
        .where((x) => x.uuid == uuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    if (m == null) return Standing.absent;
    if (m.invisible) return Standing.invisible;
    final isCoord = groups.any((g) => g.coordinatorUuid == uuid);
    return isCoord ? Standing.coordinatorVisible : Standing.memberVisible;
  } catch (_) {
    return Standing.absent;
  }
}

/// Order-insensitive channel-map compare (uuid→sorted tokens).
bool _sameMap(String a, String b) {
  Map<String, String> parse(String s) => {
        for (final p in s.split(';').where((p) => p.contains(':')))
          p.substring(0, p.indexOf(':')).trim(): (p
                  .substring(p.indexOf(':') + 1)
                  .toUpperCase()
                  .split(',')
                ..sort())
              .join(',')
      };
  final pa = parse(a), pb = parse(b);
  if (pa.length != pb.length) return false;
  for (final e in pa.entries) {
    if (pb[e.key] != e.value) return false;
  }
  return true;
}

String _label(String uuid) => '${_shortLabel(uuid)} [$uuid]';
String _shortLabel(String uuid) =>
    uuid.replaceFirst('RINCON_', '').replaceFirst('01400', '');
