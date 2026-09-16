import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/trueplay_codec.dart';

/// Golden encodings, pinned as bytes.
///
/// The encoder used to be checked by decoding its own output, which proves the
/// two halves agree and nothing about whether either matches the wire. A wrong
/// field number or wire type round-trips perfectly and is then rejected by the
/// player with an HTTP 200 and no error. These are the bytes a player accepted.
const _spectral =
    'Cg90cnVlcGxheV9URVNUXzESPQgBFQAAgD8aGQ2kcH0/FWZmZr8dj8J1PiVmZma/LXsUrj4a'
    'GQ0AAIA/FTMz878dMzNzPyUAAMC/LTMzMz8SIggCFQAAgD8aGQ0AAIA/FQAAAAAdAAAAACUA'
    'AAAALQAAAAA=';
const _apply =
    'Cgh2MWFscGhhMhIrc29ub3MuY29yZWF1ZGlvLnRydWVwbGF5LnYxLlRydWVwbGF5U2Vydmlj'
    'ZRoTQXBwbHlTcGVjdHJhbFR1bmluZyJ0Cg90cnVlcGxheV9URVNUXzESPQgBFQAAgD8aGQ2k'
    'cH0/FWZmZr8dj8J1PiVmZma/LXsUrj4aGQ0AAIA/FTMz878dMzNzPyUAAMC/LTMzMz8SIggC'
    'FQAAgD8aGQ0AAIA/FQAAAAAdAAAAACUAAAAALQAAAAA=';
const _clear =
    'Cgh2MWFscGhhMhIrc29ub3MuY29yZWF1ZGlvLnRydWVwbGF5LnYxLlRydWVwbGF5U2Vydmlj'
    'ZRoPQ2xlYXJBbGxUdW5pbmdzIgA=';
const _getConfig =
    'Cgh2MWFscGhhMhIrc29ub3MuY29yZWF1ZGlvLnRydWVwbGF5LnYxLlRydWVwbGF5U2Vydmlj'
    'ZRoPR2V0RGV2aWNlQ29uZmlnIhIKEFJJTkNPTl9URVNUMDE0MDA=';

SpectralTuning _tuning() => SpectralTuning(deviceId: 'trueplay_TEST_1', channels: [
      // The session id is arbitrary *for the codec*, but not on hardware: a
      // member declaring a different session than the rest of the batch is
      // silently dropped.
      ChannelTuning(channel: 1, biquads: const [
        BiquadSos(0.99, -0.9, 0.24, -0.9, 0.34),
        BiquadSos(1.0, -1.9, 0.95, -1.5, 0.7),
      ]),
      ChannelTuning(channel: 2, biquads: const [BiquadSos.passthrough]),
    ]);

void main() {
  group('trueplay codec', () {
    test('the spectral payload encodes to the bytes a player accepts', () {
      expect(base64.encode(encodeSpectralPayload(_tuning())), _spectral);
    });

    test('ApplySpectralTuning wraps it in the expected envelope', () {
      expect(buildApplySpectral(_tuning()).encodeBase64(), _apply);
    });

    test('ClearAllTunings carries an empty payload', () {
      final r = buildClearAllTunings();
      expect(r.method, 'ClearAllTunings');
      expect(r.payload, isEmpty);
      expect(r.encodeBase64(), _clear);
    });

    test('GetDeviceConfig carries just the rincon', () {
      expect(buildGetDeviceConfig('RINCON_TEST01400').encodeBase64(), _getConfig);
    });

    test('encoding is deterministic', () {
      expect(encodeSpectralPayload(_tuning()), encodeSpectralPayload(_tuning()));
    });
  });

  group('decodeDeviceConfig', () {
    // The reply parser is what rules 1, 2 and 4 all read from: wrong channel
    // ids, a wrong sample rate or a wrong section ceiling each produce an
    // HTTP 200 with nothing stored.
    Uint8List reply(List<int> payload) => Uint8List.fromList([
          0x0a, 8, ...utf8.encode(kSonosRpcVersion), // 1: rpcVersion
          0x12, payload.length, ...payload, // 2: DeviceConfig
        ]);

    test('reads channels, per-channel rates, model and the section ceiling', () {
      final cfg = decodeDeviceConfig(reply([
        0x0a, 6, 0x08, 1, 0x18, 0xc4, 0xd8, 0x02, // ch 1 @ 44100
        0x0a, 5, 0x08, 4, 0x18, 0xca, 0x3f, // ch 4 @ 8138 (the sub)
        0x12, 3, ...utf8.encode('S31'), // model
        0x20, 16, // maxSections
      ]));
      expect(cfg.channels, [1, 4]);
      expect(cfg.sampleRates, [44100, 8138]);
      expect(cfg.model, 'S31');
      expect(cfg.maxSections, 16);
    });

    test('skips unknown fields without desyncing the reader', () {
      // Real replies carry fields we do not model. A skip that mis-reads a
      // length-delimited field shifts everything after it, silently.
      final cfg = decodeDeviceConfig(reply([
        0x2a, 4, 0xde, 0xad, 0xbe, 0xef, // unknown field 5, length-delimited
        0x0a, 6, 0x08, 13, 0x18, 0xc4, 0xd8, 0x02, // ch 13 @ 44100
        0x35, 0x00, 0x00, 0x80, 0x3f, // unknown field 6, fixed32
        0x20, 16,
      ]));
      expect(cfg.channels, [13]);
      expect(cfg.sampleRates, [44100]);
      expect(cfg.maxSections, 16);
    });
  });
}
