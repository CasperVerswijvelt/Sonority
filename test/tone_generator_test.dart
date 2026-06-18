import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/core/tone_generator.dart';

void main() {
  test('produces a valid 16-bit mono PCM WAV', () {
    final wav = generateChimeWav();

    String tag(int off) => String.fromCharCodes(wav.sublist(off, off + 4));
    final bd = ByteData.sublistView(wav);

    expect(tag(0), 'RIFF');
    expect(tag(8), 'WAVE');
    expect(tag(12), 'fmt ');
    expect(tag(36), 'data');

    expect(bd.getUint16(20, Endian.little), 1, reason: 'PCM');
    expect(bd.getUint16(22, Endian.little), 1, reason: 'mono');
    expect(bd.getUint32(24, Endian.little), 44100, reason: 'sample rate');
    expect(bd.getUint16(34, Endian.little), 16, reason: 'bits per sample');

    final dataSize = bd.getUint32(40, Endian.little);
    expect(wav.length, 44 + dataSize, reason: 'header + declared data size');
    expect(bd.getUint32(4, Endian.little), 36 + dataSize, reason: 'RIFF size');
  });
}
