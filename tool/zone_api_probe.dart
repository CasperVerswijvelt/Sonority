// Probe for the NEWER Sonos bond model: the `zones` namespace on port 1443.
//
// Current firmware runs a second, structured bond model alongside the :1400
// HTSatChanMapSet/ChannelMapSet SOAP world. Sonority's speaker-group bonding now
// runs on this namespace; only home theaters still use the SOAP calls. It is
// guest-accessible (no auth, well-known API key), gives *named* errors instead of
// `UPnPError 800`, and applies a whole layout in ONE call. See CLAUDE.md
// ("The `zones` namespace on :1443").
//
//   dart run tool/zone_api_probe.dart                          # dump (read-only)
//   dart run tool/zone_api_probe.dart --watch                  # live event stream
//   dart run tool/zone_api_probe.dart --validate "<map>"       # legal-shape check, no live change
//   dart run tool/zone_api_probe.dart --create <name> --map "<map>" --confirm
//   dart run tool/zone_api_probe.dart --update <zoneId> --map "<map>" --confirm
//   dart run tool/zone_api_probe.dart --activate <zoneId> --confirm
//   dart run tool/zone_api_probe.dart --deactivate <zoneId> --confirm
//   dart run tool/zone_api_probe.dart --remove <zoneId> --confirm
//   dart run tool/zone_api_probe.dart --roundtrip <name> --map "<map>" --confirm
//
// `<map>` is the SAME `UUID:CH[,CH];UUID:CH` string the :1400 engine builds
// (`buildLayoutMap` / `buildGroupMap`), so recipes are reusable verbatim.
//
// SAFETY: every write is gated behind --confirm. `--validate` and `--roundtrip`
// are self-restoring (add→…→remove); `--activate`/`--deactivate` are NOT — they
// bond and unbond real speakers. `deactivateZone` frees satellites and Sonos
// auto-renames them "<Room> 2", exactly like RemoveHTSatellite.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sonority/data/sonos/channel_map.dart';

import 'discover_util.dart';

/// The well-known guest API key every Sonos player accepts on :1443.
const kApiKey = '123e4567-e89b-12d3-a456-426655440000';

Future<void> main(List<String> argv) async {
  final args = parseArgs(argv, flags: {'confirm', 'watch'});
  final confirm = args.containsKey('confirm');

  print('🔎 Discovering…');
  final devices = await discoverDevices();
  final ip = devices.map((d) => d.ip).whereType<String>().firstOrNull;
  if (ip == null) {
    print('❌ No Sonos devices found.');
    exit(1);
  }
  final api = await ZoneApi.connect(ip);
  print('🔌 ${api.restBase}  household=${api.householdId.split('.').first}…\n');

  try {
    if (args.containsKey('watch')) return await _watch(api);

    final map = args['map'];
    if (args.containsKey('validate')) {
      await _validate(api, args['validate']!);
    } else if (args.containsKey('create')) {
      _requireConfirm(confirm, 'create');
      print(await api.add(args['create']!, _toMembers(map!)));
    } else if (args.containsKey('update')) {
      _requireConfirm(confirm, 'update');
      print(
        await api.call('updateZoneDefinition', {
          'zoneId': args['update']!,
          'channelMapSet': _toMembers(map!),
        }),
      );
    } else if (args.containsKey('activate')) {
      _requireConfirm(confirm, 'activate');
      print(await api.call('activateZone', {'zoneId': args['activate']!}));
    } else if (args.containsKey('deactivate')) {
      _requireConfirm(confirm, 'deactivate');
      print(await api.call('deactivateZone', {'zoneId': args['deactivate']!}));
    } else if (args.containsKey('remove')) {
      _requireConfirm(confirm, 'remove');
      print(
        await api.call('removeZoneDefinition', {'zoneId': args['remove']!}),
      );
    } else if (args.containsKey('roundtrip')) {
      _requireConfirm(confirm, 'roundtrip');
      await _roundtrip(api, args['roundtrip']!, map!);
    }
    await _dump(api);
  } finally {
    await api.close();
  }
}

void _requireConfirm(bool confirm, String what) {
  if (confirm) return;
  print('⚠️  "$what" writes to the live system — re-run with --confirm.');
  exit(1);
}

