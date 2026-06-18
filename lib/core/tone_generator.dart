import 'dart:math';
import 'dart:typed_data';

/// Generates a short, distinctive two-tone "chime" as 16-bit mono PCM WAV
/// bytes. Produced in code so the identify-speaker feature needs no bundled
/// binary asset — we just serve these bytes over a tiny local HTTP server and
/// point a Sonos speaker at the URL.
Uint8List generateChimeWav() {
  const sampleRate = 44100;
  // Lead-in/out silence matters: Sonos can clip the first fraction of a second
  // while the amp powers up, and a too-short clip may not render at all.
  const leadSilence = 6615; // ~0.15s
  const segSamples = 19845; // ~0.45s per tone
  const tailSilence = 8820; // ~0.20s
  const freqs = [880.0, 1318.5]; // A5 then E6 — a pleasant rising ding-dong
  final total = leadSilence + segSamples * freqs.length + tailSilence;
  final pcm = Int16List(total); // zero-filled = silence

  var idx = leadSilence;
  for (final f in freqs) {
    for (var i = 0; i < segSamples; i++) {
      // Half-sine envelope so each tone fades in/out without clicks.
      final env = sin(pi * i / segSamples);
      final sample = 0.45 * env * sin(2 * pi * f * i / sampleRate);
      pcm[idx++] = (sample * 32767).round().clamp(-32768, 32767);
    }
  }
  return _wrapWavMono16(pcm, sampleRate);
}

Uint8List _wrapWavMono16(Int16List pcm, int sampleRate) {
  final dataSize = pcm.length * 2;
  final buffer = ByteData(44 + dataSize);

  void setStr(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  setStr(0, 'RIFF');
  buffer.setUint32(4, 36 + dataSize, Endian.little);
  setStr(8, 'WAVE');
  setStr(12, 'fmt ');
  buffer.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  buffer.setUint16(20, 1, Endian.little); // AudioFormat = PCM
  buffer.setUint16(22, 1, Endian.little); // mono
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate (mono 16-bit)
  buffer.setUint16(32, 2, Endian.little); // block align
  buffer.setUint16(34, 16, Endian.little); // bits per sample
  setStr(36, 'data');
  buffer.setUint32(40, dataSize, Endian.little);

  var off = 44;
  for (final s in pcm) {
    buffer.setInt16(off, s, Endian.little);
    off += 2;
  }
  return buffer.buffer.asUint8List();
}
