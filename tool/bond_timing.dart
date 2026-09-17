// Bonding-cost benchmark: the LEGACY :1400 SOAP path vs the NEWER `zones`
// namespace on :1443, op for op, on real hardware.
//
// Measures both paths for the five group-bonding operations Sonority performs,
// repeatedly, reporting min/median/max wall time plus the number of write
// attempts each needed — the robustness half, which a stopwatch alone hides.
//
// WHAT IT FOUND (medians of 3 rounds, Beam rig, 2026-09-17) — the zones API is
// NOT uniformly faster, which is worth knowing before quoting it as "faster":
//   remove a member  14.4s → 5.0s   (2.9× faster, and 2 SOAP attempts → 1)
//   dissolve          9.8s → 3.9s   (2.5× faster)
//   add a member      5.7s → 8.7s   (SLOWER)
//   channel change    3.4s → 5.5s   (SLOWER)
//   create from bare  3.7s → 5.6s   (SLOWER)
// The two multi-step ops win big; the three that were already one SOAP POST lose
// ~2s to a TLS handshake plus a websocket subscribe. The robustness column is the
// real argument: every zones op converged in ONE attempt with a named error on
// refusal, versus re-asserting against `UPnPError 800`.
//
//   dart run tool/bond_timing.dart                            # dry run (plan only)
//   dart run tool/bond_timing.dart --confirm                  # LIVE, self-restoring
//   dart run tool/bond_timing.dart --confirm --rounds 5
//   dart run tool/bond_timing.dart --confirm --group Eetkamer --spare Gym
//
//   --group <room|uuid>   the speaker group to operate on (default: the first one)
//   --spare <room|uuid>   the standalone speaker moved in and out (default: the first)
//   --rounds N            repetitions per operation per path (default 3)
//
// WHAT IS TIMED: every measurement starts just before the first write and stops
// the moment the authoritative :1400 topology reports the target end state — so
// the number is what a user waits for, including Sonos' settle and any retry
// loop, not the HTTP round-trip. Both paths share one poll cadence (3s, matching
// SonosRepository's own `_groupVerifyInterval`) so the two numbers are
// comparable; that cadence is also the measurement resolution.
//
// SAFETY / SELF-RESTORING: nothing is written without --confirm. Up front the
// tool snapshots the group's exact channel map + member set, every affected
// speaker's ZoneAttributes (room name/icon/config), the household's stored zone
// definition ids, and which definition was active. A `finally` puts all of it
// back even if a round throws: it deactivates any zone it activated, re-activates
// the originally-active definition, rebuilds the original map via SOAP if needed,
// removes every definition it created (the zones namespace does no dedupe), and
// restores names last (activateZone applies a definition's name as the ROOM name,
// and a freed member gets auto-renamed "<Room> 2"). Home theaters and Subs are
// never touched: candidate groups exclude both, and the spare comes from
// `zoneableSpeakers` (no soundbars, subs, amps or line-out boxes).

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/channel_map.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/zone_api.dart';
import 'package:sonority/data/sonos/zone_layout.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

import 'discover_util.dart';

/// One entry of a target bond, in the shape the repository primitives take.
typedef Member = ({SonosDevice device, GroupChannel channel});

/// The two bonding implementations under test. The SOAP path is forced by
/// calling the repository's :1400 primitives directly — the zones-API decision
/// lives in `SonosController`, never in these primitives, so there is nothing to
/// disable.
enum Api {
  soap('SOAP'),
  zones('zones API');

  const Api(this.label);
  final String label;
}

/// The five group edits Sonority performs. Each is measured on both paths.
enum Op {
  add('add a member'),
  remove('remove a member'),
  shape('channel/shape change'),
  dissolve('dissolve'),
  create('create from bare');

  const Op(this.label);
  final String label;
}

// Retry/poll cadence, deliberately the same for both paths (see the header).
const _maxAttempts = 6;
const _pollInterval = Duration(seconds: 3);
const _pollsPerAttempt = 8; // ≤24s per attempt; a clean apply lands in ~2 polls

