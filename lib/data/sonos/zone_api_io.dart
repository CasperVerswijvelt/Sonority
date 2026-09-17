/// Client for the newer Sonos bond model: the **`zones` namespace on :1443**.
///
/// Current firmware keeps a structured bond model alongside the :1400
/// `HTSatChanMapSet`/`ChannelMapSet` SOAP world. It is guest-tier (the public
/// api-key, no account), returns *named* errors instead of `UPnPError 800`, and
/// reconfigures a live bond in ONE call. See CLAUDE.md ("The `zones` namespace on
/// :1443") for the hardware findings behind every method here.
///
/// It is **undocumented**, so nothing may depend on it: [supported] feature-detects
/// per household and every caller keeps its SOAP path as the fallback.
///
/// ⚠️ Reads are free; [updateDefinition] is a **live speaker write** and is gated
/// behind `live: true`, so nothing writes by accident.
///
/// Reads go over REST; commands have no REST route (hardware-probed: 404/405) and
/// must go over the websocket. Reached through the `zone_api.dart` barrel so the
/// screenshot-only web/demo build gets a throwing stub instead.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'channel_map.dart';

/// The public Sonos guest api-key — sufficient for the whole `zones` namespace.
const kSonosGuestApiKey = '123e4567-e89b-12d3-a456-426655440000';

/// One member of a live bond, as the zone service sees it.
///
/// [disconnected] is the signal :1400 has no equivalent for: a speaker can sit in
/// `HTSatChanMapSet` and still not be part of the *active zone*. It does NOT mean
/// "receiving no audio" (the dev rig's fronts are audio-confirmed while reporting
/// disconnected) — treat it as bookkeeping, not a fault.
class ActiveZoneMember {
  final String uuid;
  final bool disconnected;
  const ActiveZoneMember({required this.uuid, required this.disconnected});
}

/// A bond currently in force. [zoneId] is the handle every command takes.
class ActiveZone {
  final String zoneId;
  /// Coordinator first — which is what identifies whose bond this is.
  final List<ActiveZoneMember> members;
  const ActiveZone({required this.zoneId, required this.members});
}

/// `UUID:CH,CH;UUID:CH` → the namespace's `channelMapSet` shape.
///
/// The engine's existing recipes (`buildLayoutMap` / `buildGroupMap`) feed this
/// verbatim — the newer API takes the same assignments, just JSON-shaped.
List<Map<String, Object>> zoneMembersFromMap(String rawMap) => [
  for (final e in ChannelMap.parse(rawMap).entries)
    {'id': e.uuid, 'channels': e.tokens},
];

/// A STORED bond configuration. The household keeps a library of these; exactly
/// one per room is active at a time. [name] matters: activating a definition
/// applies its name as the ROOM NAME, so a stale name renames a real room.
class ZoneDefinition {
  final String zoneId;
  final String name;

  /// `UUID:CH,CH;…`, in the engine's own channel-map format.
  final String rawMap;
  const ZoneDefinition({
    required this.zoneId,
    required this.name,
    required this.rawMap,
  });
}

class ZoneApiClient {
  final Duration timeout;
  const ZoneApiClient({this.timeout = const Duration(seconds: 8)});

  HttpClient _client() => HttpClient()
    // The player serves a self-signed cert (server-auth only) — same bypass as
    // every other :1443 call in the engine.
    ..badCertificateCallback = ((_, __, ___) => true)
    ..connectionTimeout = timeout;

  /// True when this household exposes the `zones` namespace. One REST call, no
  /// websocket — cheap enough to gate a feature on.
  Future<bool> supported(String ip) async {
    try {
      return (await activeZones(ip)) != null;
    } catch (_) {
      return false;
    }
  }

  /// The bonds currently in force, or null if the household has no zone service.
  Future<List<ActiveZone>?> activeZones(String ip) async {
    final c = _client();
    try {
      final body = await _get(
        c,
        'https://$ip:1443/api/v1/households/local/zones',
      );
      final zones = body['zones'];
      if (body['_objectType'] != 'activeZoneList' || zones is! List) {
        return null;
      }
      return [
        for (final z in zones.cast<Map<String, dynamic>>())
          ActiveZone(
            zoneId: z['zoneId'] as String,
            members: [
              for (final m
                  in (z['members'] as List).cast<Map<String, dynamic>>())
                ActiveZoneMember(
                  uuid: m['id'] as String,
                  disconnected: (m['state'] as Map?)?['disconnected'] == true,
                ),
            ],
          ),
      ];
    } finally {
      c.close(force: true);
    }
  }

  /// Change a live bond's membership in place — the one call that replaces
  /// dissolve-then-recreate for a member **removal** (`AddBondedZones` faults on
  /// any map that drops a member).
  ///
  /// ⚠️ Hardware-confirmed limit: the namespace allows **add or remove, one
  /// direction per call, membership only**. A channel reassignment, or an add and
  /// a remove together, is refused with `update only allows add or remove, not
  /// both` — the call changes nothing, so the caller just falls back.
  ///
  /// Throws [ZoneApiException] with the server's own reason on refusal.
  Future<void> updateDefinition({
    required String ip,
    required String zoneId,
    required String rawMap,
    bool live = false,
  }) async {
    _requireLive(live, 'updateDefinition');
    await _command(ip, 'updateZoneDefinition', {
      'zoneId': zoneId,
      'channelMapSet': zoneMembersFromMap(rawMap),
    });
  }

