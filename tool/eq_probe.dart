// Read-only probe for Sonos per-speaker EQ / audio settings over the local API.
// Run on the same Wi-Fi as your Sonos system:
//
//   dart run tool/eq_probe.dart                    # read-only: dump SCPD + values
//   dart run tool/eq_probe.dart --test <room|uuid> # round-trip Bass (bump + restore)
//
// It (1) fetches the RenderingControl SCPD to confirm the exact action/argument
// names for Bass/Treble/Loudness/EQ/OutputFixed, then (2) reads the current
// value of each setting for every discovered speaker, annotated with its HT
// channel. --test flips Bass by +1 and restores it to confirm writes take.
//
// Purpose: nail down the exact action names, EQType tokens and value ranges
// BEFORE wiring lib/data/sonos/speaker_settings.dart into the app.

// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/speaker_settings.dart' show eqTypes;
import 'package:sonority/data/sonos/zone_topology.dart';

import 'discover_util.dart';

const _rcService = 'urn:schemas-upnp-org:service:RenderingControl:1';
const _rcControl = '/MediaRenderer/RenderingControl/Control';
final _soap = SonosSoapClient();

// The EQType tokens the app captures — shared list so probe and client can't
// drift. The probe reads each; ones the speaker doesn't support just fault,
// which tells us which apply to which model.
const _eqTypes = eqTypes;

String _short(Object e) {
  final s = e.toString();
  return s.length > 90 ? '${s.substring(0, 90)}…' : s;
}