/// `UUID:CH,CH;UUID:CH` → the API's `[{id, channels:[…]}]` shape.
List<Map<String, Object>> _toMembers(String raw) => [
  for (final e in ChannelMap.parse(raw).entries)
    {'id': e.uuid, 'channels': e.tokens},
];

Future<void> _dump(ZoneApi api) async {
  final active = await api.activeZones();
  print('\n🎛️  Active zones (${active.length}) — the bond actually in force:');
  for (final z in active) {
    print('  ▸ ${z['name']}  ${z['zoneId']}');
    for (final m in (z['members'] as List).cast<Map<String, dynamic>>()) {
      final off = (m['state'] as Map)['disconnected'] == true;
      print(
        '      ${off ? "✗ DISCONNECTED" : "✓ connected   "} '
        '${(m['channelMap'] as List).join(",").padRight(8)} ${m['id']}',
      );
    }
  }

  final defs = await api.definitions();
  print(
    '\n📚 Stored zone definitions (${defs.length}) — the household library:',
  );
  for (final z in defs) {
    final members = (z['members'] as List).cast<Map<String, dynamic>>();
    print(
      '  ${z['zoneId']}  ${(z['name'] as String).padRight(14)} '
      '${members.map((m) => (m['channelMap'] as List).join(",")).join(";")}',
    );
  }
}

Future<void> _watch(ZoneApi api) async {
  print('👀 Subscribed. Ctrl-C to stop.\n');
  api.events.listen((e) {
    final type = e.$1['type'];
    if (type == 'activeZonesChange') {
      for (final z in (e.$2['zones'] as List).cast<Map<String, dynamic>>()) {
        final members = (z['members'] as List).cast<Map<String, dynamic>>();
        print(
          '${DateTime.now().toIso8601String().substring(11, 19)} '
          '${z['name']} ${z['zoneId'].toString().substring(0, 8)} '
          '${members.map((m) => "${(m['channelMap'] as List).join(",")}"
              "${(m['state'] as Map)['disconnected'] == true ? "✗" : "✓"}").join(" ")}',
        );
      }
    }
  });
  await Future<void>.delayed(const Duration(days: 1));
}

/// Add a definition, then immediately remove it. Never activates, so the live
/// system is untouched — this just asks Sonos "is this bond shape legal?".
Future<void> _validate(ZoneApi api, String map) async {
  final before = (await api.definitions()).length;
  final res = await api.add('SonorityProbe', _toMembers(map));
  if (res.$1) {
    final made = (await api.definitions())
        .where((z) => z['name'] == 'SonorityProbe')
        .toList();
    print('✅ accepted — Sonos considers this a legal bond shape');
    for (final z in made) {
      await api.call('removeZoneDefinition', {'zoneId': z['zoneId']});
    }
  } else {
    print('❌ rejected: ${res.$2}');
  }
  final after = (await api.definitions()).length;
  if (after != before) {
    print('⚠️  definition count $before → $after (cleanup failed!)');
  }
}

/// create → activate → poll until every member reports connected → deactivate →
/// remove. Reports attempts + wall time, the numbers that decide whether this
/// beats bondAndVerify's re-assert loop.
Future<void> _roundtrip(ZoneApi api, String name, String map) async {
  final t0 = DateTime.now();
  final add = await api.add(name, _toMembers(map));
  if (!add.$1) {
    print('❌ create failed: ${add.$2}');
    return;
  }
  final zoneId =
      (await api.definitions()).lastWhere((z) => z['name'] == name)['zoneId']
          as String;
  print('➕ created $zoneId');

  try {
    print(
      '▶️  activate: ${await api.call('activateZone', {'zoneId': zoneId})}',
    );
    var polls = 0;
    var connected = false;
    while (polls < 20 && !connected) {
      await Future<void>.delayed(const Duration(seconds: 6));
      polls++;
      final z = (await api.activeZones())
          .where((z) => z['zoneId'] == zoneId)
          .firstOrNull;
      final members = (z?['members'] as List?)?.cast<Map<String, dynamic>>();
      connected =
          members != null &&
          members.length == ChannelMap.parse(map).entries.length &&
          members.every((m) => (m['state'] as Map)['disconnected'] != true);
      print(
        '   poll $polls: ${members == null ? "(zone not active yet)" : members.map((m) => "${(m['channelMap'] as List).join(",")}"
                  "${(m['state'] as Map)['disconnected'] == true ? "✗" : "✓"}").join(" ")}',
      );
    }
    final secs = DateTime.now().difference(t0).inSeconds;
    print(
      connected
          ? '✅ fully connected after $polls poll(s), ${secs}s — ONE activate call, no re-assert loop'
          : '❌ never fully connected after $polls polls (${secs}s)',
    );
  } finally {
    print('\n♻️  restoring');
    print(
      '   deactivate: ${await api.call('deactivateZone', {'zoneId': zoneId})}',
    );
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(seconds: 10));
      final res = await api.call('removeZoneDefinition', {'zoneId': zoneId});
      print('   remove: $res');
      if (res.$1) break;
    }
  }
}