late final SonosRepository repo;
late final DevicePropertiesClient props;
late final ZoneTopologyClient topo;
late final ZoneApiClient zoneApi;

/// The initial full discovery. Reused as `previous` for every cheap topology
/// refresh so the repository never re-runs SSDP inside a timed window.
late final SonosSystem system;
late final String anyIp; // topology is a system-wide query any player answers

late final String coordUuid;
late final String coordIp;

/// The coordinator's room name at start. Always passed as the zones-API
/// definition name — activating a definition applies its name as the ROOM name,
/// so anything else renames a real room.
late final String coordName;

late final List<Member> base; // the group exactly as found
late final List<Member> plusSpare; // base + the spare speaker
late final List<Member> flipped; // base with every channel reassigned
late final List<Member> pairOnly; // coordinator + one member (the create target)
late final String baseMap;

final stats = <(Op, Api), _Stat>{};

Future<void> main(List<String> argv) async {
  final args = parseArgs(argv, flags: {'confirm'});
  final confirm = args.containsKey('confirm');
  final rounds = int.tryParse(args['rounds'] ?? '') ?? 3;

  print('🔎 Discovering…');
  repo = SonosRepository();
  props = DevicePropertiesClient(SonosSoapClient());
  topo = ZoneTopologyClient(SonosSoapClient());
  zoneApi = const ZoneApiClient();
  system = await repo.discover();
  final ip = system.devicesByUuid.values.map((d) => d.ip).whereType<String>().firstOrNull;
  if (ip == null) {
    print('❌ No reachable Sonos devices.');
    exit(1);
  }
  anyIp = ip;

  // ---- pick the group: never a home theater, never one carrying a Sub ----
  final candidates = system.speakerGroups
      .where((m) => !m.isHomeTheater && m.subUuid == null)
      .toList();
  if (candidates.isEmpty) {
    print('❌ No speaker group to benchmark (home theaters and groups with a Sub '
        'are excluded on purpose). Create a stereo pair or zone first.');
    exit(1);
  }
  final wantGroup = args['group'];
  final group = wantGroup == null
      ? candidates.first
      : candidates
          .where((m) =>
              m.uuid == wantGroup ||
              m.zoneName.toLowerCase() == wantGroup.toLowerCase())
          .firstOrNull;
  if (group == null) {
    print('❌ "$wantGroup" is not one of the benchmarkable groups: '
        '${candidates.map((m) => m.zoneName).join(", ")}');
    exit(1);
  }

  final memberUuids = group.channelMapUuids; // coordinator first
  final channels = group.groupChannels;
  final devices = [for (final u in memberUuids) system.device(u)].whereType<SonosDevice>().toList();
  if (devices.length != memberUuids.length || devices.any((d) => d.ip == null)) {
    print('❌ Could not resolve an IP for every member of "${group.zoneName}" — '
        'discovery flaked. Nothing changed, just retry.');
    exit(1);
  }
  if (devices.length < 2) {
    print('❌ "${group.zoneName}" has fewer than 2 members.');
    exit(1);
  }

  // ---- pick the spare: standalone, not a soundbar/sub/amp/line-out box ----
  final free = system.zoneableSpeakers
      .where((d) => !d.drivesExternalSpeakers && d.ip != null)
      .toList();
  final wantSpare = args['spare'];
  final spare = wantSpare == null
      ? free.firstOrNull
      : free
          .where((d) =>
              d.uuid == wantSpare ||
              d.roomName.toLowerCase() == wantSpare.toLowerCase())
          .firstOrNull;
  if (spare == null) {
    print(wantSpare == null
        ? '❌ No standalone speaker free to move in and out. Free one first.'
        : '❌ "$wantSpare" is not a free, zoneable speaker. Candidates: '
            '${free.map((d) => d.roomName).join(", ")}');
    exit(1);
  }

  coordUuid = devices.first.uuid;
  coordIp = devices.first.ip!;
  base = [for (final d in devices) (device: d, channel: channels[d.uuid]!)];
  plusSpare = [...base, (device: spare, channel: GroupChannel.both)];
  // A real reassignment for every member: a full-range zone becomes alternating
  // L/R (a stereo-pair shape for two members), anything sided becomes full-range.
  flipped = [
    for (var i = 0; i < base.length; i++)
      (
        device: base[i].device,
        channel: base[i].channel == GroupChannel.both
            ? (i.isEven ? GroupChannel.left : GroupChannel.right)
            : GroupChannel.both,
      ),
  ];
  pairOnly = base.take(2).toList();
  baseMap = _map(base);

  // ---- snapshot ----
  // A bonded member's name already reads as the coordinator's absorbed name —
  // that is the best obtainable, and it doesn't matter for the end state we
  // restore (the rebuilt group re-absorbs them anyway). The names that DO
  // matter are the coordinator's and the spare's, and both are genuine here.
  final names = <String, ZoneAttributes>{};
  for (final d in [...devices, spare]) {
    try {
      names[d.uuid] = await props.getZoneAttributes(d.ip!);
    } catch (e) {
      print('⚠️  could not snapshot ${d.roomName}\'s name ($e) — it will not be restored.');
    }
  }
  coordName = names[coordUuid]?.zoneName ?? group.zoneName;

  final defsBefore = <String>{};
  String? activeBefore;
  try {
    defsBefore.addAll(await zoneApi.withSession(
        coordIp, live: true, (s) async => s.definitions.map((d) => d.zoneId)));
    activeBefore = (await zoneApi.activeZones(coordIp))
        ?.where((z) => z.members.firstOrNull?.uuid == coordUuid)
        .firstOrNull
        ?.zoneId;
  } catch (e) {
    print('⚠️  zones API unreadable ($e) — its half of the benchmark will report failures.');
  }

  // ---- plan ----
  print('\n📋 Plan — $rounds round(s), each running all 5 ops on BOTH paths');
  print('   group      ${group.zoneName} (${group.groupKind.name}) coord=${devices.first.typeLabel} @ $coordIp');
  for (final m in base) {
    print('     • ${m.device.roomName.padRight(14)} ${m.device.typeLabel.padRight(14)} '
        '${groupChannelLabel(m.channel)}');
  }
  print('   spare      ${spare.roomName} (${spare.typeLabel})');
  print('   base map   $baseMap');
  print('\n   ${Op.add.label.padRight(22)} $baseMap\n${" " * 29}→ ${_map(plusSpare)}');
  print('     SOAP  reassertGroup (in-place re-assert loop)');
  print('     zones applyBondViaZoneApi (addZoneDefinition + activateZone)');
  print('   ${Op.remove.label.padRight(22)} back to the base map');
  print('     SOAP  detach + separateGroup + createGroup  (AddBondedZones faults on a drop)');
  print('     zones dropGroupMembersViaZoneApi (updateZoneDefinition, in place)');
  print('   ${Op.shape.label.padRight(22)} → ${_map(flipped)}');
  print('     SOAP  reassertGroup      zones applyBondViaZoneApi');
  print('   ${Op.dissolve.label.padRight(22)} → nothing bonded');
  print('     SOAP  detach + separateGroup      zones dissolveBondViaZoneApi (no detach)');
  print('   ${Op.create.label.padRight(22)} → ${_map(pairOnly)}');
  print('     SOAP  createGroup + poll-verify   zones applyBondViaZoneApi');
  print('\n🛡️  Snapshotted for restore:');
  print('   map          $baseMap');
  print('   members      ${memberUuids.join(", ")}');
  print('   room names   ${names.entries.map((e) => "${system.device(e.key)?.roomName}=${e.value.zoneName}").join(", ")}');
  print('   definitions  ${defsBefore.length} stored, active on this coordinator: ${activeBefore ?? "none"}');
  print('   restore      deactivate anything we activated → re-activate $activeBefore → '
      'rebuild the map via SOAP → remove definitions we created → restore names');

  if (!confirm) {
    print('\n✅ DRY RUN — not a single write. Re-run with --confirm.');
    return;
  }

  try {
    for (var r = 1; r <= rounds; r++) {
      for (final api in Api.values) {
        print('\n════════ round $r/$rounds — ${api.label} ════════');
        await _round(api);
      }
    }
  } catch (e, st) {
    print('💥 harness error: $e\n$st');
  } finally {
    await _restore(defsBefore, activeBefore, names);
  }
  _report(rounds);
}

