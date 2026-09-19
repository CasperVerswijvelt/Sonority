// Hardware check: can the newer :1443 `zones` API reconfigure a HOME THEATER?
//
//   dart run tool/ht_zone_check.dart            # read-only plan
//   dart run tool/ht_zone_check.dart --confirm  # run it (self-restoring)
//
// ANSWER, measured on the Beam rig (fw 96.1-78270): NO. This tool exists to
// reproduce that, because it is the reason `SonosController._applyHtTarget` is
// the one bonding path still on :1400 SOAP while every speaker-group path went
// over to the zones API. What it recorded:
//
//   ① `activateZone` of a definition that DROPS a satellite reported success and
//      changed `HTSatChanMapSet` not at all — the dropped Sub stayed bonded and
//      ended up held by a SECOND active zone, so the two models straddled.
//   ② Activating any other definition over that was then refused outright
//      (`activateZone failed`), including the one that had been active before,
//      and it did not clear on retry.
//   ③ Only `deactivateZone` moved it — and that is a teardown, not a reconfigure:
//      it freed the fronts to standalone and Sonos auto-renamed them "<Room> 2".
//
// A home theater built by `AddHTSatellite` and a zone definition are parallel
// records of the same bond, and only the SOAP call mutates the one that decides
// the audio. A speaker GROUP is different — its bond IS the definition.
//
// SAFETY: dry-run by default. With --confirm it writes to a live home theater
// and restores in a `finally`: deactivate what it activated → re-activate the
// originally-active definition → re-assert the original map over SOAP (the
// legacy path, which is what created the straddle) → restore every room name →
// remove the definitions it created. Every restore step is independently
// guarded, because step ② above means an activation CAN refuse mid-restore.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/channel_map.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/zone_api.dart';

void note(String s) => print('      $s');

/// Runs a restore step without letting its failure abandon the ones after it.
Future<void> step(String label, Future<void> Function() body) async {
  try {
    await body();
    print('   ▫️ $label');
  } catch (e) {
    print('   ⚠️ $label FAILED: $e');
  }
}

