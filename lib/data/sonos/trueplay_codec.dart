/// Pure-Dart codec for the Sonos spectral-tuning **apply** blob — the base64 that
/// goes in `trueplayConfig.encoded` of a `POST …:1443/…/trueplay/config/audiocore`.
///
/// The blob is a nanopb-serialized **`audiocorerpc.Request`** envelope wrapping a
/// `sonos.coreaudio.trueplay.v1.TrueplayService` RPC:
///
///   Request { 1:rpcVersion "v1alpha2", 2:service, 3:method, 4:payload(bytes) }
///   ApplySpectralTuningRequest (payload) {
///     1:deviceId string,
///     2:repeated ChannelTuning { 1:channel uint, 2:gain float,
///                                3:repeated Biquad { 1..5 float [b0,b1,b2,a1,a2] } }
///   }
///
/// Only three protobuf wire types appear (varint, fixed32, length-delimited), so
/// this hand-rolls a tiny reader/writer rather than pull in a protobuf dep. The
/// codec is lossless and byte-deterministic — decode→encode reproduces the input
/// byte-identically, which the tests assert.
library;

import 'dart:convert';
import 'dart:typed_data';

const kSonosTrueplayService = 'sonos.coreaudio.trueplay.v1.TrueplayService';
const kSonosRpcVersion = 'v1alpha2';

/// One second-order section: `[b0,b1,b2,a1,a2]`, a0 normalised to 1.
class BiquadSos {
  final double b0, b1, b2, a1, a2;
  const BiquadSos(this.b0, this.b1, this.b2, this.a1, this.a2);

  /// Unity passthrough (no correction).
  static const passthrough = BiquadSos(1, 0, 0, 0, 0);
}

/// Per-channel spectral tuning: a channel index, a scalar gain, and the biquad
/// cascade that shapes that channel.
class ChannelTuning {
  final int channel;
  final double gain;
  final List<BiquadSos> biquads;
  const ChannelTuning(
      {required this.channel, this.gain = 1.0, required this.biquads});
}

/// A decoded `ApplySpectralTuning` request: the tuning id + one entry per channel.
class SpectralTuning {
  final String deviceId;
  final List<ChannelTuning> channels;
  const SpectralTuning({required this.deviceId, required this.channels});
}

/// The `audiocorerpc.Request` envelope. [method] selects the RPC
/// (`ApplySpectralTuning`, `ClearAllTunings`, …); [payload] is the inner
/// serialized message (opaque at this level).
class TrueplayRequest {
  final String rpcVersion;
  final String service;
  final String method;
  final Uint8List payload;
  const TrueplayRequest({
    this.rpcVersion = kSonosRpcVersion,
    this.service = kSonosTrueplayService,
    required this.method,
    required this.payload,
  });

  Uint8List encode() {
    final w = _PbWriter()
      ..string(1, rpcVersion)
      ..string(2, service)
      ..string(3, method)
      ..lengthDelimited(4, payload);
    return w.toBytes();
  }

  String encodeBase64() => base64.encode(encode());

  static TrueplayRequest decode(Uint8List bytes) {
    String rpcVersion = '', service = '', method = '';
    Uint8List payload = Uint8List(0);
    final r = _PbReader(bytes);
    while (!r.eof) {
      final (field, wire) = r.tag();
      // Guard on wire type: a `trueplay-node` doc reuses these field numbers with
      // different wire types, so only read fields that match the envelope schema.
      if (field == 1 && wire == 2) {
        rpcVersion = r.string();
      } else if (field == 2 && wire == 2) {
        service = r.string();
      } else if (field == 3 && wire == 2) {
        method = r.string();
      } else if (field == 4 && wire == 2) {
        payload = r.bytesValue();
      } else {
        r.skip(wire);
      }
    }
    return TrueplayRequest(
        rpcVersion: rpcVersion,
        service: service,
        method: method,
        payload: payload);
  }
}

