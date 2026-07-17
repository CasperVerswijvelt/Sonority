import 'dart:math';
import 'dart:typed_data';

/// Generates a short, distinctive "chime" as 16-bit mono PCM WAV bytes.
/// Produced in code so the identify-speaker feature needs no bundled binary
/// asset — we just serve these bytes over a tiny local HTTP server and point a
/// Sonos speaker at the URL.
///
/// The waveform is tuned to be **easy to localize by ear** (tell which physical
/// speaker it's coming from): a short train of repeated percussive plucks, each
/// with a sharp attack + fast decay and rich harmonics. Humans localize sound
/// from onset transients (interaural time differences) and high-frequency
/// content (interaural level differences) — a slow, pure sine tone (the old
/// chime) has neither and is nearly impossible to point at. Sharp attacks,
/// broadband harmonics, and repetition all directly help; a rising arpeggio
/// keeps it pleasant and clearly intentional rather than static-like.
Uint8List generateChimeWav() {
  const sampleRate = 44100;
  // Lead-in/out silence matters: Sonos can clip the first fraction of a second
  // while the amp powers up, and a too-short clip may not render at all.
  const leadSilence = 6615; // ~0.15s
  const pluckSamples = 4900; // ~0.11s per pluck
  const gapSamples = 4410; // ~0.10s of silence between plucks
  const tailSilence = 8820; // ~0.20s
  const attackSamples = 66; // ~1.5ms linear rise — sharp onset, no DC click
  const decayRate = 5.0; // exponential decay over each pluck (e^-5 ≈ 0.007 tail)
  // Ascending A-major arpeggio (A5 C#6 E6 A6): four distinct onsets to localize.
  const freqs = [880.0, 1108.73, 1318.51, 1760.0];
  // Harmonic weights (fundamental + overtones) — the overtones add the
  // high-frequency energy that carries direction. Normalized so peaks stay near
  // the old chime's 0.45 amplitude (the identify volume-bump assumes that).
  const harmonics = [1.0, 0.5, 0.33, 0.25, 0.2];
  final weightSum = harmonics.reduce((a, b) => a + b);

  final total =
      leadSilence + (pluckSamples + gapSamples) * freqs.length + tailSilence;
  final pcm = Int16List(total); // zero-filled = silence

  var idx = leadSilence;
  for (final f in freqs) {
    for (var i = 0; i < pluckSamples; i++) {
      final attack = i < attackSamples ? i / attackSamples : 1.0;
      final decay = exp(-decayRate * i / pluckSamples);
      var wave = 0.0;
      for (var h = 0; h < harmonics.length; h++) {
        wave += harmonics[h] * sin(2 * pi * f * (h + 1) * i / sampleRate);
      }
      final sample = 0.45 * attack * decay * wave / weightSum;
      pcm[idx++] = (sample * 32767).round().clamp(-32768, 32767);
    }
    idx += gapSamples; // silence between plucks (already zero-filled)
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
