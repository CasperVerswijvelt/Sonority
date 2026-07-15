import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/sonos_models.dart';
import '../../data/sonos/diagnostics_log.dart';
import '../../data/sonos/sonos_repository.dart';
import '../widgets/version_badge.dart' show fullVersionLabel;
import 'diagnostics_platform.dart';

/// Which optional sources to fold into the bundle (both default on in the UI).
/// The core files — README, parsed_topology.json, topology.txt, raw_topology.xml,
/// device_descriptions/, app_state.json — are always included.
class DiagnosticsOptions {
  const DiagnosticsOptions({
    this.includeLogs = true,
    this.includeNetwork = true,
  });
  final bool includeLogs;
  final bool includeNetwork;
}

/// Builds the diagnostics zip and returns its file path. Re-fetches the raw
/// topology + per-device descriptions fresh (a few read-only HTTP calls — no
/// Sonos writes), serializes the live [system], dumps app-owned prefs, and adds
/// logs/network per [options]. Structured with named files so a human can browse
/// it and an agent can parse `parsed_topology.json` directly.
Future<String> buildDiagnosticsZip({
  required SonosSystem system,
  required SonosRepository repo,
  required PackageInfo package,
  required DateTime now,
  DiagnosticsOptions options = const DiagnosticsOptions(),
}) async {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  // Core topology views.
  add(
    'parsed_topology.json',
    const JsonEncoder.withIndent('  ').convert(topologyJson(system)),
  );
  add('topology.txt', topologyText(system));

  // Raw GetZoneGroupState from any reachable player.
  final probeIp = system.devicesByUuid.values
      .map((d) => d.ip)
      .firstWhere((ip) => ip != null, orElse: () => null);
  add(
    'raw_topology.xml',
    await _tryFetch(
      () => repo.rawTopology(probeIp!),
      onNull: probeIp == null ? 'No reachable player to query.' : null,
    ),
  );

  // Raw per-device descriptions (capability flags, min-app-version, household id).
  for (final d in system.devicesByUuid.values) {
    final ip = d.ip;
    if (ip == null) continue;
    add(
      'device_descriptions/${_fileSafe(d.roomName)}_${d.uuid}.xml',
      await _tryFetch(() => repo.rawDeviceDescription(ip)),
    );
  }

  // App-owned persisted state (profiles + pre-group room-name snapshots).
  add('app_state.json', await _appStateJson());

  if (options.includeNetwork) {
    add('network.txt', await networkInterfacesText());
  }
  add('README.txt', _readme(system, package, now, options));

  // logs.txt LAST — snapshot the app log only after every other step has run, so
  // any SOAP fault / error logged while fetching the raw topology or the device
  // descriptions above is captured in the same bundle.
  if (options.includeLogs) {
    final lines = DiagnosticsLog.lines;
    add(
      'logs.txt',
      lines.isEmpty ? '(no log lines captured yet)' : lines.join('\n'),
    );
  }

  final zipped = ZipEncoder().encode(archive);
  return writeTempFile('sonority-diagnostics-${_stamp(now)}.zip', zipped);
}

// ── Pure serialization (unit-tested) ───────────────────────────────────────

/// Machine-readable dump of the whole system, INCLUDING invisible members and
/// the raw channel-map strings (nothing hidden — this is the diagnostics view).
Map<String, dynamic> topologyJson(SonosSystem system) => {
  'groups': [
    for (final g in system.groups)
      {
        'coordinatorUuid': g.coordinatorUuid,
        'members': [
          for (final m in g.members)
            {
              'uuid': m.uuid,
              'zoneName': m.zoneName,
              'invisible': m.invisible,
              'location': m.location,
              'ip': m.ip,
              'isHomeTheater': m.isHomeTheater,
              'isGroup': m.isGroup,
              'groupKind': m.groupKind.name,
              'htSatChanMapSet': m.htSatChanMapSet,
              'channelMapSet': m.channelMapSet,
              'satellites': [
                for (final s in m.satellites)
                  {
                    'uuid': s.uuid,
                    'zoneName': s.zoneName,
                    'ip': s.ip,
                    'channels': [for (final c in s.channels) c.token],
                  },
              ],
            },
        ],
      },
  ],
  'devices': [
    for (final d in system.devicesByUuid.values)
      {
        'uuid': d.uuid,
        'roomName': d.roomName,
        'modelName': d.modelName,
        'modelNumber': d.modelNumber,
        'typeLabel': d.typeLabel,
        'ip': d.ip,
        'mac': d.mac,
        'serial': d.serial,
        'softwareVersion': d.softwareVersion,
        'hardwareVersion': d.hardwareVersion,
        'reachable': d.reachable,
        'isSoundbar': d.isSoundbar,
        'isSub': d.isSub,
        'isAmp': d.isAmp,
      },
  ],
};

