/// Client for the newer Sonos bond model: the **`zones` namespace on :1443**.
///
/// Current firmware keeps a structured bond model alongside the :1400
/// `HTSatChanMapSet`/`ChannelMapSet` SOAP world. It is guest-tier (the public
/// api-key, no account), returns *named* errors instead of `UPnPError 800`, and
/// reconfigures a live bond in ONE call. See CLAUDE.md ("The `zones` namespace on
/// :1443") for the hardware findings behind every method here.
///
/// This is **the** bonding path for speaker GROUPS. The :1400 SOAP bonding calls
/// are kept in the engine as the legacy path (`bondAndVerify`, `createGroup`,
/// `separateGroup`, `reassertGroup`) — split off, NOT wired as a mid-operation
/// fallback, so a refusal here is an error rather than a second write on top of
/// the first. A home theater is the exception and still bonds over SOAP: an
/// activation cannot change `HTSatChanMapSet` (measured — `tool/ht_zone_check.dart`).
/// There is deliberately no capability probe either: an absent namespace refuses
/// the subscribe by name (`ERROR_UNSUPPORTED_NAMESPACE`) in ~4ms, so the
/// operation itself is the detection.
///
/// ⚠️ Reads are free; **every write** is a live speaker write, gated behind
/// `live: true` so nothing writes by accident.
///
/// Commands have no REST route (hardware-probed: 404/405) and must go over the
/// websocket, so a multi-step operation runs inside [withSession]: ONE socket and
/// ONE household lookup for the whole burst. That is not a micro-optimisation —
/// connecting per command made `applyBondViaZoneApi` pay four TLS handshakes and
/// measured SLOWER than the SOAP path it replaces (`tool/bond_timing.dart`, in
/// that superseded per-command run: add 3.8s SOAP vs 7.3s zones — the current
/// medians for the sessioned version are the ones in CLAUDE.md, not these).
/// Subscribing also delivers the active zones and the definition library, and
/// Sonos pushes a fresh copy after any change, so reads inside a session cost no
/// extra round trip.
/// Reached through the `zone_api.dart` barrel so the screenshot-only web/demo
/// build gets a throwing stub instead.
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

  /// The bonds currently in force, or null if the household has no zone service.
  ///
  /// A standalone REST read for callers that only want a look (the e2e test,
  /// `tool/bond_timing.dart`). Inside [withSession] use
  /// [ZoneApiSession.activeZones], which comes free with the subscribe.
  Future<List<ActiveZone>?> activeZones(String ip) async {
    final c = _client();
    try {
      final body =
          await _get(c, 'https://$ip:1443/api/v1/households/local/zones');
      final zones = body['zones'];
      if (body['_objectType'] != 'activeZoneList' || zones is! List) {
        return null;
      }
      return [for (final z in zones.cast<Map<String, dynamic>>()) _zone(z)];
    } finally {
      c.close(force: true);
    }
  }

  /// Runs [body] against ONE open websocket, then closes it. Every multi-step
  /// operation belongs in here — see the note at the top of the file for why.
  ///
  /// A session exists to issue commands, so the whole thing is the write gate:
  /// `live: true` or nothing opens. One gate instead of one per command.
  ///
  /// Throws [ZoneApiException] if the household has no zone service: the
  /// subscribe is refused by name (`ERROR_UNSUPPORTED_NAMESPACE`, measured at
  /// ~4ms), so there is no timeout to sit through — which is why opening a
  /// session doubles as the capability check.
  Future<T> withSession<T>(
      String ip, Future<T> Function(ZoneSession session) body,
      {bool live = false}) async {
    if (!live) {
      throw StateError(
          'A zones session issues live speaker writes; pass live: true.');
    }
    final c = _client();
    WebSocket? ws;
    try {
      final info =
          await _get(c, 'https://$ip:1443/api/v1/players/local/info');
      ws = await WebSocket.connect(
        'wss://$ip:1443/websocket/api',
        protocols: const ['v1.api.smartspeaker.audio'],
        headers: {'X-Sonos-Api-Key': kSonosGuestApiKey},
        customClient: c,
      ).timeout(timeout);
      final session =
          ZoneApiSession._(ws, info['householdId'] as String, timeout);
      await session._open();
      return await body(session);
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
}

ActiveZone _zone(Map<String, dynamic> z) => ActiveZone(
      zoneId: z['zoneId'] as String,
      members: [
        for (final m in (z['members'] as List).cast<Map<String, dynamic>>())
          ActiveZoneMember(
            uuid: m['id'] as String,
            disconnected: (m['state'] as Map?)?['disconnected'] == true,
          ),
      ],
    );

List<ZoneDefinition> _defs(List<dynamic> zones) => [
      for (final z in zones.cast<Map<String, dynamic>>())
        ZoneDefinition(
          zoneId: z['zoneId'] as String,
          name: z['name'] as String? ?? '',
          rawMap: [
            for (final m in (z['members'] as List).cast<Map<String, dynamic>>())
              '${m['id']}:${(m['channelMap'] as List).join(',')}',
          ].join(';'),
        ),
    ];

/// What a caller may do inside [ZoneApiClient.withSession].
///
/// An interface rather than a concrete type purely so tests can substitute one:
/// [ZoneApiSession] owns a live socket, so it cannot be constructed off-network.
abstract interface class ZoneSession {
  /// The bonds in force as of the last push. Free — no round trip.
  List<ActiveZone> get activeZones;

  /// The stored definition library as of the last push. Free — no round trip.
  List<ZoneDefinition> get definitions;

  /// Waits for Sonos to push an updated library — what follows an add.
  Future<List<ZoneDefinition>> nextDefinitions();

  Future<void> addDefinition({required String name, required String rawMap});

  /// Membership only, one direction per call.
  Future<void> updateDefinition({
    required String zoneId,
    required String rawMap,
  });

  /// ⚠️ Also applies the definition's `name` as the room name.
  Future<void> activate(String zoneId);

  /// A real unbond: members become standalone rooms.
  Future<void> deactivate(String zoneId);

  /// Deletes a stored definition. Refused while it is active.
  Future<void> removeDefinition(String zoneId);
}

/// One open websocket to a player's `zones` namespace. Created by
/// [ZoneApiClient.withSession] and only valid inside it.
///
/// The subscribe that opens the session hands us the current active zones and
/// definition library, and Sonos pushes a fresh copy of either after any change —
/// so [activeZones] and [definitions] are free, and [nextDefinitions] waits for
/// the push rather than asking again.
class ZoneApiSession implements ZoneSession {
  final WebSocket _ws;
  final String _householdId;
  final Duration _timeout;
  final _events = StreamController<(Map<String, dynamic>, dynamic)>.broadcast();

  List<ActiveZone> _activeZones = const [];
  List<ZoneDefinition> _definitions = const [];

  ZoneApiSession._(this._ws, this._householdId, this._timeout) {
    _ws.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as List;
          final header = msg[0] as Map<String, dynamic>;
          final body = msg[1];
          final zones = body is Map ? body['zones'] : null;
          if (zones is List) {
            if (header['type'] == 'activeZonesChange') {
              _activeZones = [
                for (final z in zones) _zone(z as Map<String, dynamic>),
              ];
            } else if (header['type'] == 'zoneDefinitionsChange') {
              _definitions = _defs(zones);
            }
          }
          if (!_events.isClosed) _events.add((header, body));
        } catch (e, s) {
          // A binary frame or an unexpected payload shape would otherwise escape
          // as an uncaught async error, leaving every waiter to time out.
          if (!_events.isClosed) _events.addError(e, s);
        }
      },
      onError: (Object e, StackTrace s) {
        if (!_events.isClosed) _events.addError(e, s);
      },
      onDone: () {
        if (!_events.isClosed) _events.close();
      },
    );
  }

  @override
  List<ActiveZone> get activeZones => _activeZones;

  @override
  List<ZoneDefinition> get definitions => _definitions;

  Future<void> _open() async {
    // Wait for the definition library, which arrives right after the subscribe
    // reply — it is the read no caller can do without.
    final pushed = _events.stream
        .firstWhere((e) => e.$1['type'] == 'zoneDefinitionsChange')
        .timeout(_timeout);
    await _send('subscribe', const {});
    await pushed;
  }

  /// Cheaper and more truthful than re-subscribing: Sonos pushes the library.
  @override
  Future<List<ZoneDefinition>> nextDefinitions() async {
    await _events.stream
        .firstWhere((e) => e.$1['type'] == 'zoneDefinitionsChange')
        .timeout(_timeout);
    return _definitions;
  }

  @override
  Future<void> addDefinition({required String name, required String rawMap}) =>
      _send('addZoneDefinition',
          {'name': name, 'channelMapSet': zoneMembersFromMap(rawMap)});

  /// A channel change or a simultaneous add+remove is refused (`update only
  /// allows add or remove, not both`), which costs nothing: it changes no state.
  @override
  Future<void> updateDefinition(
          {required String zoneId, required String rawMap}) =>
      _send('updateZoneDefinition',
          {'zoneId': zoneId, 'channelMapSet': zoneMembersFromMap(rawMap)});

  @override
  Future<void> activate(String zoneId) =>
      _send('activateZone', {'zoneId': zoneId});

  @override
  Future<void> deactivate(String zoneId) =>
      _send('deactivateZone', {'zoneId': zoneId});

  @override
  Future<void> removeDefinition(String zoneId) =>
      _send('removeZoneDefinition', {'zoneId': zoneId});

  /// Sends one command and waits for its reply. Throws [ZoneApiException] with
  /// the server's own wording on refusal.
  ///
  /// The reply waiter is armed BEFORE the send: on one shared socket the answer
  /// can arrive before a listener attached afterwards would see it.
  Future<void> _send(String command, Map<String, Object> body) async {
    final reply = _events.stream
        .firstWhere((e) => e.$1['response'] == command)
        .timeout(_timeout);
    _ws.add(jsonEncode([
      {
        'namespace': 'zones',
        'command': command,
        'householdId': _householdId,
      },
      body,
    ]));
    final (header, errBody) = await reply;
    if (header['success'] == true) return;
    final err = errBody is Map ? errBody : const <String, Object?>{};
    throw ZoneApiException(
        (err['reason'] ?? err['errorCode'] ?? 'refused').toString());
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
