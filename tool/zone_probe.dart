// Sonos "zone" (multi-speaker bond) probe — confirms the wire format of the
// 2025 zones feature against real hardware.
//
//   dart run tool/zone_probe.dart                                   # SCPD + existing zones (read-only)
//   dart run tool/zone_probe.dart --members <a>,<b>,<c>             # dry run (plan only)
//   dart run tool/zone_probe.dart --members <a>,<b>,<c> --confirm   # LIVE round-trip
//   dart run tool/zone_probe.dart --separate [--names UUID=Name,…]  # dissolve the live zone
//
// Each member is a room name, RINCON_ uuid, or IP. The first member is the
// coordinator (stays visible). Create is AddBondedZones; REMOVAL is detach
// (BecomeCoordinatorOfStandaloneGroup) then SeparateStereoPair — RemoveBondedZones
// returns 200 OK but silently no-ops on the 2025 zones feature (confirmed here).
//
// The captured ChannelMapSet (UUID:LF,RF;…) is the ground truth for buildGroupMap
// + the isZone/isStereoPair detection; trust what topology echoes back.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/av_transport.dart';
import 'package:sonority/data/sonos/channel_map.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/zone_topology.dart';
import 'package:xml/xml.dart';

import 'discover_util.dart';

Future<void> main(List<String> argv) async {
  final args = parseArgs(argv, flags: {'confirm', 'separate', 'sidetest', 'explore', 'no-rebond'});
  final membersArg = args['members'];
  final confirm = args.containsKey('confirm');

  print('🔎 Discovering…');
  final devices = await discoverDevices();
  if (devices.isEmpty) {
    print('❌ No Sonos devices found.');
    exit(1);
  }
  final anyIp = devices.first.ip!;

  // 1) Confirm the bonding actions exist on this hardware.
  await _dumpZoneActions(anyIp);

  // 2) Dump any zone-shaped member already in topology (ChannelMapSet with >2
  //    entries or full-range members).
  final topo = ZoneTopologyClient(SonosSoapClient());
  await _dumpExistingZones(topo, anyIp);

  // --sidetest: probe a NON-standard config the official app can't make — two
  // speakers as the LEFT channel and two as the RIGHT (4-speaker stereo, 2/side):
  //   L1:LF,LF;L2:LF,LF;R1:RF,RF;R2:RF,RF
  // Tries AddBondedZones then CreateStereoPair, reports whether Sonos accepts /
  // rejects / 200-OK-no-ops, then cleans up (detach → SeparateStereoPair) and
  // restores names. Usage: --sidetest --members L1,L2,R1,R2
  if (args.containsKey('sidetest')) {
    final props = DevicePropertiesClient(SonosSoapClient());
    final av = AvTransportClient(SonosSoapClient());
    final soap = SonosSoapClient();
    final sel = (membersArg ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sel.length != 4) {
      print('Usage: --sidetest --members L1,L2,R1,R2');
      exit(64);
    }
    final m = sel.map((s) => resolveDevice(devices, s)).toList();
    final coord = m.first;
    final map =
        '${m[0].uuid}:LF,LF;${m[1].uuid}:LF,LF;${m[2].uuid}:RF,RF;${m[3].uuid}:RF,RF';
    final names = {for (final d in m) d.uuid: await props.getZoneAttributes(d.ip!)};
    print('\n🧪 2L+2R map: $map');
    print('   left = ${m[0].roomName}, ${m[1].roomName} · right = ${m[2].roomName}, ${m[3].roomName}');

    Future<({bool bonded, String? cms, int hidden})> readState() async {
      final all = (await topo.getZoneGroups(anyIp)).expand((g) => g.members).toList();
      final cms = all
          .where((x) => x.uuid == coord.uuid)
          .cast<ZoneGroupMember?>()
          .firstOrNull
          ?.channelMapSet;
      final hidden = m
          .skip(1)
          .where((d) => !all.any((x) => x.uuid == d.uuid && !x.invisible))
          .length;
      return (bonded: (cms ?? '').isNotEmpty, cms: cms, hidden: hidden);
    }

    Future<bool> tryAction(String label, Future<void> Function() call) async {
      print('\n→ $label');
      try {
        await call();
        print('   call returned 200 OK');
      } catch (e) {
        print('   ❌ threw: $e');
        return false;
      }
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final st = await readState();
        print('   [${(i + 1) * 3}s] bonded=${st.bonded} hidden=${st.hidden}/3 cms=${st.cms}');
        if (st.bonded && st.hidden == 3) return true;
      }
      return false;
    }

    var formed = await tryAction('AddBondedZones(2L+2R)',
        () => props.addBondedZones(ip: coord.ip!, channelMapSet: map));
    if (!formed) {
      formed = await tryAction(
          'CreateStereoPair(2L+2R)',
          () => soap.call(
              ip: coord.ip!,
              controlPath: '/DeviceProperties/Control',
              serviceType: 'urn:schemas-upnp-org:service:DeviceProperties:1',
              action: 'CreateStereoPair',
              args: {'ChannelMapSet': map}));
    }

    // Clean up whatever bonded (use the LIVE map so it matches exactly).
    final live = (await readState()).cms;
    if ((live ?? '').isNotEmpty) {
      print('\n🧹 Cleanup: detach → SeparateStereoPair');
      await av.becomeCoordinatorOfStandaloneGroup(coord.ip!);
      await Future<void>.delayed(const Duration(seconds: 6));
      await props.separateBondedZones(ip: coord.ip!, channelMapSet: live!);
      await Future<void>.delayed(const Duration(seconds: 6));
    }
    for (final d in m) {
      final want = names[d.uuid]!;
      if ((await props.getZoneAttributes(d.ip!)).zoneName != want.zoneName) {
        await props.setZoneAttributes(d.ip!, want);
        print('   restored ${d.uuid} -> ${want.zoneName}');
      }
    }
    final fin = await readState();
    print(formed
        ? '\n✅ 2L+2R was ACCEPTED by Sonos — novel config! (cleaned up; bondedNow=${fin.bonded})'
        : '\n❌ 2L+2R NOT formed (rejected or silent no-op). bondedNow=${fin.bonded}');
    return;
  }

  // --explore: run a battery of L/R channel configurations (symmetric,
  // asymmetric, degenerate) over a pool of speakers, reporting which Sonos
  // accepts and the resulting topology shape. The first two --members are
  // unbonded from --bar (the HT soundbar) first so the One SLs can be used, then
  // re-bonded as LF/RF fronts at the end (restored in a finally). API/topology
  // only — does NOT verify audio. ⚠️ wipes the HT's Trueplay tuning.
  //   --explore --bar <barUuid> --members SL1,SL2,s3,s4,s5,s6
  if (args.containsKey('explore')) {
    final props = DevicePropertiesClient(SonosSoapClient());
    final av = AvTransportClient(SonosSoapClient());
    final barSel = args['bar'];
    final pool = (membersArg ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => resolveDevice(devices, s))
        .toList();
    if (pool.length < 2) {
      print('Usage: --explore [--bar <barUuid>] --members s1,s2,…  '
          '(with --bar, the first two members are borrowed from the HT)');
      exit(64);
    }
    // With --bar, borrow the first two members from the HT (unbond → use →
    // rebond). Without it, the pool is assumed already-standalone and the HT is
    // never touched.
    final bar = barSel == null ? null : resolveDevice(devices, barSel);

    Future<({String? cms, bool allHidden})> readCoord(List<SonosDevice> mem) async {
      final all = (await topo.getZoneGroups(anyIp)).expand((g) => g.members).toList();
      final cms = all
          .where((x) => x.uuid == mem.first.uuid)
          .cast<ZoneGroupMember?>()
          .firstOrNull
          ?.channelMapSet;
      final hidden = mem
          .skip(1)
          .where((d) => !all.any((x) => x.uuid == d.uuid && !x.invisible))
          .length;
      return (cms: cms, allHidden: hidden == mem.length - 1);
    }

    String classify(String? cms) {
      if (cms == null || cms.isEmpty) {
        return 'none';
      }
      final toks = cms
          .split(';')
          .where((p) => p.contains(':'))
          .map((p) => p.substring(p.indexOf(':') + 1).toUpperCase())
          .toList();
      bool full(String t) => t.contains('LF') && t.contains('RF');
      bool lOnly(String t) => t.contains('LF') && !t.contains('RF');
      bool rOnly(String t) => t.contains('RF') && !t.contains('LF');
      if (toks.length == 2 &&
          ((lOnly(toks[0]) && rOnly(toks[1])) ||
              (rOnly(toks[0]) && lOnly(toks[1])))) {
        return 'stereoPair';
      }
      if (toks.length >= 2 && toks.every(full)) {
        return 'zone';
      }
      return 'other(${toks.length})';
    }

    final results = <String>[];
    final snap = <String, ZoneAttributes>{};
    var originalBarMap = '';

    Future<void> restoreNames(List<SonosDevice> mem) async {
      for (final d in mem) {
        final want = snap[d.uuid];
        if (want == null) {
          continue;
        }
        try {
          if ((await props.getZoneAttributes(d.ip!)).zoneName != want.zoneName) {
            await props.setZoneAttributes(d.ip!, want);
          }
        } catch (_) {}
      }
    }

    Future<void> runConfig(String name, List<String> specs) async {
      if (specs.length > pool.length) {
        results.add('SKIP   $name (needs ${specs.length})');
        return;
      }
      final mem = pool.take(specs.length).toList();
      final map = [
        for (var i = 0; i < specs.length; i++) '${mem[i].uuid}:${specs[i]}'
      ].join(';');
      String? cms;
      var accepted = false;
      var note = '';
      // Bonding is eventually-consistent and intermittently faults (8s timeout /
      // transient SOAP error) yet may still apply — re-assert up to twice and
      // verify from topology, regardless of whether the call threw.
      for (var attempt = 0; attempt < 2 && !accepted; attempt++) {
        try {
          await props.addBondedZones(ip: mem.first.ip!, channelMapSet: map);
        } catch (e) {
          note = ' (faulted:${e.toString().split(',').first.replaceAll('SonosSoapException(', ' ')})';
        }
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(seconds: 3));
          final st = await readCoord(mem);
          cms = st.cms;
          if ((cms ?? '').isNotEmpty && st.allHidden) {
            accepted = true;
            break;
          }
        }
      }
      results.add(
          '${accepted ? "✅" : "❌"} ${name.padRight(26)} → ${accepted ? classify(cms) : "not formed$note"}'
          '${accepted ? "  cms=$cms" : ""}');
      // cleanup whatever bonded
      final live = (await readCoord(mem)).cms;
      if ((live ?? '').isNotEmpty) {
        try {
          await av.becomeCoordinatorOfStandaloneGroup(mem.first.ip!);
          await Future<void>.delayed(const Duration(seconds: 5));
          await props.separateBondedZones(ip: mem.first.ip!, channelMapSet: live!);
          await Future<void>.delayed(const Duration(seconds: 5));
        } catch (_) {}
      }
      await restoreNames(mem);
    }

    try {
      // With --bar: unbond whichever pool speakers are currently HT satellites of
      // the bar, so we can use them. Inside the try so the finally restores.
      if (bar != null) {
        final barMember = (await topo.getZoneGroups(anyIp))
            .expand((g) => g.members)
            .where((x) => x.uuid == bar.uuid)
            .cast<ZoneGroupMember?>()
            .firstOrNull;
        originalBarMap = barMember?.htSatChanMapSet ?? '';
        final sats = barMember?.channelAssignments.values.toSet() ?? <String>{};
        final toUnbond = pool.where((d) => sats.contains(d.uuid)).toList();
        print('\n🔻 Unbonding ${toUnbond.map((d) => d.roomName).join(", ")} from ${bar.roomName}…');
        print('   (original HT map: $originalBarMap)');
        for (final d in toUnbond) {
          await props.removeHtSatellite(soundbarIp: bar.ip!, satelliteUuid: d.uuid);
        }
        // Long settle: just-unbonded speakers are briefly unreachable/flaky.
        await Future<void>.delayed(const Duration(seconds: 30));
      }
      for (final d in pool) {
        try {
          snap[d.uuid] = await props.getZoneAttributes(d.ip!);
        } catch (_) {}
      }

      // pool order = [SL1, SL2, s3, s4, s5, s6] so One SLs lead every config.
      // Per-config try/catch so one failure doesn't abort the battery.
      final battery = <(String, List<String>)>[
        ('pair (L|R)', ['LF,LF', 'RF,RF']),
        ('all-left degenerate', ['LF,LF', 'LF,LF']),
        ('2L+1R (asym)', ['LF,LF', 'LF,LF', 'RF,RF']),
        ('1L+2R (asym)', ['LF,LF', 'RF,RF', 'RF,RF']),
        ('3 full-range zone', ['LF,RF', 'LF,RF', 'LF,RF']),
        ('zone(2)+extra-left', ['LF,RF', 'LF,RF', 'LF,LF']),
        ('fullrange+L+R (mixed)', ['LF,RF', 'LF,LF', 'RF,RF']),
        ('2L+2R', ['LF,LF', 'LF,LF', 'RF,RF', 'RF,RF']),
        ('3L+1R (asym)', ['LF,LF', 'LF,LF', 'LF,LF', 'RF,RF']),
        ('3L+2R', ['LF,LF', 'LF,LF', 'LF,LF', 'RF,RF', 'RF,RF']),
        ('5 full-range zone', ['LF,RF', 'LF,RF', 'LF,RF', 'LF,RF', 'LF,RF']),
        ('3L+3R', ['LF,LF', 'LF,LF', 'LF,LF', 'RF,RF', 'RF,RF', 'RF,RF']),
        // ---- limit-pushers (need 7-8 speakers) ----
        ('6L+2R (skewed)',
            ['LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'RF,RF', 'RF,RF']),
        ('7L+1R (extreme asym)',
            ['LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'RF,RF']),
        ('4L+4R',
            ['LF,LF', 'LF,LF', 'LF,LF', 'LF,LF', 'RF,RF', 'RF,RF', 'RF,RF', 'RF,RF']),
        ('8 full-range zone (max-ish)',
            ['LF,RF', 'LF,RF', 'LF,RF', 'LF,RF', 'LF,RF', 'LF,RF', 'LF,RF', 'LF,RF']),
        // ---- HT-channel tokens on plain speakers (no soundbar) ----
        ('center + L + R (CC token)', ['CC', 'LF,LF', 'RF,RF']),
        ('phantom 5.0 no-bar (CC/LF/RF/LR/RR)',
            ['CC', 'LF', 'RF', 'LR', 'RR']),
        ('zone + discrete rears', ['LF,RF', 'LF,RF', 'LR', 'RR']),
      ];
      for (final (name, specs) in battery) {
        try {
          await runConfig(name, specs);
        } catch (e) {
          results.add('💥 ${name.padRight(26)} → harness error: $e');
        }
      }
    } finally {
      if (snap.isNotEmpty) {
        await restoreNames(pool);
      }
      // ---- restore the HT to its original map (re-assert + verify) ----
      if (bar != null && args.containsKey('no-rebond')) {
        print('\nℹ️  Leaving HT speakers unbonded as requested (--no-rebond).');
        if (originalBarMap.isNotEmpty) {
          print('   Original HT map to restore later: $originalBarMap');
        }
      } else if (bar != null && originalBarMap.isNotEmpty) {
        print('\n🔺 Restoring HT: $originalBarMap');
        final restoreMap = ChannelMap.parse(originalBarMap);
        final want = restoreMap.entries.skip(1).expand((e) => e.channels).toSet();
        var restored = false;
        for (var attempt = 0; attempt < 8 && !restored; attempt++) {
          try {
            await props.addHtSatellite(soundbarIp: bar.ip!, map: restoreMap);
          } catch (_) {}
          await Future<void>.delayed(const Duration(seconds: 8));
          final m = (await topo.getZoneGroups(anyIp))
              .expand((g) => g.members)
              .where((x) => x.uuid == bar.uuid)
              .cast<ZoneGroupMember?>()
              .firstOrNull;
          final chans = (m?.channelAssignments ?? {}).keys.toSet();
          restored = chans.containsAll(want);
          print('   attempt ${attempt + 1}: restored = $restored');
        }
        print(restored
            ? '   ✅ HT restored (⚠️ re-run Trueplay in the iOS app).'
            : '   ❌ HT NOT fully restored — re-add in the app! Map: $originalBarMap');
      }
    }

    print('\n================ RESULTS ================');
    for (final r in results) {
      print(r);
    }
    print('========================================');
    return;
  }

  // --separate: dissolve the live zone the way the app does — detach it into its
  // own group (BecomeCoordinatorOfStandaloneGroup; a zone bond can't be removed
  // while its coordinator is a non-coordinator member of another playback group)
  // then SeparateStereoPair. RemoveBondedZones returns 200 OK but silently
  // no-ops on the 2025 zones feature. Optional --names UUID=Name,UUID=Name
  // restores room names afterwards.
  if (args.containsKey('separate')) {
    final props = DevicePropertiesClient(SonosSoapClient());
    final av = AvTransportClient(SonosSoapClient());
    final coord = (await topo.getZoneGroups(anyIp))
        .expand((g) => g.members)
        .where((m) => !m.invisible && m.isZone)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    if (coord == null) {
      print('\nℹ️  No live zone to separate.');
      return;
    }
    final fullMap = coord.channelMapSet!;
    print('\n⬅️  Separating "${coord.zoneName}" (${coord.ip})  map=$fullMap');

    Future<bool> standalone() async {
      final grp = (await topo.getZoneGroups(anyIp))
          .where((x) => x.members.any((m) => m.uuid == coord.uuid))
          .cast<ZoneGroup?>()
          .firstOrNull;
      return grp == null || grp.coordinatorUuid == coord.uuid;
    }

    print('① detach into standalone group');
    await av.becomeCoordinatorOfStandaloneGroup(coord.ip!);
    for (var i = 0; i < 6 && !await standalone(); i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    print('   standalone = ${await standalone()}');

    print('② SeparateStereoPair');
    await props.separateBondedZones(ip: coord.ip!, channelMapSet: fullMap);
    var ok = false;
    for (var i = 0; i < 7; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      ok = !(await topo.getZoneGroups(anyIp))
          .expand((x) => x.members)
          .any((m) => m.uuid == coord.uuid && m.isZone);
      print('   [${(i + 1) * 3}s] separated = $ok');
      if (ok) break;
    }

    final namesArg = args['names'];
    if (namesArg != null && ok) {
      for (final p in namesArg.split(',')) {
        final kv = p.split('=');
        if (kv.length != 2) continue;
        final dev = devices
            .where((d) => d.uuid == kv[0])
            .cast<SonosDevice?>()
            .firstOrNull;
        if (dev?.ip == null) continue;
        final cur = await props.getZoneAttributes(dev!.ip!);
        await props.setZoneAttributes(dev.ip!,
            ZoneAttributes(zoneName: kv[1], icon: cur.icon, configuration: cur.configuration));
        print('   restored ${kv[0]} -> ${kv[1]}');
      }
    }
    print(ok ? '\n✅ separated' : '\n❌ still not separated');
    return;
  }

  if (membersArg == null) {
    print('\nℹ️  No --members given. Pass --members a,b,c [--confirm] to round-trip a zone, '
        'or --separate to dissolve the existing zone.');
    return;
  }

  final members = membersArg
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((sel) => resolveDevice(devices, sel))
      .toList();
  if (members.length < 2) {
    print('❌ A zone needs at least 2 members.');
    exit(64);
  }
  // Dedupe by uuid (resolveDevice exits on bad input).
  final seen = <String>{};
  for (final m in members) {
    if (!seen.add(m.uuid)) {
      print('❌ Duplicate member: ${m.roomName} (${m.uuid}).');
      exit(64);
    }
  }

  final props = DevicePropertiesClient(SonosSoapClient());
  final coord = members.first;

  // Snapshot names up front.
  final attrs = <String, ZoneAttributes>{};
  for (final m in members) {
    attrs[m.uuid] = await props.getZoneAttributes(m.ip!);
  }

  // Guessed request map: every member gets full-range LF,RF (coordinator first).
  final channelMapSet =
      members.map((m) => '${m.uuid}:LF,RF').join(';');

  print('\nPlan (coordinator = ${coord.roomName}):');
  for (final m in members) {
    print('  • ${m.roomName} (${m.modelName}) ${m.uuid} @ ${m.ip} '
        '— name="${attrs[m.uuid]!.zoneName}"');
  }
  print('  AddBondedZones ChannelMapSet (guess): $channelMapSet');

  if (!confirm) {
    print('\n✅ DRY RUN — nothing changed. Re-run with --confirm for the live round-trip.');
    return;
  }

  print('\n➡️  AddBondedZones… (polling up to ~21s for topology to settle)');
  try {
    await props.addBondedZones(ip: coord.ip!, channelMapSet: channelMapSet);
  } catch (e) {
    print('   ⚠️  AddBondedZones write error (may still apply): $e');
  }

  for (var i = 0; i < 7; i++) {
    await Future<void>.delayed(const Duration(seconds: 3));
    final groups = await topo.getZoneGroups(coord.ip!);
    final all = groups.expand((g) => g.members).toList();
    final visible = all.where((m) => !m.invisible).map((m) => m.uuid).toSet();
    final hiddenCount = members.where((m) => !visible.contains(m.uuid)).length;
    print('   [${(i + 1) * 3}s] $hiddenCount/${members.length - 1} non-coordinators hidden');
    final coordMember = all
        .where((m) => m.uuid == coord.uuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    if (coordMember?.channelMapSet != null) {
      print('       ↳ coordinator ChannelMapSet = ${coordMember!.channelMapSet}');
    }
    if (hiddenCount == members.length - 1 &&
        coordMember?.channelMapSet != null) {
      break;
    }
  }

  print('\n🔬 REAL ChannelMapSet captured above is the ground truth — encode buildGroupMap to match it.');

  print('\n⬅️  Separating (detach → SeparateStereoPair)…');
  await AvTransportClient(SonosSoapClient())
      .becomeCoordinatorOfStandaloneGroup(coord.ip!);
  await settle();
  await props.separateBondedZones(ip: coord.ip!, channelMapSet: channelMapSet);
  await settle();
  await settle();

  print('   Verifying names restored…');
  for (final m in members) {
    final after = await props.getZoneAttributes(m.ip!);
    final want = attrs[m.uuid]!;
    final ok = after.zoneName == want.zoneName;
    print('     ${m.uuid}: "${after.zoneName}" (${ok ? "restored" : "NOT restored"})');
    if (!ok) {
      await props.setZoneAttributes(m.ip!, want);
      print('       🔧 Restored -> "${want.zoneName}"');
    }
    // Re-assert visibility note: a member still hidden here means RemoveBondedZones
    // didn't fully dissolve — re-run discovery to check.
  }
  print('\n🎉 Done. Re-run `dart run tool/spike.dart` to confirm everything is standalone again.');
}

/// Fetches the DeviceProperties SCPD and lists zone/bond/pair actions + their
/// arguments, confirming AddBondedZones/RemoveBondedZones are supported here.
Future<void> _dumpZoneActions(String ip) async {
  try {
    final res = await http
        .get(Uri.parse('http://$ip:1400/xml/DeviceProperties1.xml'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      print('   SCPD fetch failed: HTTP ${res.statusCode}');
      return;
    }
    final doc = XmlDocument.parse(res.body);
    final actions = doc.findAllElements('action').where((a) {
      final n = a.getElement('name')?.innerText ?? '';
      return n.contains('Bonded') || n.contains('Zone') || n.contains('Pair');
    });
    if (actions.isEmpty) {
      print('   ⚠️  No *Bonded/Zone/Pair* actions found in DeviceProperties SCPD.');
      return;
    }
    print('   DeviceProperties zone/bond actions:');
    for (final a in actions) {
      final name = a.getElement('name')?.innerText ?? '?';
      final args = a
          .findAllElements('argument')
          .map((arg) => arg.getElement('name')?.innerText ?? '?')
          .join(', ');
      print('     • $name(${args.isEmpty ? '' : args})');
    }
  } catch (e) {
    print('   SCPD dump skipped: $e');
  }
}

/// Prints any topology member carrying a ChannelMapSet (stereo pair OR zone), so
/// we can eyeball the format an existing zone uses.
Future<void> _dumpExistingZones(ZoneTopologyClient topo, String ip) async {
  try {
    final groups = await topo.getZoneGroups(ip);
    final withMap = groups
        .expand((g) => g.members)
        .where((m) => (m.channelMapSet ?? '').isNotEmpty)
        .toList();
    if (withMap.isEmpty) {
      print('   (no existing ChannelMapSet members — no stereo pairs or zones right now)');
      return;
    }
    print('   Existing ChannelMapSet members:');
    for (final m in withMap) {
      print('     • ${m.zoneName} [${m.uuid}] ChannelMapSet=${m.channelMapSet}');
    }
  } catch (e) {
    print('   topology dump skipped: $e');
  }
}