Future<void> main(List<String> argv) async {
  final confirm = argv.contains('--confirm');
  final repo = SonosRepository();
  final props = DevicePropertiesClient(SonosSoapClient());
  const zoneApi = ZoneApiClient();

  print('🔎 Discovering…');
  var system = await repo.discover();
  final ht = system.allMembers.where((m) => m.isHomeTheater).firstOrNull;
  if (ht == null) {
    print('❌ No home theater found.');
    exit(1);
  }
  final bar = system.device(ht.uuid)!;
  final ip = bar.ip!;
  final originalMap = ht.htSatChanMapSet ?? ht.channelMapSet!;
  final full = ChannelMap.parse(originalMap);
  // `subUuid` reads the group ChannelMapSet; an HT's Sub lives in the HT map.
  final subUuid = ht.subUuids.firstOrNull;
  if (subUuid == null) {
    print('❌ This home theater has no Sub to drop; nothing to prove.');
    exit(1);
  }
  // Dropping the Sub is a genuine LEAVE — the case AddHTSatellite faults on and
  // the reason `_applyHtTarget` needs a removal step at all.
  final dropped = full.withoutUuid(subUuid).encode();
  // Every box in the HT map, coordinator first — `channelMapUuids` reads the
  // GROUP ChannelMapSet, which a home theater doesn't carry.
  final involved = full.entries.map((e) => e.uuid).toList();
  final names = <String, ZoneAttributes>{
    for (final u in involved)
      if (system.device(u)?.ip != null)
        u: await props.getZoneAttributes(system.device(u)!.ip!),
  };

  print('\n🎬 ${ht.zoneName} @ $ip');
  print('   original  $originalMap');
  print('   target    $dropped   (drops the Sub $subUuid)');
  final activeBefore = (await zoneApi.activeZones(ip))!
      .where((z) => z.members.firstOrNull?.uuid == ht.uuid)
      .firstOrNull;
  print('   active    ${activeBefore?.zoneId ?? "(none)"}');
  final defsBefore =
      await zoneApi.withSession(ip, live: true, (s) async => s.definitions);
  print('   library   ${defsBefore.length} definitions');
  final nameList = names.values.map((a) => a.zoneName).join(', ');
  print('   names     $nameList');
  if (!confirm) {
    print('\nDry run. Re-run with --confirm to write.');
    return;
  }

  bool hasChannels(SonosSystem s, String map) {
    final m = s.memberByUuid(ht.uuid);
    if (m == null) return false;
    return ChannelMap.parse(map)
        .entries
        .skip(1)
        .every((e) => e.channels.every((ch) => m.uuidsForChannel(ch).contains(e.uuid)));
  }

  Future<SonosSystem> settle(
      String label, bool Function(SonosSystem) until) async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        system = await repo.refresh(system, ip);
      } catch (_) {
        continue;
      }
      if (until(system)) {
        print('   ✅ $label after ${(i + 1) * 3}s');
        return system;
      }
    }
    print('   ❌ $label NEVER settled');
    return system;
  }

  try {
    // ---- ① the claim: activate a map that DROPS a bonded satellite ---------
    print('\n① activateZone with the Sub dropped');
    await repo.applyBondViaZoneApi(
        ip: ip, roomName: ht.zoneName, targetMap: dropped, onNote: note);
    await settle(
      'Sub is out of the bond',
      (s) =>
          hasChannels(s, dropped) &&
          !(s.memberByUuid(ht.uuid)?.subUuids.contains(subUuid) ?? true),
    );
    print('   :1400 map  ${system.memberByUuid(ht.uuid)?.htSatChanMapSet}');
    print('   zones say  ${(await zoneApi.activeZones(ip))!.length} active zones');

    // ---- ② the other direction: activate the full map again ----------------
    print('\n② activateZone with the Sub back in');
    try {
      await repo.applyBondViaZoneApi(
          ip: ip, roomName: ht.zoneName, targetMap: originalMap, onNote: note);
      await settle('full layout restored', (s) => hasChannels(s, originalMap));
    } catch (e) {
      print('   ❌ refused: $e');
    }
    print('   :1400 map  ${system.memberByUuid(ht.uuid)?.htSatChanMapSet}');
  } finally {
    print('\n🧹 Restoring…');
    // Anything we activated has to go before the original can come back — an
    // activation over a live definition is refused, which is finding ② itself.
    final defsNow =
        await zoneApi.withSession(ip, live: true, (s) async => s.definitions);
    final known = {for (final d in defsBefore) d.zoneId};
    final created = defsNow.where((d) => !known.contains(d.zoneId)).toList();
    final live = await zoneApi.activeZones(ip) ?? const [];
    for (final d in created.where((d) => live.any((z) => z.zoneId == d.zoneId))) {
      await step('deactivated ${d.zoneId} (created by this run)',
          () => zoneApi.withSession(
              ip, live: true, (s) async => s.deactivate(d.zoneId)));
      await Future<void>.delayed(const Duration(seconds: 16));
    }
    if (activeBefore != null) {
      await step('re-activated ${activeBefore.zoneId}',
          () => zoneApi.withSession(
              ip, live: true, (s) async => s.activate(activeBefore.zoneId)));
      await Future<void>.delayed(const Duration(seconds: 16));
    }
    // The fronts were never part of that definition (the straddle) — the legacy
    // SOAP path is what put them there, so it is what puts them back.
    await step('re-asserted the original map', () async {
      system = await repo.bondAndVerify(
        coordinator: bar,
        target: ChannelMap.parse(originalMap),
        previous: system,
        onNote: note,
      );
    });
    print('   :1400 map  ${system.memberByUuid(ht.uuid)?.htSatChanMapSet}');
    for (final e in names.entries) {
      final dip = system.device(e.key)?.ip;
      if (dip == null) continue;
      final want = e.value;
      final cur = await retryUnreachable(() => props.getZoneAttributes(dip));
      if (cur.zoneName == want.zoneName) continue;
      await step('renamed ${e.key} "${cur.zoneName}" → "${want.zoneName}"',
          () => retryUnreachable(() => props.setZoneAttributes(dip, want)));
    }
    for (final d in created) {
      await step('removed the definition we created: ${d.zoneId} "${d.name}"',
          () => zoneApi.withSession(
              ip, live: true, (s) async => s.removeDefinition(d.zoneId)));
    }
    final left =
        await zoneApi.withSession(ip, live: true, (s) async => s.definitions);
    print('   library   ${left.length} definitions (was ${defsBefore.length})');
  }
}
