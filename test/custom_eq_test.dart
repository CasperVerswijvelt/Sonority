import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/custom_eq.dart';
import 'package:sonority/data/sonos/trueplay_fit.dart';

/// dB of the composed+fitted cascade at [f], as a speaker would render it.
double achievedAt(List<double> offsets, double f,
    {double fs = 44100, int maxSections = 16}) {
  final grid = eqGrid();
  final corr = composeCorrection(bandOffsetsDb: offsets, freqs: grid);
  final sections =
      sectionsForCorrection(corr, grid, fs: fs, maxSections: maxSections);
  return cascadeMagnitudeDb(sections, [f], fs)[0];
}

void main() {
  group('composeCorrection', () {
    test('a uniform slider move changes nothing', () {
      final grid = eqGrid();
      final flat = composeCorrection(bandOffsetsDb: flatCurve(), freqs: grid);
      final lifted = composeCorrection(
          bandOffsetsDb: List.filled(kEqBands.length, 4.0), freqs: grid);
      for (var i = 0; i < grid.length; i++) {
        expect(lifted[i], closeTo(flat[i], 1e-9),
            reason: 'a uniform move is a volume change, not a tonal one');
      }
    });

    test('band gains land at their own centre frequencies', () {
      final grid = eqGrid();
      final o = flatCurve()..[5] = 6; // 1 kHz
      final corr = composeCorrection(bandOffsetsDb: o, freqs: grid);
      final at1k = corr[_nearest(grid, 1000)];
      final at63 = corr[_nearest(grid, 63)];
      expect(at1k, greaterThan(at63 + 4),
          reason: '1 kHz should be lifted relative to the untouched bands');
    });

    test('held flat below the first band and above the last', () {
      final grid = eqGrid(lo: 20, hi: 20000);
      final o = flatCurve()
        ..[0] = -6 // lowest band
        ..[kEqBands.length - 1] = 2; // highest band
      final corr = composeCorrection(bandOffsetsDb: o, freqs: grid);
      final mean = (-6 + 2) / kEqBands.length;
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] <= kEqBands.first) {
          expect(corr[i], closeTo(-6 - mean, 1e-9), reason: '${grid[i]} Hz');
        }
        if (grid[i] >= kEqBands.last) {
          expect(corr[i], closeTo(2 - mean, 1e-9), reason: '${grid[i]} Hz');
        }
      }
    });

    test('smoothing never overshoots the bands it interpolates', () {
      // The whole reason for a MONOTONE spline: a natural cubic would ring
      // between control points and invent a boost the user never asked for —
      // which would then be faithfully fitted and sent to a speaker.
      final grid = eqGrid();
      final o = flatCurve()
        ..[4] = -10 // 500 Hz
        ..[5] = 8; // 1 kHz  (a deliberately brutal step)
      final corr = composeCorrection(bandOffsetsDb: o, freqs: grid);
      final mean = (-10 + 8) / kEqBands.length;
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] < kEqBands[4] || grid[i] > kEqBands[5]) continue;
        expect(corr[i], lessThanOrEqualTo(8 - mean + 1e-9));
        expect(corr[i], greaterThanOrEqualTo(-10 - mean - 1e-9));
      }
    });

    test('the composed curve is clamped, per frequency', () {
      final grid = eqGrid();
      // Alternating extremes: after mean-removal these still exceed the rails.
      final o = [for (var i = 0; i < kEqBands.length; i++) i.isEven ? 60.0 : -60.0];
      final corr = composeCorrection(bandOffsetsDb: o, freqs: grid);
      for (final v in corr) {
        expect(v, lessThanOrEqualTo(kEqMaxBoostDb + 1e-9));
        expect(v, greaterThanOrEqualTo(-kEqMaxCutDb - 1e-9));
      }
    });
  });

  // The guard on the future path: a room measurement supplies `base`, and the
  // sliders become a trim on top of it. These fail if someone collapses
  // composeCorrection and sectionsForCorrection into one slider-only function.
  group('the measurement seam (base curve)', () {
    test('zero offsets reproduce the base exactly', () {
      final grid = eqGrid();
      final base = _syntheticBase(grid);
      final corr =
          composeCorrection(base: base, bandOffsetsDb: flatCurve(), freqs: grid);
      for (var i = 0; i < grid.length; i++) {
        expect(corr[i], closeTo(base[i], 1e-9));
      }
    });

    test('offsets add on top of the base', () {
      final grid = eqGrid();
      final base = _syntheticBase(grid);
      final o = flatCurve()..[5] = 3; // 1 kHz
      final corr = composeCorrection(base: base, bandOffsetsDb: o, freqs: grid);
      final i = _nearest(grid, 1000);
      expect(corr[i], greaterThan(base[i] + 1));
    });

    test('the clamp fires on the COMPOSED curve, not on slider travel', () {
      final grid = eqGrid();
      // A base already pinned at the cut rail, plus a further cut.
      final base = Float64List.fromList(
          List<double>.filled(grid.length, -kEqMaxCutDb));
      final o = flatCurve()..[5] = -6;
      final corr = composeCorrection(base: base, bandOffsetsDb: o, freqs: grid);
      expect(corr[_nearest(grid, 1000)], closeTo(-kEqMaxCutDb, 1e-9),
          reason: 'must stay at the rail, not reach -18 dB');
    });

    test('a uniform offset move still changes nothing over a base', () {
      final grid = eqGrid();
      final base = _syntheticBase(grid);
      final a = composeCorrection(
          base: base, bandOffsetsDb: flatCurve(), freqs: grid);
      final b = composeCorrection(
          base: base,
          bandOffsetsDb: List.filled(kEqBands.length, -5.0),
          freqs: grid);
      for (var i = 0; i < grid.length; i++) {
        expect(b[i], closeTo(a[i], 1e-9));
      }
    });
  });

  group('sectionsForCorrection', () {
    test('a flat curve becomes a single passthrough section', () {
      final grid = eqGrid();
      final corr = composeCorrection(bandOffsetsDb: flatCurve(), freqs: grid);
      final s = sectionsForCorrection(corr, grid, fs: 44100, maxSections: 16);
      expect(s, hasLength(1));
      expect(cascadeMagnitudeDb(s, [100, 1000, 5000], 44100).map((v) => v.abs()),
          everyElement(lessThan(0.01)));
    });

    test('the achieved response tracks what was asked for', () {
      // A cut at 1 kHz and a lift at 125 Hz, checked where they were drawn.
      final o = flatCurve()
        ..[2] = 5 // 125 Hz
        ..[5] = -8; // 1 kHz
      final grid = eqGrid();
      final corr = composeCorrection(bandOffsetsDb: o, freqs: grid);
      final want = corr[_nearest(grid, 1000)];
      expect(achievedAt(o, 1000), closeTo(want, 1.5));
      expect(achievedAt(o, 125), closeTo(corr[_nearest(grid, 125)], 1.5));
    });

    test('never exceeds the player-reported section ceiling', () {
      final grid = eqGrid();
      final corr =
          composeCorrection(bandOffsetsDb: flatCurve()..[4] = -9, freqs: grid);
      for (final max in [1, 4, 8, 11, 16]) {
        final s =
            sectionsForCorrection(corr, grid, fs: 44100, maxSections: max);
        expect(s.length, lessThanOrEqualTo(max), reason: 'ceiling $max');
        expect(s, isNotEmpty);
      }
    });

    test('a sub channel is fitted at its own rate, inside its own band', () {
      final grid = eqGrid();
      // 63 Hz — index 1 now that the band list starts at 31.5 Hz.
      final corr =
          composeCorrection(bandOffsetsDb: flatCurve()..[1] = -9, freqs: grid);
      final sub =
          sectionsForCorrection(corr, grid, fs: kSubSampleRate, maxSections: 8);
      expect(sub, isNotEmpty);
      expect(sub.length, lessThanOrEqualTo(8));
      // The 63 Hz cut must actually be a cut when rendered at 8138 Hz. Designing
      // it at 44100 would put it ~5x off and leave 63 Hz untouched.
      expect(cascadeMagnitudeDb(sub, [63], kSubSampleRate)[0], lessThan(-2));
    });

    test('every emitted section is stable and finite, at the rails', () {
      final grid = eqGrid();
      for (final shape in [
        [for (var i = 0; i < kEqBands.length; i++) i.isEven ? 60.0 : -60.0],
        List.filled(kEqBands.length, -60.0)..[0] = 60,
        flatCurve()..[kEqBands.length - 1] = 60,
      ]) {
        final corr = composeCorrection(bandOffsetsDb: shape, freqs: grid);
        for (final fs in [44100.0, kSubSampleRate]) {
          final s =
              sectionsForCorrection(corr, grid, fs: fs, maxSections: 16);
          for (final sec in s) {
            expect(poleModulus(sec), lessThan(1));
            expect([sec.b0, sec.b1, sec.b2, sec.a1, sec.a2],
                everyElement(predicate<double>((c) => c.isFinite)));
          }
        }
      }
    });
  });
}

int _nearest(List<double> grid, double f) {
  var best = 0;
  for (var i = 1; i < grid.length; i++) {
    if ((grid[i] - f).abs() < (grid[best] - f).abs()) best = i;
  }
  return best;
}

/// Stands in for a measured room correction: a low-frequency cut that decays.
Float64List _syntheticBase(List<double> freqs) => Float64List.fromList([
      for (final f in freqs) -6 * math.exp(-math.pow(math.log(f / 55), 2) / 0.5)
    ]);