/// All five ops on one path. The base group is (re-)established THROUGH THE PATH
/// UNDER TEST: a bond built by `AddBondedZones` has no active zone definition, so
/// the zones-API remove/dissolve calls would find nothing to edit (CLAUDE.md —
/// the two models can disagree, and a :1400 write does not update this one).
Future<void> _round(Api api) async {
  await _ensureBase(api);

  if (await _measure(Op.add, api, () => _apply(api, plusSpare))) {
    await _measure(Op.remove, api, () => _remove(api, base));
  }
  await _ensureBase(api);

  await _measure(Op.shape, api, () => _apply(api, flipped));
  await _ensureBase(api); // unmeasured shape restore

  final bonded = [for (final m in base) m.device.uuid];
  if (await _measure(Op.dissolve, api, () => _dissolve(api, bonded))) {
    await _measure(Op.create, api, () => _apply(api, pairOnly));
  }
  // The next round's _ensureBase grows this back to the full member set.
}

/// Times one operation, records the sample, and reports. Returns false when the
/// round failed — a failure leaves the live state unknown, so the caller must
/// not chain the follow-up op onto it.
Future<bool> _measure(Op op, Api api, Future<int> Function() run) async {
  print('\n→ ${op.label} via ${api.label}');
  final sw = Stopwatch()..start();
  final s = stats.putIfAbsent((op, api), _Stat.new);
  try {
    final attempts = await run();
    sw.stop();
    s.durations.add(sw.elapsedMilliseconds);
    s.attempts.add(attempts);
    print('   ✅ ${_secs(sw.elapsedMilliseconds)} in $attempts attempt(s)');
    return true;
  } catch (e) {
    sw.stop();
    s.failed++;
    print('   ❌ FAILED after ${_secs(sw.elapsedMilliseconds)}: $e');
    return false;
  }
}

