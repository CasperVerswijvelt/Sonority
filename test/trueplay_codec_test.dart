import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/trueplay_codec.dart';

void main() {
  group('trueplay codec', () {
    test('envelope encode/decode round-trips losslessly', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final req = TrueplayRequest(method: 'ApplySpectralTuning', payload: payload);
      final decoded = TrueplayRequest.decode(req.encode());
      expect(decoded.rpcVersion, kSonosRpcVersion);
      expect(decoded.service, kSonosTrueplayService);
      expect(decoded.method, 'ApplySpectralTuning');
      expect(decoded.payload, payload);
      // re-encode is byte-identical (deterministic)
      expect(decoded.encode(), req.encode());
    });

    test('spectral payload encode/decode preserves channels and coeffs', () {
      // An arbitrary deviceId is fine *for the codec* — it round-trips any
      // string. It is NOT arbitrary on hardware: the id is a tuning-session id
      // and a doc declaring a different session than the rest of the applied
      // set is silently dropped.
      final t = SpectralTuning(deviceId: 'trueplay_TEST_1', channels: [
        ChannelTuning(channel: 1, gain: 1.0, biquads: const [
          BiquadSos(0.99, -0.9, 0.24, -0.9, 0.34),
          BiquadSos(1.0, -1.9, 0.95, -1.5, 0.7),
        ]),
        ChannelTuning(channel: 2, gain: 1.0, biquads: const [
          BiquadSos.passthrough,
        ]),
      ]);
      final bytes = encodeSpectralPayload(t);
      final back = decodeSpectralPayload(bytes);
      expect(back.deviceId, t.deviceId);
      expect(back.channels.length, 2);
      expect(back.channels[0].channel, 1);
      expect(back.channels[0].biquads.length, 2);
      // float32 values survive the round-trip exactly (they originate as f32)
      final b = back.channels[0].biquads[0];
      final o = t.channels[0].biquads[0];
      expect(b.b0, closeTo(o.b0, 1e-6));
      expect(b.a2, closeTo(o.a2, 1e-6));
      // re-encode identical
      expect(encodeSpectralPayload(back), bytes);
    });

    test('ClearAllTunings has an empty payload', () {
      final r = buildClearAllTunings();
      expect(r.method, 'ClearAllTunings');
      expect(r.payload.length, 0);
      final d = TrueplayRequest.decode(r.encode());
      expect(d.method, 'ClearAllTunings');
      expect(d.payload.length, 0);
    });

  });
}
