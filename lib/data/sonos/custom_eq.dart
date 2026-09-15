/// The EQ curve model: what the sliders mean, and how they become coefficients.
///
/// Pure Dart, no Flutter. This is the one file that knows the shape of the
/// user-facing EQ; everything below it ([fitBiquads] in `trueplay_fit.dart`,
/// the codec, the apply client) is generic.
///
/// **The composition, which is deliberately open at the top:**
///
/// ```
///   final(f) = base(f) + offsets(f)  →  clamp per frequency  →  fitBiquads
///              ↑          ↑
///   a measured correction  the sliders
///   (null today)           (mean-subtracted)
/// ```
///
/// [base] is null while the app has no room-measurement step, so today the
/// sliders *are* the whole curve. When measurement lands it supplies `base` and
/// the identical sliders become a trim on top of it — which is why the clamp
/// lives on the *composed* curve and never on slider travel, and why
/// [composeCorrection] and [sectionsForCorrection] are two functions rather than
/// one. Collapsing them would close that door.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'trueplay_codec.dart';
import 'trueplay_fit.dart';

/// The band centres (Hz) the sliders address — ISO octave centres.
const kEqBands = <double>[63, 125, 250, 500, 1000, 2000, 4000, 8000];

/// Correction limits, applied to the composed curve per frequency. Sonos' own
/// fitter lands inside +5.7 / −11.5 dB on real hardware; boost is the expensive
/// direction (headroom, driver excursion), hence the asymmetry.
const kEqMaxBoostDb = 6.0;
const kEqMaxCutDb = 12.0;

/// The `SW` role reports this rate; every other channel reports 44100. It is the
/// only signal available before an apply that a channel is the band-limited sub
/// output, so it doubles as the "narrow band" discriminator.
const kSubSampleRate = 8138.0;

/// The log-frequency grid corrections are composed and fitted on.
List<double> eqGrid({double lo = 30, double hi = 16000, int n = 96}) =>
    geomspace(lo, hi, n);

/// Are all bands at rest? A flat curve needs no filters at all.
bool isFlat(List<double> bandOffsetsDb) =>
    bandOffsetsDb.every((g) => g.abs() < 0.05);

/// `base + offsets`, clamped per frequency to [kEqMaxBoostDb]/[kEqMaxCutDb].
///
/// [bandOffsetsDb] carries one value per [kEqBands] and is **mean-subtracted**
/// first: a uniform slider move must do nothing. Otherwise it would be a
/// broadband gain — a volume control by another name, which both duplicates the
/// Sonos app and spends headroom for no tonal change. The mean is removed from
/// the *offsets* only, never from the composed curve, because a measured [base]
/// carries a deliberate reference level that has to survive.
Float64List composeCorrection({
  Float64List? base,
  required List<double> bandOffsetsDb,
  required List<double> freqs,
}) {
  assert(bandOffsetsDb.length == kEqBands.length);
  assert(base == null || base.length == freqs.length);

  final mean = bandOffsetsDb.reduce((a, b) => a + b) / bandOffsetsDb.length;
  final g = [for (final v in bandOffsetsDb) v - mean];

  final out = Float64List(freqs.length);
  for (var i = 0; i < freqs.length; i++) {
    out[i] = (base?[i] ?? 0) + _interpLog(freqs[i], g);
    out[i] = out[i].clamp(-kEqMaxCutDb, kEqMaxBoostDb);
  }
  return out;
}

/// Log-linear interpolation of band gains at [f]; held flat outside the band
/// range so the curve doesn't dive to zero below 63 Hz or above 8 kHz.
double _interpLog(double f, List<double> gains) {
  if (f <= kEqBands.first) return gains.first;
  if (f >= kEqBands.last) return gains.last;
  var i = 0;
  while (i < kEqBands.length - 2 && f > kEqBands[i + 1]) {
    i++;
  }
  final t = (math.log(f) - math.log(kEqBands[i])) /
      (math.log(kEqBands[i + 1]) - math.log(kEqBands[i]));
  return gains[i] + (gains[i + 1] - gains[i]) * t;
}

/// A dense dB correction curve → the biquad cascade for ONE channel.
///
/// [fs] is that channel's own reported sample rate — never assume 44100, since
/// the sub runs at [kSubSampleRate] and a filter designed at the wrong rate
/// lands several times off its design frequency. [maxSections] is that player's
/// reported ceiling; more sections than it advertises and the whole apply is
/// silently dropped.
///
/// Returns a single passthrough section for a flat curve — a channel still needs
/// an entry, it just needs one that does nothing.
List<BiquadSos> sectionsForCorrection(
  Float64List correctionDb,
  List<double> freqs, {
  required double fs,
  required int maxSections,
}) {
  assert(correctionDb.length == freqs.length);
  if (maxSections < 1) return const [];

  // A sub reproduces roughly 20–120 Hz, so fitting it against the full curve
  // spends every filter above its passband. Everything else fits its whole
  // range, bounded by a comfortable margin below Nyquist.
  final narrow = fs < 20000;
  final fitHi = math.min(narrow ? 200.0 : 20000.0, 0.4 * fs);

  final f = <double>[], t = <double>[];
  for (var i = 0; i < freqs.length; i++) {
    if (freqs[i] <= fitHi) {
      f.add(freqs[i]);
      t.add(correctionDb[i]);
    }
  }
  if (f.length < 4 || t.every((v) => v.abs() < 0.05)) {
    return const [BiquadSos.passthrough];
  }

  // fitBiquads emits nBands peaking sections plus one low shelf.
  final nBands = math.min(narrow ? 6 : 10, maxSections - 1);
  if (nBands < 1) return const [BiquadSos.passthrough];

  final fit = fitBiquads(
    f,
    t,
    nBands: nBands,
    fs: fs,
    bandLo: narrow ? 25 : 60,
    bandHi: narrow ? 110 : 8000,
  );

  final sections = fit.sections.take(maxSections).toList();
  for (final s in sections) {
    // The player validates nothing: an unstable section is accepted, stored and
    // then run. RBJ sections are stable by construction, so this is an assertion
    // about our own maths, not about input.
    if (!poleModulus(s).isFinite || poleModulus(s) >= 1) {
      throw StateError('custom_eq produced an unstable section: $s');
    }
    if ([s.b0, s.b1, s.b2, s.a1, s.a2].any((c) => !c.isFinite)) {
      throw StateError('custom_eq produced a non-finite section: $s');
    }
  }
  return sections;
}

/// What the cascade actually does, for the preview — so the UI can draw the
/// achieved response against the requested one rather than promising the
/// sliders' shape and delivering something else.
Float64List achievedDb(
        List<BiquadSos> sections, List<double> freqs, double fs) =>
    cascadeMagnitudeDb(sections, freqs, fs);
