import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/trueplay_codec.dart';
import 'package:sonority/data/sonos/trueplay_fit.dart';

void main() {
  group('fitBiquads', () {
    test('a known biquad cascade is refit within tight tolerance', () {
      const fs = 44100.0;
      // A target built from real biquads: two peaks + a bass cut.
      final target = <BiquadSos>[
        rbjPeaking(120, 1.2, 4.0, fs),
        rbjPeaking(1500, 2.0, -5.0, fs),
        rbjLowShelf(60, -8.0, fs),
      ];
      final freqs = geomspace(30, 12000, 200);
      final targetDb = cascadeMagnitudeDb(target, freqs, fs);

      final fit = fitBiquads(freqs, targetDb.toList(), fs: fs);
      // The fitter reproduces the magnitude response, not the exact coeffs.
      expect(fit.rmsDb, lessThan(1.0),
          reason: 'RMS ${fit.rmsDb} dB should be < 1 dB');
      expect(fit.maxAbsDb, lessThan(3.0));
      expect(fit.sections, isNotEmpty);
    });

    test('a band-limited sub target fits with bands packed into its passband',
        () {
      const fs = 44100.0;
      // A sub-shaped target: a room mode at 45 Hz and a dip at 90 Hz.
      final target = <BiquadSos>[
        rbjPeaking(45, 2.0, 7.0, fs),
        rbjPeaking(90, 1.5, -5.0, fs),
        rbjLowShelf(35, 3.0, fs),
      ];
      final freqs = geomspace(20, 120, 60);
      final targetDb = cascadeMagnitudeDb(target, freqs, fs).toList();

      // highShelf: false — a sub has no top end to shelve.
      final fit = fitBiquads(freqs, targetDb,
          fs: fs, nBands: 6, bandLo: 25, bandHi: 110, highShelf: false);
      expect(fit.sections.length, 7); // 6 bands + the low shelf
      expect(fit.rmsDb, lessThan(0.4),
          reason: 'sub-band RMS ${fit.rmsDb} dB, max ${fit.maxAbsDb} dB');
      expect(fit.maxAbsDb, lessThan(1.0));

      // The default 60–8000 Hz placement can't do this: only 2 of its 10 bands
      // land inside the target's band at all.
      final wide =
          fitBiquads(freqs, targetDb, fs: fs, nBands: 6, highShelf: false);
      expect(fit.rmsDb * 4, lessThan(wide.rmsDb),
          reason: 'band-limited ${fit.rmsDb} dB should beat the default '
              '60–8000 Hz placement (${wide.rmsDb} dB) by a wide margin');
    });



    test('an explicit centers list overrides nBands/bandLo/bandHi', () {
      const fs = 44100.0;
      final freqs = geomspace(30, 12000, 100);
      final targetDb = List<double>.filled(freqs.length, 0.0);
      final fit = fitBiquads(freqs, targetDb,
          fs: fs, nBands: 10, centers: [50, 100, 200]);
      expect(fit.sections.length, 5); // 3 centres + a shelf at each end
      expect(
          fitBiquads(freqs, targetDb,
                  fs: fs, centers: [50, 100, 200], highShelf: false)
              .sections
              .length,
          4);
    });

    test('a high shelf is what makes the topmost band reachable', () {
      // Peaking filters only make bumps, so without a shelf above the last
      // centre the cascade cannot hold a correction out to Nyquist. This is the
      // regression that made the 16 kHz band ~25% effective.
      const fs = 44100.0;
      final freqs = geomspace(1000, 20000, 80);
      // Ask for +6 dB across the whole top end.
      final targetDb = List<double>.filled(freqs.length, 6.0);

      final withShelf = fitBiquads(freqs, targetDb,
          fs: fs, centers: [2000, 4000, 8000], highShelf: true);
      final without = fitBiquads(freqs, targetDb,
          fs: fs, centers: [2000, 4000, 8000], highShelf: false);

      final got = cascadeMagnitudeDb(withShelf.sections, [16000], fs)[0];
      expect(got, closeTo(6, 1.0), reason: 'with a high shelf: $got dB');
      expect(withShelf.rmsDb * 2, lessThan(without.rmsDb),
          reason: 'shelf ${withShelf.rmsDb} dB vs none ${without.rmsDb} dB');
    });

    test('a flat target fits near 0 dB', () {
      const fs = 44100.0;
      final freqs = geomspace(30, 12000, 150);
      final targetDb = List<double>.filled(freqs.length, 0.0);
      final fit = fitBiquads(freqs, targetDb, fs: fs);
      expect(fit.rmsDb, lessThan(0.5));
    });

    // Hardware finding (2026-08-05): the speaker performs NO coefficient
    // validation — it accepted and stored a section with poles at |p| = 1.5.
    // So stability is entirely our responsibility, and the fitter is the one
    // place that can guarantee it for every tuning we ever author.
    test('every fitted section is stable, even for extreme targets', () {
      const fs = 44100.0;
      final freqs = geomspace(30, 12000, 200);
      // Deliberately nasty: deep narrow notch, big boost, and a steep tilt —
      // the shapes most likely to push the bounded solver somewhere silly.
      for (final target in <List<double>>[
        cascadeMagnitudeDb([
          rbjPeaking(1000, 6.0, -24, fs),
          rbjPeaking(120, 5.0, 18, fs),
        ], freqs, fs).toList(),
        [for (final f in freqs) 12 - 24 * (math.log(f / 30) / math.log(400))],
        List<double>.filled(freqs.length, -30),
      ]) {
        for (final nBands in [6, 10]) {
          final fit = fitBiquads(freqs, target, fs: fs, nBands: nBands);
          for (final s in fit.sections) {
            expect(poleModulus(s), lessThan(1.0),
                reason: 'unstable section $s from nBands=$nBands — the speaker '
                    'would store this happily; we must never emit it');
            expect(s.b0.isFinite && s.b1.isFinite && s.b2.isFinite, isTrue);
            expect(s.a1.isFinite && s.a2.isFinite, isTrue);
          }
        }
      }
    });
  });
}