/// Print every RenderingControl action whose name mentions an audio setting,
/// with its in/out arguments — so we know the exact envelope + value ranges.
Future<void> _dumpEqActions(String ip) async {
  try {
    final res = await http
        .get(Uri.parse('http://$ip:1400/xml/RenderingControl1.xml'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      print('  SCPD fetch failed: HTTP ${res.statusCode}');
      return;
    }
    final doc = XmlDocument.parse(res.body);
    bool interesting(String n) =>
        n.contains('Bass') ||
        n.contains('Treble') ||
        n.contains('Loudness') ||
        n.contains('EQ') ||
        n.contains('OutputFixed');
    final actions = doc
        .findAllElements('action')
        .where((a) => interesting(a.getElement('name')?.innerText ?? ''));
    for (final a in actions) {
      print('  • ${a.getElement('name')?.innerText ?? '?'}');
      for (final arg in a.findAllElements('argument')) {
        final an = arg.getElement('name')?.innerText ?? '?';
        final dir = arg.getElement('direction')?.innerText ?? '?';
        final rel = arg.getElement('relatedStateVariable')?.innerText ?? '';
        print('      ${dir.padRight(3)} $an  ($rel)');
      }
    }
    // Value ranges live on the state variables (allowedValueRange / list).
    for (final sv in doc.findAllElements('stateVariable')) {
      final n = sv.getElement('name')?.innerText ?? '';
      if (!(n.contains('Bass') || n.contains('Treble') || n.contains('Loudness'))) {
        continue;
      }
      final min = sv.findAllElements('minimum').map((e) => e.innerText);
      final max = sv.findAllElements('maximum').map((e) => e.innerText);
      if (min.isNotEmpty || max.isNotEmpty) {
        print('  range $n: ${min.firstOrNull ?? '?'} .. ${max.firstOrNull ?? '?'}');
      }
    }
  } catch (e) {
    print('  SCPD fetch error: ${_short(e)}');
  }
}

Future<String?> _read(String ip, String action, String outEl,
    {Map<String, String> extra = const {}}) async {
  try {
    final body = await _soap.call(
      ip: ip,
      controlPath: _rcControl,
      serviceType: _rcService,
      action: action,
      args: {'InstanceID': '0', ...extra},
    );
    final els = body.findAllElements(outEl);
    return els.isEmpty ? null : els.first.innerText.trim();
  } catch (e) {
    return '✗ ${_short(e)}';
  }
}

Future<String> _readAll(String ip) async {
  final bass = await _read(ip, 'GetBass', 'CurrentBass');
  final treble = await _read(ip, 'GetTreble', 'CurrentTreble');
  final loud =
      await _read(ip, 'GetLoudness', 'CurrentLoudness', extra: {'Channel': 'Master'});
  final vol =
      await _read(ip, 'GetVolume', 'CurrentVolume', extra: {'Channel': 'Master'});
  final parts = [
    'bass=$bass',
    'treble=$treble',
    'loud=$loud',
    'vol=$vol',
  ];
  for (final t in _eqTypes) {
    final v = await _read(ip, 'GetEQ', 'CurrentValue', extra: {'EQType': t});
    // Only surface EQ types the speaker actually answers, to keep lines readable.
    if (v != null && !v.startsWith('✗')) parts.add('$t=$v');
  }
  return parts.join('  ');
}

Future<void> main(List<String> argv) async {
  print('🔎 Discovery…');
  final ipByUuid = <String, String>{};
  final labelByUuid = <String, String>{};
  String? anyIp;
  for (final d in await discoverDevices()) {
    if (d.ip == null) continue;
    anyIp ??= d.ip;
    ipByUuid[d.uuid] = d.ip!;
    labelByUuid[d.uuid] = '${d.roomName} (${d.modelName})';
  }
  if (anyIp == null) {
    print('❌ Could not read any device description.');
    return;
  }

  // Map uuid -> channel token(s) from any HT map or stereo-pair/zone map.
  final channelByUuid = <String, String>{};
  final groups = await ZoneTopologyClient(SonosSoapClient()).getZoneGroups(anyIp);
  for (final g in groups) {
    for (final m in g.members) {
      for (final raw in [m.htSatChanMapSet, m.channelMapSet]) {
        if (raw == null || raw.isEmpty) continue;
        for (final part in raw.split(';')) {
          final c = part.indexOf(':');
          if (c < 0) continue;
          channelByUuid[part.substring(0, c).trim()] = part.substring(c + 1).trim();
        }
      }
    }
  }

  String? resolve(String roomOrUuid) {
    if (ipByUuid.containsKey(roomOrUuid)) return roomOrUuid;
    final hit = labelByUuid.entries.firstWhere(
      (e) => e.value.toLowerCase().contains(roomOrUuid.toLowerCase()),
      orElse: () => const MapEntry('', ''),
    );
    return hit.key.isEmpty ? null : hit.key;
  }

  // ---- write round-trip: bump Bass by +1, then restore (confirms writes) ----
  if (argv.contains('--test')) {
    final idx = argv.indexOf('--test');
    final target = (idx + 1 < argv.length) ? argv[idx + 1] : '';
    final uuid = resolve(target);
    if (uuid == null) {
      print('❌ No speaker matching "$target".');
      return;
    }
    final ip = ipByUuid[uuid]!;
    try {
      final before = await _read(ip, 'GetBass', 'CurrentBass');
      final n = int.tryParse(before ?? '') ?? 0;
      final bumped = n >= 10 ? n - 1 : n + 1;
      await _soap.call(
        ip: ip,
        controlPath: _rcControl,
        serviceType: _rcService,
        action: 'SetBass',
        args: {'InstanceID': '0', 'DesiredBass': '$bumped'},
      );
      final mid = await _read(ip, 'GetBass', 'CurrentBass');
      await _soap.call(
        ip: ip,
        controlPath: _rcControl,
        serviceType: _rcService,
        action: 'SetBass',
        args: {'InstanceID': '0', 'DesiredBass': '$n'},
      );
      final after = await _read(ip, 'GetBass', 'CurrentBass');
      print('${labelByUuid[uuid]} @ $ip  bass: $before → $mid → $after (restored)');
    } catch (e) {
      print('✗ ${labelByUuid[uuid]} @ $ip: ${_short(e)}');
    }
    return;
  }

  // ---- default: read-only diagnostic ----
  print('\n📜 RenderingControl SCPD — EQ/audio actions (via $anyIp):');
  await _dumpEqActions(anyIp);

  print('\n📊 Audio settings per speaker:');
  for (final entry in ipByUuid.entries) {
    final uuid = entry.key, ip = entry.value;
    final ch = channelByUuid[uuid];
    final tag = ch == null ? '' : ' [$ch]';
    print('  ${(labelByUuid[uuid] ?? uuid)}$tag');
    print('      ${await _readAll(ip)}');
  }

  print('\nLegend: bass/treble typically −10..10, loud/night 0/1, '
      'sub/surround gain a signed range. ✗ = the speaker rejects that setting.');
}
