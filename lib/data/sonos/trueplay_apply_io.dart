/// Thin client for the spectral-tuning **apply** REST endpoint on a player's
/// `:1443`. Guest-tier: the write persists with only the public Sonos guest
/// api-key — no account/OAuth/grant, same tier as the rest of Sonority's local
/// API. The endpoint needs *some* `X-Sonos-Api-Key` header present (absent → 400).
///
/// ⚠️ Every method that writes is a **live write to the user's real speakers**
/// and is gated behind an explicit `live: true`. Default off — a call without it
/// throws, so nothing writes by accident.
///
/// ⚠️ **An HTTP 200 is not an apply.** The player is a dumb store: wrong channel
/// ids, too many sections or an incoherent session id all return 200 and store
/// nothing, with no error. The only verdict is re-reading
/// `:1400 GetRoomCalibrationStatus` → `RoomCalibrationAvailable`
/// (`room_calibration.dart`). An apply also does **not** enable the tuning; that
/// is a separate `SetRoomCalibrationStatus` call.
///
/// Uses `dart:io` `HttpClient` (the player serves a self-signed cert, server-auth
/// only, so cert verification is bypassed — same as every other `:1443` call).
/// Reached through the `trueplay_apply.dart` barrel so the web/demo build gets a
/// throwing stub instead.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'trueplay_codec.dart';

/// The public Sonos guest api-key — sufficient for Trueplay apply (any
/// `X-Sonos-Api-Key` header qualifies; absent → HTTP 400).
const kSonosGuestApiKey = '123e4567-e89b-12d3-a456-426655440000';

class TrueplayApplyClient {
  final Duration timeout;
  const TrueplayApplyClient({this.timeout = const Duration(seconds: 8)});

  /// POST a pre-encoded config blob for one player. [configId] is `audiocore`
  /// or `trueplay-node`. Returns the HTTP status code. Set [live] true to
  /// actually write.
  Future<int> postConfig({
    required String ip,
    required String rincon,
    required String configId,
    required String encodedBase64,
    String apiKey = kSonosGuestApiKey,
    bool live = false,
  }) async {
    if (!live) {
      throw StateError(
          'Trueplay apply is a live speaker write; pass live: true to enable.');
    }
    return (await _post(
      ip: ip,
      rincon: rincon,
      configId: configId,
      encodedBase64: encodedBase64,
      apiKey: apiKey,
    ))
        .status;
  }

  /// Dispatch a **`GetDeviceConfig`** RPC: the player's own channel vocabulary
  /// (channel ids, sample rate, model, section count) for its CURRENT layout —
  /// what an `ApplySpectralTuning` has to match. This is a READ, so it is
  /// deliberately NOT `live`-gated: it changes nothing. Note a plain `GET` on this path only ever
  /// returns a 14-byte stub — the config comes back in the *response* to this POST.
  ///
  /// [config] is null when the reply isn't the expected JSON+protobuf (then read
  /// [raw]).
  Future<({int status, TrueplayDeviceConfig? config, String raw})>
      readDeviceConfig({
    required String ip,
    required String rincon,
    String apiKey = kSonosGuestApiKey,
  }) async {
    final resp = await _post(
      ip: ip,
      rincon: rincon,
      configId: 'audiocore',
      encodedBase64: buildGetDeviceConfig(rincon).encodeBase64(),
      apiKey: apiKey,
    );
    final raw = utf8.decode(resp.body, allowMalformed: true);
    TrueplayDeviceConfig? config;
    try {
      // The reply is a bare `trueplayConfiguration` object (no `trueplayConfig`
      // wrapper, unlike the request body).
      final map = jsonDecode(raw) as Map;
      final encoded =
          (map['encoded'] ?? (map['trueplayConfig'] as Map?)?['encoded'])!;
      config = decodeDeviceConfig(base64.decode(encoded as String));
    } catch (_) {
      // Not a config reply (error page, stub, other firmware) — `raw` says what.
    }
    return (status: resp.status, config: config, raw: raw);
  }

  Future<({int status, Uint8List body})> _post({
    required String ip,
    required String rincon,
    required String configId,
    required String encodedBase64,
    required String apiKey,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (_, __, ___) => true;
    client.connectionTimeout = timeout;
    try {
      final uri = Uri.parse(
          'https://$ip:1443/api/v1/players/$rincon/trueplay/config/$configId');
      final req = await client.postUrl(uri);
      req.headers.set('X-Sonos-Api-Key', apiKey);
      req.headers.contentType = ContentType.json;
      final body = utf8.encode(jsonEncode({
        'trueplayConfig': {
          'id': configId,
          'encoded': encodedBase64,
          '_objectType': 'trueplayConfiguration',
        }
      }));
      // Set contentLength explicitly: without it Dart's HttpClient sends the
      // body with `Transfer-Encoding: chunked`, and the :1443 API rejects a
      // chunked body with HTTP 499 (hardware-confirmed — the identical request
      // with a fixed Content-Length returns 200). Not an auth problem.
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(timeout);
      final bytes = <int>[];
      await resp.forEach(bytes.addAll).timeout(timeout);
      return (status: resp.statusCode, body: Uint8List.fromList(bytes));
    } finally {
      client.close(force: true);
    }
  }

  /// Apply a spectral tuning to one player (`config/audiocore`).
  Future<int> applySpectral({
    required String ip,
    required String rincon,
    required SpectralTuning tuning,
    bool live = false,
  }) =>
      postConfig(
        ip: ip,
        rincon: rincon,
        configId: 'audiocore',
        encodedBase64: buildApplySpectral(tuning).encodeBase64(),
        live: live,
      );

  /// Clear the stored tuning on one player (flips `RoomCalibrationAvailable`→0).
  Future<int> clearAllTunings({
    required String ip,
    required String rincon,
    bool live = false,
  }) =>
      postConfig(
        ip: ip,
        rincon: rincon,
        configId: 'audiocore',
        encodedBase64: buildClearAllTunings().encodeBase64(),
        live: live,
      );
}