  /// The household's stored definition library. Only ever arrives as a pushed
  /// event, so this subscribes and takes the first `zoneDefinitionsChange`.
  Future<List<ZoneDefinition>> definitions(String ip) async {
    final zones = await _subscribeOnce(ip);
    return [
      for (final z in zones)
        ZoneDefinition(
          zoneId: z['zoneId'] as String,
          name: z['name'] as String? ?? '',
          rawMap: [
            for (final m in (z['members'] as List).cast<Map<String, dynamic>>())
              '${m['id']}:${(m['channelMap'] as List).join(',')}',
          ].join(';'),
        ),
    ];
  }

  /// Store a new definition. Does NOT apply it — [activate] does.
  Future<void> addDefinition({
    required String ip,
    required String name,
    required String rawMap,
    bool live = false,
  }) async {
    _requireLive(live, 'addDefinition');
    await _command(ip, 'addZoneDefinition', {
      'name': name,
      'channelMapSet': zoneMembersFromMap(rawMap),
    });
  }

  /// Apply a stored definition — one call replaces a whole bond rebuild.
  ///
  /// ⚠️ Also applies the definition's `name` as the room name.
  Future<void> activate({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async {
    _requireLive(live, 'activate');
    await _command(ip, 'activateZone', {'zoneId': zoneId});
  }

  /// Dissolve the live bond. A real unbond: members become standalone rooms.
  Future<void> deactivate({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async {
    _requireLive(live, 'deactivate');
    await _command(ip, 'deactivateZone', {'zoneId': zoneId});
  }

  /// Delete a stored definition. Refused while it is active.
  Future<void> removeDefinition({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async {
    _requireLive(live, 'removeDefinition');
    await _command(ip, 'removeZoneDefinition', {'zoneId': zoneId});
  }

  void _requireLive(bool live, String what) {
    if (!live) {
      throw StateError('$what is a live speaker write; pass live: true.');
    }
  }

  /// Connect, subscribe, take the first `zoneDefinitionsChange`, close.
  Future<List<Map<String, dynamic>>> _subscribeOnce(String ip) async {
    final c = _client();
    WebSocket? ws;
    try {
      final info = await _get(c, 'https://$ip:1443/api/v1/players/local/info');
      ws = await WebSocket.connect(
        'wss://$ip:1443/websocket/api',
        protocols: const ['v1.api.smartspeaker.audio'],
        headers: {'X-Sonos-Api-Key': kSonosGuestApiKey},
        customClient: c,
      ).timeout(timeout);
      final done = Completer<List<Map<String, dynamic>>>();
      ws.listen(
        (raw) {
          if (done.isCompleted) return;
          try {
            final msg = jsonDecode(raw as String) as List;
            if ((msg[0] as Map)['type'] != 'zoneDefinitionsChange') return;
            done.complete(
              ((msg[1] as Map)['zones'] as List).cast<Map<String, dynamic>>(),
            );
          } catch (e, s) {
            // A binary frame or an unexpected payload shape would otherwise
            // escape as an uncaught async error, leaving us to wait out the
            // whole timeout for a reply that can never parse.
            if (!done.isCompleted) done.completeError(e, s);
          }
        },
        // A close or error arriving after we already completed must not throw.
        onError: (Object e, StackTrace s) {
          if (!done.isCompleted) done.completeError(e, s);
        },
        cancelOnError: true,
      );
      ws.add(
        jsonEncode([
          {
            'namespace': 'zones',
            'command': 'subscribe',
            'householdId': info['householdId'],
          },
          const <String, Object>{},
        ]),
      );
      return await done.future.timeout(timeout);
    } finally {
      await ws?.close();
      c.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _get(HttpClient c, String url) async {
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set('X-Sonos-Api-Key', kSonosGuestApiKey);
    final res = await req.close().timeout(timeout);
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  /// One websocket round-trip: connect, send, wait for this command's reply,
  /// close. Commands are rare and the socket is cheap, so the engine deliberately
  /// keeps no long-lived connection.
  Future<void> _command(
    String ip,
    String command,
    Map<String, Object> body,
  ) async {
    final c = _client();
    WebSocket? ws;
    try {
      final info = await _get(c, 'https://$ip:1443/api/v1/players/local/info');
      ws = await WebSocket.connect(
        'wss://$ip:1443/websocket/api',
        protocols: const ['v1.api.smartspeaker.audio'],
        headers: {'X-Sonos-Api-Key': kSonosGuestApiKey},
        customClient: c,
      ).timeout(timeout);
      final done = Completer<void>();
      ws.listen(
        (raw) {
          if (done.isCompleted) return;
          try {
            final msg = jsonDecode(raw as String) as List;
            final header = msg[0] as Map<String, dynamic>;
            if (header['response'] != command) return;
            if (header['success'] == true) {
              done.complete();
            } else {
              final err = msg[1] as Map<String, dynamic>;
              done.completeError(
                ZoneApiException(
                  (err['reason'] ?? err['errorCode'] ?? 'refused').toString(),
                ),
              );
            }
          } catch (e, s) {
            if (!done.isCompleted) done.completeError(e, s);
          }
        },
        onError: (Object e, StackTrace s) {
          if (!done.isCompleted) done.completeError(e, s);
        },
        cancelOnError: true,
      );
      ws.add(
        jsonEncode([
          {
            'namespace': 'zones',
            'command': command,
            'householdId': info['householdId'],
          },
          body,
        ]),
      );
      await done.future.timeout(timeout);
    } finally {
      await ws?.close();
      c.close(force: true);
    }
  }
}

/// A refusal from the `zones` namespace, carrying the server's own wording
/// (`zone def not found`, `update only allows add or remove, not both`, …).
class ZoneApiException implements Exception {
  final String reason;
  const ZoneApiException(this.reason);
  @override
  String toString() => 'ZoneApiException: $reason';
}