/// Brings the group back to its snapshotted map through [api] — unmeasured
/// setup/recovery, a no-op when the map already matches.
Future<void> _ensureBase(Api api) async {
  if (await _mapIs(baseMap)) return;
  print('   ↺ re-establishing the base group via ${api.label}…');
  try {
    await _apply(api, base);
  } catch (e) {
    // Don't take the whole run down: the next op's own _ensureBase gets another
    // go, and the `finally` restore rebuilds via SOAP regardless.
    print('   ⚠️  could not re-establish the base group via ${api.label}: $e');
  }
}

/// Apply a whole target bond (add / reassign / create) through [api].
Future<int> _apply(Api api, List<Member> target) {
  final map = _map(target);
  return switch (api) {
    Api.soap => _soapApply(target),
    Api.zones => _until(
        () => repo.applyBondViaZoneApi(
              ip: coordIp,
              roomName: coordName,
              targetMap: map,
              onNote: _note,
            ),
        () => _mapIs(map),
      ),
  };
}

/// The :1400 path for any target. `AddBondedZones` adds members and reassigns
/// channels IN PLACE, but faults on every attempt at a map that DROPS a bonded
/// member — so a removal (or a coordinator change) is forced through the whole
/// dissolve-and-rebuild detour, which is exactly what makes it expensive.
/// [groupEditIsInPlace] is the engine's own test for which of the two applies.
Future<int> _soapApply(List<Member> target) async {
  final map = _map(target);
  final current = await _liveMembers();
  final targetUuids = [for (final t in target) t.device.uuid];
  if (groupEditIsInPlace(
      currentUuids: current,
      targetUuids: targetUuids,
      targetCoordUuid: targetUuids.first)) {
    // reassertGroup runs its own write+verify loop, so its attempt count comes
    // from the per-attempt notes rather than from _until.
    final notes = <String>[];
    await repo.reassertGroup(
      members: target,
      currentUuids: current,
      previous: system,
      onNote: (n) {
        notes.add(n);
        _note(n);
      },
    );
    return _attemptsFrom(notes);
  }
  var attempts = 0;
  if (current.isNotEmpty) attempts += await _soapDissolve(current);
  return attempts +
      await _until(() => repo.createGroup(members: target), () => _mapIs(map));
}

