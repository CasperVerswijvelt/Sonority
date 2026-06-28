// Read-only probe for Sonos Trueplay / room-calibration over the local API.
// Run on the same Wi-Fi as your Sonos system:
//
//   dart run tool/trueplay_probe.dart                 # read-only: dump status
//   dart run tool/trueplay_probe.dart --enable <room|uuid>   # toggle on  (reversible)
//   dart run tool/trueplay_probe.dart --disable <room|uuid>  # toggle off (reversible)
//
// It (1) fetches the RenderingControl SCPD to confirm the exact action/argument
// names for GetRoomCalibrationStatus / SetRoomCalibrationStatus, then (2) reads
// RoomCalibrationAvailable + RoomCalibrationEnabled for every discovered speaker,
// annotated with its home-theater channel. The write modes only flip the
// enable flag (no measurement, no bonding change) and re-read to confirm.

// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'package:sonority/data/sonos/device_description.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

const _rcService = 'urn:schemas-upnp-org:service:RenderingControl:1';
const _rcControl = '/MediaRenderer/RenderingControl/Control';
final _soap = SonosSoapClient();

String _short(Object e) {
  final s = e.toString();
  return s.length > 100 ? '${s.substring(0, 100)}…' : s;
}

/// Fetch the RenderingControl SCPD and print every action whose name mentions
/// "Calibration", with its in/out arguments — so we know the exact envelope.
Future<void> _dumpCalibrationActions(String ip) async {
  try {
    final res = await http
        .get(Uri.parse('http://$ip:1400/xml/RenderingControl1.xml'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      print('  SCPD fetch failed: HTTP ${res.statusCode}');
      return;
    }
    final doc = XmlDocument.parse(res.body);
    final actions = doc.findAllElements('action').where((a) =>
        (a.getElement('name')?.innerText ?? '').contains('Calibration'));
    if (actions.isEmpty) {
      print('  (no *Calibration* actions in SCPD)');
      return;
    }
    for (final a in actions) {
      final name = a.getElement('name')?.innerText ?? '?';
      print('  • $name');
      for (final arg in a.findAllElements('argument')) {
        final an = arg.getElement('name')?.innerText ?? '?';
        final dir = arg.getElement('direction')?.innerText ?? '?';
        final rel = arg.getElement('relatedStateVariable')?.innerText ?? '';
        print('      ${dir.padRight(3)} $an  ($rel)');
      }
    }
  } catch (e) {
    print('  SCPD fetch error: ${_short(e)}');
  }
}

Future<Map<String, String>> _getStatus(String ip) async {
  final body = await _soap.call(
    ip: ip,
    controlPath: _rcControl,
    serviceType: _rcService,
    action: 'GetRoomCalibrationStatus',
    args: {'InstanceID': '0'},
  );
  final out = <String, String>{};
  for (final name in ['RoomCalibrationEnabled', 'RoomCalibrationAvailable']) {
    final els = body.findAllElements(name);
    if (els.isNotEmpty) out[name] = els.first.innerText.trim();
  }
  return out;
}

Future<void> _setEnabled(String ip, bool on) => _soap.call(
      ip: ip,
      controlPath: _rcControl,
      serviceType: _rcService,
      action: 'SetRoomCalibrationStatus',
      args: {'InstanceID': '0', 'RoomCalibrationEnabled': on ? '1' : '0'},
    );

Future<void> main(List<String> argv) async {
  print('🔎 Discovery…');
  final locations = await SsdpDiscovery().discover();
  if (locations.isEmpty) {
    print('❌ No players. Same Wi-Fi? Local network allowed?');
    return;
  }

  final descriptions = DeviceDescriptionClient();
  final ipByUuid = <String, String>{};
  final labelByUuid = <String, String>{};
  String? anyIp;
  for (final loc in locations) {
    try {
      final d = await descriptions.fetch(loc);
      if (d.ip == null) continue;
      anyIp ??= d.ip;
      ipByUuid[d.uuid] = d.ip!;
      labelByUuid[d.uuid] = '${d.roomName} (${d.modelName})';
    } catch (_) {}
  }
  if (anyIp == null) {
    print('❌ Could not read any device description.');
    return;
  }

  // Map uuid -> channel token(s) from any HT map or stereo-pair map.
  final channelByUuid = <String, String>{};
  final groups =
      await ZoneTopologyClient(SonosSoapClient()).getZoneGroups(anyIp);
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

  // ---- write modes (reversible: enable flag only) ----
  final wantEnable = argv.contains('--enable');
  final wantDisable = argv.contains('--disable');
  if (wantEnable || wantDisable) {
    final idx = argv.indexOf(wantEnable ? '--enable' : '--disable');
    final target = (idx + 1 < argv.length) ? argv[idx + 1] : '';
    final uuid = resolve(target);
    if (uuid == null) {
      print('❌ No speaker matching "$target".');
      return;
    }
    final ip = ipByUuid[uuid]!;
    try {
      await _setEnabled(ip, wantEnable);
      final back = await _getStatus(ip);
      print('${wantEnable ? "ENABLED" : "DISABLED"} ${labelByUuid[uuid]} @ $ip → $back');
    } catch (e) {
      print('✗ ${labelByUuid[uuid]} @ $ip: ${_short(e)}');
    }
    return;
  }

  // ---- default: read-only diagnostic ----
  print('\n📜 RenderingControl SCPD — calibration actions (via $anyIp):');
  await _dumpCalibrationActions(anyIp);

  print('\n📊 Room-calibration status per speaker:');
  for (final entry in ipByUuid.entries) {
    final uuid = entry.key, ip = entry.value;
    final ch = channelByUuid[uuid];
    final tag = ch == null ? '' : ' [$ch]';
    try {
      final s = await _getStatus(ip);
      final avail = s['RoomCalibrationAvailable'] ?? '?';
      final en = s['RoomCalibrationEnabled'] ?? '?';
      final head = '  ${(labelByUuid[uuid] ?? uuid).padRight(30)}$tag'.padRight(46);
      print('$head  available=$avail  enabled=$en');
    } catch (e) {
      print('  ${(labelByUuid[uuid] ?? uuid).padRight(30)}$tag  ✗ ${_short(e)}');
    }
  }

  print('\nLegend: available=1 → a tuning is stored on that speaker; '
      'enabled=1 → it is applied. Both 1 ⇒ Trueplay active.');
}