/// Encode an `ApplySpectralTuning` payload (the inner message, not the envelope).
Uint8List encodeSpectralPayload(SpectralTuning t) {
  final w = _PbWriter()..string(1, t.deviceId);
  for (final ch in t.channels) {
    final cw = _PbWriter()
      ..varint(1, ch.channel)
      ..fixed32Float(2, ch.gain);
    for (final b in ch.biquads) {
      final bw = _PbWriter()
        ..fixed32Float(1, b.b0)
        ..fixed32Float(2, b.b1)
        ..fixed32Float(3, b.b2)
        ..fixed32Float(4, b.a1)
        ..fixed32Float(5, b.a2);
      cw.lengthDelimited(3, bw.toBytes());
    }
    w.lengthDelimited(2, cw.toBytes());
  }
  return w.toBytes();
}

/// Decode an `ApplySpectralTuning` payload.
SpectralTuning decodeSpectralPayload(Uint8List payload) {
  String deviceId = '';
  final channels = <ChannelTuning>[];
  final r = _PbReader(payload);
  while (!r.eof) {
    final (field, wire) = r.tag();
    switch (field) {
      case 1:
        deviceId = r.string();
      case 2:
        channels.add(_decodeChannel(r.bytesValue()));
      default:
        r.skip(wire);
    }
  }
  return SpectralTuning(deviceId: deviceId, channels: channels);
}

ChannelTuning _decodeChannel(Uint8List bytes) {
  int channel = 0;
  double gain = 1.0;
  final biquads = <BiquadSos>[];
  final r = _PbReader(bytes);
  while (!r.eof) {
    final (field, wire) = r.tag();
    switch (field) {
      case 1:
        channel = r.varintValue();
      case 2:
        gain = r.fixed32Float();
      case 3:
        biquads.add(_decodeBiquad(r.bytesValue()));
      default:
        r.skip(wire);
    }
  }
  return ChannelTuning(channel: channel, gain: gain, biquads: biquads);
}

BiquadSos _decodeBiquad(Uint8List bytes) {
  final f = List<double>.filled(5, 0);
  final r = _PbReader(bytes);
  while (!r.eof) {
    final (field, wire) = r.tag();
    if (field >= 1 && field <= 5 && wire == 5) {
      f[field - 1] = r.fixed32Float();
    } else {
      r.skip(wire);
    }
  }
  return BiquadSos(f[0], f[1], f[2], f[3], f[4]);
}

/// Build a ready-to-POST `ApplySpectralTuning` envelope for one player.
TrueplayRequest buildApplySpectral(SpectralTuning t) => TrueplayRequest(
    method: 'ApplySpectralTuning', payload: encodeSpectralPayload(t));

/// Build the `ClearAllTunings` envelope (empty inner message) — flips a stored
/// tuning's `RoomCalibrationAvailable` 1→0 (hardware-confirmed).
TrueplayRequest buildClearAllTunings() =>
    TrueplayRequest(method: 'ClearAllTunings', payload: Uint8List(0));

/// Build the `GetDeviceConfig` envelope — a READ (the first thing the iOS app
/// POSTs, once per player: payload = `1:<rincon>`).
/// The response carries that player's channel vocabulary for its current layout.
TrueplayRequest buildGetDeviceConfig(String rincon) => TrueplayRequest(
    method: 'GetDeviceConfig',
    payload: (_PbWriter()..string(1, rincon)).toBytes());

/// A player's own answer to "which channels can be tuned, and how" — the reply to
/// [buildGetDeviceConfig]. **This is the authority on the shape of an
/// `ApplySpectralTuning`**: the channel ids are NOT 1-based per device, they are
/// allocated across the player's current layout (hardware-confirmed: a Beam
/// coordinator reports 1,2,3; its `LR` Play:1 satellite reports 5; a standalone
/// One SL reports 13 — the ids track the channel ROLE the bond assigns,
/// for that player). Inventing ids is the known way to get a 200 that stores
/// nothing.
///
/// Wire shape (`2 { 1 { 1:channel 2:? 3:sampleRate … } … 2:model 3:? 4:maxSections }`).
class TrueplayDeviceConfig {
  /// Tunable channel ids, in the order the player lists them.
  final List<int> channels;

  /// Sample rate per channel. 44100 for every audio channel, but the `SW`
  /// (sub) role reports **8138** — never assume, always use the reported value,
  /// or a filter lands several times off its design frequency.
  final List<double> sampleRates;

  /// Sonos internal model code (`S22` One SL, `S31` Beam, `S1` Play:1). Reported
  /// but not currently used — the correction limits we apply are model-neutral.
  final String model;