/// Remove a member. The zones API does this in place with one
/// `updateZoneDefinition` — the one call `AddBondedZones` has no answer for.
Future<int> _remove(Api api, List<Member> target) {
  final map = _map(target);
  return switch (api) {
    Api.soap => _soapApply(target), // routes itself through dissolve + rebuild
    Api.zones => _until(
        () => _zones(() => repo.dropGroupMembersViaZoneApi(
              ip: coordIp,
              coordinatorUuid: coordUuid,
              targetMap: map,
              onNote: _note,
            )),
        () => _mapIs(map),
      ),
  };
}

Future<int> _dissolve(Api api, List<String> bonded) => switch (api) {
      Api.soap => _soapDissolve(bonded),
      Api.zones => _until(
          () => repo.dissolveBondViaZoneApi(
                ip: coordIp,
                coordinatorUuid: coordUuid,
                onNote: _note,
              ),
          () => _isDissolved(bonded),
        ),
    };

/// The :1400 dissolve: `SeparateStereoPair` no-ops while the coordinator is a
/// non-coordinator member of a larger playback group, so it must be detached
/// first — a step `deactivateZone` doesn't need, and part of the cost being
/// measured. The LIVE map is read because a custom map won't round-trip through
/// a recipe; the zones path pays a comparable `activeZones` read inside
/// `dissolveBondViaZoneApi`.
Future<int> _soapDissolve(List<String> bonded) async {
  final live = await _liveMap();
  if (live == null) return 0;
  final members = [for (final e in ChannelMap.parse(live).entries) system.device(e.uuid)]
      .whereType<SonosDevice>()
      .toList();
  await repo.detachFromGroup(coordIp);
  await Future<void>.delayed(const Duration(seconds: 4));
  return _until(
    () => repo.separateGroup(members: members, channelMapSet: live),
    () => _isDissolved(bonded),
  );
}

/// Write, then poll the authoritative :1400 topology until [verify] passes,
/// re-writing up to [_maxAttempts] times. Returns the attempts it took; throws
/// if it never verifies.
///
/// Both paths go through this one loop so their numbers are comparable, and both
/// follow the same hardware-established rule: a failed write is "go verify",
/// never a verdict — a timed-out `AddBondedZones` or `activateZone` very often
/// applied anyway.
Future<int> _until(
    Future<void> Function() write, Future<bool> Function() verify) async {
  for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
    try {
      await write();
    } on _Declined catch (e) {
      // A named refusal from the zones namespace is authoritative: it changed
      // nothing and will refuse again, so retrying only burns minutes.
      throw StateError('zones API declined: ${e.why}');
    } catch (e) {
      print('      attempt $attempt write error, verifying anyway: $e');
    }
    for (var p = 0; p < _pollsPerAttempt; p++) {
      await Future<void>.delayed(_pollInterval);
      if (await verify()) return attempt;
    }
    print('      attempt $attempt: not settled yet');
  }
  throw StateError('never verified after $_maxAttempts attempt(s)');
}

/// `dropGroupMembersViaZoneApi` is the one entry point that answers with a bool
/// rather than throwing: false means "no live zone definition to mutate", so the
/// app would activate the target layout instead (still the zones path — there is
/// no SOAP fallback). For a benchmark that is a declined round, since the point is
/// to time THAT primitive.
Future<void> _zones(Future<bool> Function() call) async {
  if (!await call()) throw const _Declined('no live zone to update in place');
}

class _Declined implements Exception {
  final String why;
  const _Declined(this.why);
}

void _note(String n) => print('      $n');

/// Highest attempt number mentioned by a repository primitive's notes
/// ("attempt 3: …", "re-asserted after 4 tries"); 1 when it converged silently.
int _attemptsFrom(List<String> notes) {
  var max = 1;
  for (final n in notes) {
    for (final m in RegExp(r'attempt (\d+)|after (\d+) tries').allMatches(n)) {
      final v = int.parse(m.group(1) ?? m.group(2)!);
      if (v > max) max = v;
    }
  }
  return max;
}