/// Minimal client for the `zones` namespace: REST for reads, websocket for
/// commands + events. Deliberately lives in the tool, not `lib/` — this is a
/// probe of an undocumented API, not (yet) an engine dependency.
class ZoneApi {
  final String restBase;
  final String householdId;
  final WebSocket _ws;
  final HttpClient _http;
  final _events =
      StreamController<
        (Map<String, dynamic>, Map<String, dynamic>)
      >.broadcast();

  ZoneApi._(this.restBase, this.householdId, this._ws, this._http) {
    _ws.listen((raw) {
      final msg = (jsonDecode(raw as String) as List)
          .cast<Map<String, dynamic>>();
      _events.add((msg[0], msg[1]));
    });
  }

  Stream<(Map<String, dynamic>, Map<String, dynamic>)> get events =>
      _events.stream;

  static Future<ZoneApi> connect(String ip) async {
    final http = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    final info = await _get(http, 'https://$ip:1443/api/v1/players/local/info');
    final ws = await WebSocket.connect(
      'wss://$ip:1443/websocket/api',
      protocols: ['v1.api.smartspeaker.audio'],
      headers: {'X-Sonos-Api-Key': kApiKey},
      customClient: http,
    );
    final api = ZoneApi._(
      'https://$ip:1443/api/v1',
      info['householdId'] as String,
      ws,
      http,
    );
    await api.call('subscribe', const {});
    return api;
  }

  static Future<Map<String, dynamic>> _get(HttpClient c, String url) async {
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set('X-Sonos-Api-Key', kApiKey);
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  /// Sends one command and waits for its reply. Returns (success, reason).
  Future<(bool, String?)> call(String command, Map<String, Object> body) async {
    final done = Completer<(bool, String?)>();
    late StreamSubscription<void> sub;
    sub = events.listen((e) {
      if (e.$1['response'] != command || done.isCompleted) return;
      done.complete((
        e.$1['success'] == true,
        e.$2['reason'] as String? ?? e.$2['errorCode'] as String?,
      ));
      sub.cancel();
    });
    _ws.add(
      jsonEncode([
        {'namespace': 'zones', 'command': command, 'householdId': householdId},
        body,
      ]),
    );
    return done.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => (false, 'timeout'),
    );
  }

  Future<(bool, String?)> add(String name, List<Map<String, Object>> members) =>
      call('addZoneDefinition', {'name': name, 'channelMapSet': members});

  Future<List<Map<String, dynamic>>> activeZones() async {
    final r = await _get(_http, '$restBase/households/local/zones');
    return (r['zones'] as List).cast<Map<String, dynamic>>();
  }

  /// Definitions only arrive as a pushed event, so re-subscribe and take the
  /// next `zoneDefinitionsChange`.
  Future<List<Map<String, dynamic>>> definitions() async {
    final next = events.firstWhere(
      (e) => e.$1['type'] == 'zoneDefinitionsChange',
    );
    await call('subscribe', const {});
    final e = await next.timeout(const Duration(seconds: 10));
    return (e.$2['zones'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> close() async {
    await _ws.close();
    _http.close(force: true);
    await _events.close();
  }
}