  /// Biquad sections per channel the player advertises (16 everywhere so far; the
  /// a Sub may report fewer, so treat it as a maximum).
  final int maxSections;

  const TrueplayDeviceConfig({
    required this.channels,
    required this.sampleRates,
    required this.model,
    required this.maxSections,
  });
}

/// Decode a `GetDeviceConfig` reply blob (`1:rpcVersion 2:DeviceConfig`) — the
/// base64 of the reply's `trueplayConfig.encoded`. Unknown fields are skipped, so
/// a firmware that adds some still parses.
TrueplayDeviceConfig decodeDeviceConfig(Uint8List reply) {
  var payload = Uint8List(0);
  final outer = _PbReader(reply);
  while (!outer.eof) {
    final (field, wire) = outer.tag();
    if (field == 2 && wire == 2) {
      payload = outer.bytesValue();
    } else {
      outer.skip(wire);
    }
  }
  final channels = <int>[];
  final rates = <double>[];
  var model = '';
  var sections = 0;
  final r = _PbReader(payload);
  while (!r.eof) {
    final (field, wire) = r.tag();
    switch (field) {
      case 1 when wire == 2:
        final c = _PbReader(r.bytesValue());
        var ch = -1;
        var rate = 0.0;
        while (!c.eof) {
          final (f, w) = c.tag();
          if (f == 1 && w == 0) {
            ch = c.varintValue();
          } else if (f == 3 && w == 0) {
            rate = c.varintValue().toDouble();
          } else {
            c.skip(w);
          }
        }
        if (ch >= 0) {
          channels.add(ch);
          rates.add(rate);
        }
      case 2 when wire == 2:
        model = r.string();
      case 4 when wire == 0:
        sections = r.varintValue();
      default:
        r.skip(wire);
    }
  }
  return TrueplayDeviceConfig(
      channels: channels,
      sampleRates: rates,
      model: model,
      maxSections: sections);
}

// --------------------------------------------------------------------------
// Minimal protobuf reader/writer (varint, fixed32, length-delimited only).
// --------------------------------------------------------------------------

class _PbWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void _raw(int v) {
    // unsigned LEB128 varint
    while (v >= 0x80) {
      _b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _b.addByte(v);
  }

  void _tag(int field, int wire) => _raw(field << 3 | wire);

  void varint(int field, int value) {
    _tag(field, 0);
    _raw(value);
  }

  void fixed32Float(int field, double value) {
    _tag(field, 5);
    final bd = ByteData(4)..setFloat32(0, value, Endian.little);
    _b.add(bd.buffer.asUint8List());
  }

  void lengthDelimited(int field, List<int> value) {
    _tag(field, 2);
    _raw(value.length);
    _b.add(value);
  }

  void string(int field, String value) =>
      lengthDelimited(field, utf8.encode(value));

  Uint8List toBytes() => _b.toBytes();
}

class _PbReader {
  final Uint8List d;
  int p = 0;
  _PbReader(this.d);

  bool get eof => p >= d.length;

  int _raw() {
    int shift = 0, result = 0;
    while (true) {
      final b = d[p++];
      result |= (b & 0x7f) << shift;
      if (b < 0x80) return result;
      shift += 7;
    }
  }

  (int, int) tag() {
    final t = _raw();
    return (t >> 3, t & 0x7);
  }

  int varintValue() => _raw();

  double fixed32Float() {
    final v = ByteData.sublistView(d, p, p + 4).getFloat32(0, Endian.little);
    p += 4;
    return v;
  }

  Uint8List bytesValue() {
    final len = _raw();
    final out = Uint8List.sublistView(d, p, p + len);
    p += len;
    return out;
  }

  String string() => utf8.decode(bytesValue());

  void skip(int wire) {
    switch (wire) {
      case 0:
        _raw();
      case 5:
        p += 4;
      case 1:
        p += 8;
      case 2:
        // NB `p += _raw()` would be WRONG: Dart reads `p` BEFORE evaluating the
        // right-hand side, so the length prefix's own bytes get un-counted and
        // the reader lands one byte short (it silently mis-parsed every skipped
        // length-delimited field).
        final len = _raw();
        p += len;
      default:
        throw FormatException('unsupported wire type $wire');
    }
  }
}