/// The live `ChannelMapSet` carried by the coordinator, or null if it carries
/// none. Read from the authoritative attribute, not the transient `<Satellite>`
/// list — topology lies for ~15s after any bonding change.
Future<String?> _liveMap() async {
  try {
    final m = (await topo.getZoneGroups(anyIp))
        .expand((g) => g.members)
        .where((x) => x.uuid == coordUuid)
        .firstOrNull;
    final cms = m?.channelMapSet;
    return (cms ?? '').isEmpty ? null : cms;
  } catch (_) {
    return null; // a failed read is "not settled yet", not a verdict
  }
}

Future<List<String>> _liveMembers() async {
  final live = await _liveMap();
  return live == null
      ? const []
      : [for (final e in ChannelMap.parse(live).entries) e.uuid];
}

Future<bool> _mapIs(String want) async =>
    sameChannelMap(await _liveMap() ?? '', want);

/// Dissolved = the coordinator carries no map AND every former member is a
/// visible room again. The second half matters: the map attribute clears well
/// before the freed speakers re-appear as rooms, and the room is what a user
/// waits for.
Future<bool> _isDissolved(List<String> bonded) async {
  if (await _liveMap() != null) return false;
  try {
    final members = (await topo.getZoneGroups(anyIp)).expand((g) => g.members).toList();
    return bonded.every((u) => members.any((m) => m.uuid == u && !m.invisible));
  } catch (_) {
    return false;
  }
}

String _map(List<Member> members) => buildGroupMap(
    [for (final m in members) (uuid: m.device.uuid, channel: m.channel)]);

/// Puts everything back, in the only order that works: the definitions we
/// activated must go inactive before the original can be re-activated (a live
/// definition over the same coordinator makes `activateZone` refuse with
/// "new primary activation failed"), and a definition can't be removed while
/// active. Names go last because `activateZone` applies a definition's name as
/// the room name.
Future<void> _restore(
    Set<String> defsBefore, String? activeBefore, Map<String, ZoneAttributes> names) async {
  print('\n🧹 Restoring…');

  // 1. Deactivate any zone now live on our coordinator that wasn't there before.
  try {
    final live = (await zoneApi.activeZones(coordIp))
        ?.where((z) => z.members.firstOrNull?.uuid == coordUuid)
        .firstOrNull;
    if (live != null && live.zoneId != activeBefore) {
      await zoneApi.withSession(
          coordIp, live: true, (s) => s.deactivate(live.zoneId));
      print('   ▫️ deactivated ${live.zoneId} (created by this run)');
      await Future<void>.delayed(const Duration(seconds: 10));
    }
  } catch (e) {
    print('   ⚠️  could not deactivate our zone: $e');
  }

  // 2. Re-activate whatever was active at start, so the zones-side bookkeeping
  //    matches what we found (and rebuilds the bond in one call when it can).
  if (activeBefore != null) {
    try {
      await zoneApi.withSession(
          coordIp, live: true, (s) => s.activate(activeBefore));
      print('   ▫️ re-activated the original definition $activeBefore');
      await Future<void>.delayed(const Duration(seconds: 16));
    } catch (e) {
      print('   ⚠️  could not re-activate $activeBefore ($e) — falling back to SOAP.');
    }
  }

  // 3. The bond itself, via SOAP — covers "there was no definition" and
  //    "activation refused". This is the one step that must not be skipped.
  try {
    if (!await _mapIs(baseMap)) await _soapApply(base);
    print(await _mapIs(baseMap)
        ? '   ✅ original group restored'
        : '   ❌ group NOT restored — MANUAL FIX: AddBondedZones on $coordIp map=$baseMap');
  } catch (e) {
    print('   ❌ group NOT restored ($e) — MANUAL FIX: AddBondedZones on $coordIp map=$baseMap');
  }

  // 4. Remove every definition this run created. Identified by set difference
  //    against the snapshot, because the namespace does no dedupe and nothing
  //    else prunes the household's library.
  try {
    final extra = (await zoneApi.withSession(
            coordIp, live: true, (s) async => s.definitions))
        .where((d) => !defsBefore.contains(d.zoneId))
        .toList();
    for (final d in extra) {
      try {
        await zoneApi.withSession(
            coordIp, live: true, (s) => s.removeDefinition(d.zoneId));
        print('   ▫️ removed the definition we created: ${d.zoneId} "${d.name}"');
      } catch (e) {
        print('   ⚠️  could not remove ${d.zoneId} "${d.name}" ($e) — '
            'dart run tool/zone_api_probe.dart --remove ${d.zoneId} --confirm');
      }
    }
    if (extra.isEmpty) print('   ▫️ no leftover definitions');
  } catch (e) {
    print('   ⚠️  could not list definitions to clean up: $e');
  }

  // 5. Names last.
  for (final e in names.entries) {
    final ip = system.device(e.key)?.ip;
    if (ip == null) continue;
    try {
      if ((await props.getZoneAttributes(ip)).zoneName != e.value.zoneName) {
        await props.setZoneAttributes(ip, e.value);
        print('   ▫️ restored the name "${e.value.zoneName}"');
      }
    } catch (err) {
      print('   ⚠️  could not restore "${e.value.zoneName}" ($err)');
    }
  }
}