/// Human-readable mirror of the on-screen technical view — the same string is
/// shown in the diagnostics sheet and written to `topology.txt`.
String topologyText(SonosSystem system) {
  final b = StringBuffer('=== Sonos topology ===\n');
  for (var gi = 0; gi < system.groups.length; gi++) {
    final g = system.groups[gi];
    b.writeln('\nGroup ${gi + 1}  (coordinator ${g.coordinatorUuid})');
    for (final m in g.members) {
      b.writeln(
        '  ${m.invisible ? '○' : '●'} ${m.zoneName}'
        '${m.invisible ? '  [hidden]' : ''}',
      );
      b.writeln('      uuid: ${m.uuid}');
      final d = system.devicesByUuid[m.uuid];
      if (d != null) {
        for (final line in _deviceLines(d)) {
          b.writeln('      $line');
        }
      }
      _writeMap(b, 'HTSatChanMapSet', m.htSatChanMapSet);
      _writeMap(b, 'ChannelMapSet', m.channelMapSet,
          note: m.isGroup ? m.groupKind.name : null);
      for (final s in m.satellites) {
        b.writeln(
          '      └ [${s.channels.map((c) => c.token).join(',')}] ${s.uuid}'
          ' · ${s.ip ?? '?'}',
        );
      }
    }
  }
  // Any device not surfaced above (defensive — usually none). HT satellites are
  // <Satellite> children rather than ZoneGroupMembers, so count them as
  // represented too, else every bonded surround/sub reads as an "orphan".
  final memberUuids = {
    for (final g in system.groups)
      for (final m in g.members) ...[
        m.uuid,
        for (final s in m.satellites) s.uuid,
      ],
  };
  final orphans = system.devicesByUuid.values.where(
    (d) => !memberUuids.contains(d.uuid),
  );
  if (orphans.isNotEmpty) {
    b.writeln('\nDevices not in topology groups:');
    for (final d in orphans) {
      b.writeln('  - ${d.roomName}  ${d.uuid}');
      for (final line in _deviceLines(d)) {
        b.writeln('      $line');
      }
    }
  }
  return b.toString();
}

/// Per-device detail split across short lines (kept narrow so the on-screen
/// monospace view doesn't wrap mid-token).
List<String> _deviceLines(SonosDevice d) {
  final model =
      '${d.modelName}${d.modelNumber != null ? ' [${d.modelNumber}]' : ''}';
  return [
    '$model${d.reachable ? '' : '   (UNREACHABLE)'}',
    'ip ${d.ip ?? '?'}   mac ${d.mac ?? '?'}',
    'serial ${d.serial ?? '?'}',
    'sw ${d.softwareVersion ?? '?'}   hw ${d.hardwareVersion ?? '?'}',
  ];
}

/// Writes a channel-map set one `UUID:tokens` entry per line — far more legible
/// than the raw single-line `;`-joined blob.
void _writeMap(StringBuffer b, String label, String? map, {String? note}) {
  if (map == null || map.isEmpty) return;
  b.writeln('      $label:${note != null ? '  ($note)' : ''}');
  for (final entry in map.split(';')) {
    if (entry.trim().isEmpty) continue;
    b.writeln('        $entry');
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

Future<String> _appStateJson() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = {for (final k in prefs.getKeys()) k: prefs.get(k)};
  return const JsonEncoder.withIndent('  ').convert(inlineJsonPrefs(raw));
}

/// SharedPreferences only stores strings, but the app stores most values as JSON
/// (profiles, name snapshots). Inline any string that is itself valid JSON as
/// real nested JSON so the dump is readable/parseable instead of a wall of
/// escaped quotes; plain (non-JSON) strings and non-string prefs pass through.
Map<String, dynamic> inlineJsonPrefs(Map<String, Object?> raw) => {
      for (final e in raw.entries)
        e.key: e.value is String ? _tryJsonDecode(e.value as String) : e.value,
    };

Object? _tryJsonDecode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return s;
  }
}

Future<String> _tryFetch(
  Future<String> Function() fetch, {
  String? onNull,
}) async {
  if (onNull != null) return onNull;
  try {
    final s = await fetch();
    return s.isEmpty ? '(empty response)' : s;
  } catch (e) {
    return '(fetch failed: $e)';
  }
}

String _readme(
  SonosSystem system,
  PackageInfo package,
  DateTime now,
  DiagnosticsOptions o,
) {
  final files = [
    'README.txt              — this file',
    'parsed_topology.json    — machine-readable system dump (all members incl. hidden)',
    'topology.txt            — human-readable version of the same',
    'raw_topology.xml        — raw GetZoneGroupState from a player',
    'device_descriptions/    — raw device_description.xml per speaker',
    'app_state.json          — the app\'s stored profiles + saved room names',
    if (o.includeLogs)
      'logs.txt                — app diagnostics log (SOAP faults, retries, discovery, errors)',
    if (o.includeNetwork)
      'network.txt             — this device\'s network interfaces',
  ];
  return '''
Sonority diagnostics bundle
===========================
App:       ${fullVersionLabel(package)}  (${package.version}+${package.buildNumber})
Platform:  ${osDescription()}
Captured:  ${now.toIso8601String()}
System:    ${system.devicesByUuid.length} device(s), ${system.groups.length} group(s)

Contents
--------
${files.join('\n')}

Note: the topology contains room names, IP and MAC addresses, and model/serial
info — the data needed to debug bonding/discovery. The optional sources above
were included per the toggles in the app when this bundle was created.
''';
}

String _fileSafe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}