class _Stat {
  final durations = <int>[]; // ms, successful rounds only
  final attempts = <int>[];
  var failed = 0;
}

void _report(int rounds) {
  print('\n================ RESULTS ================');
  for (final op in Op.values) {
    print('\n${op.label}');
    for (final api in Api.values) {
      final s = stats[(op, api)];
      if (s == null || s.durations.isEmpty) {
        print('   ${api.label.padRight(10)} no successful round'
            '${s == null ? "" : " (${s.failed} failed)"}');
        continue;
      }
      final d = [...s.durations]..sort();
      print('   ${api.label.padRight(10)} min ${_secs(d.first)}  '
          'median ${_secs(_median(s.durations).round())}  max ${_secs(d.last)}  '
          'attempts ${s.attempts}  failed ${s.failed}');
    }
  }

  print('\n---- paste into the PR ----\n');
  print('Bonding cost, SOAP (:1400) vs `zones` API (:1443) — median of $rounds round(s):\n');
  print('| operation | SOAP median | zones median | speedup | SOAP attempts | zones attempts |');
  print('|---|---|---|---|---|---|');
  final failures = <String>[];
  for (final op in Op.values) {
    final soap = stats[(op, Api.soap)];
    final zones = stats[(op, Api.zones)];
    final sMed = _median(soap?.durations ?? const []);
    final zMed = _median(zones?.durations ?? const []);
    final speedup = sMed.isNaN || zMed.isNaN || zMed == 0
        ? '—'
        : '${(sMed / zMed).toStringAsFixed(1)}×';
    print('| ${op.label} | ${_cell(sMed)} | ${_cell(zMed)} | $speedup | '
        '${_attemptCell(soap)} | ${_attemptCell(zones)} |');
    for (final e in {Api.soap: soap, Api.zones: zones}.entries) {
      final f = e.value?.failed ?? 0;
      if (f > 0) failures.add('${op.label} via ${e.key.label}: $f/$rounds failed');
    }
  }
  print(failures.isEmpty
      ? '\nNo round failed outright.'
      : '\nRounds that failed outright: ${failures.join("; ")}.');
  print('\nTimed from just before the first write to the moment :1400 topology '
      'reports the end state, polled every ${_pollInterval.inSeconds}s on both paths.');
}

String _cell(double ms) => ms.isNaN ? 'n/a' : _secs(ms.round());

String _attemptCell(_Stat? s) => s == null || s.attempts.isEmpty
    ? 'n/a'
    : '${_median(s.attempts).toStringAsFixed(1)} (${s.attempts.reduce((a, b) => a < b ? a : b)}–'
        '${s.attempts.reduce((a, b) => a > b ? a : b)})';

double _median(List<int> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid].toDouble() : (s[mid - 1] + s[mid]) / 2;
}

String _secs(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';
