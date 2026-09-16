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

import 'sonority_error.dart';
import 'trueplay_codec.dart';
import 'trueplay_fit.dart';

/// Re-exported so a caller drawing the achieved response against the requested
/// one needs a single import.
export 'trueplay_fit.dart' show cascadeMagnitudeDb;

/// The band centres (Hz) the sliders address — ISO octave centres.
///
/// Ten rather than eight: stopping at 63 Hz leaves the entire sub range
/// uncontrollable on a home theater with a bonded Sub (which reproduces roughly
/// 20–120 Hz), and stopping at 8 kHz gives up the "air" band. Both ends are
/// where a room most often needs help. Ten peaking filters plus a shelf is still
/// comfortably inside the 16-section ceiling every player reports.
const kEqBands = <double>[31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

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

/// A curve with every band at rest.
List<double> flatCurve() => List<double>.filled(kEqBands.length, 0);

/// A band centre as the UI writes it: "63", "1k". Shared by the sliders and the
/// plot's axis so the two can't label the same band differently.
String eqBandLabel(double f) =>
    f >= 1000 ? '${(f / 1000).toStringAsFixed(0)}k' : f.toStringAsFixed(0);

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

/// Monotone cubic (Fritsch-Carlson) interpolation of the band gains at [f], in
/// LOG frequency. Held flat outside the band range so the curve doesn't dive to
/// zero below the lowest band or above the highest.
///
/// Monotone rather than natural cubic on purpose: a natural spline overshoots
/// between control points, which would invent a boost the user never asked for —
/// and then faithfully fit and apply it. Fritsch-Carlson limits the tangents so
/// the curve can never leave the interval its neighbouring bands define, which
/// is the property that makes it safe to send to a speaker. Linear interpolation
/// is also safe but reads as a set of kinks rather than a response curve.
double _interpLog(double f, List<double> gains) {
  if (f <= kEqBands.first) return gains.first;
  if (f >= kEqBands.last) return gains.last;

  final n = kEqBands.length;
  var i = 0;
  while (i < n - 2 && f > kEqBands[i + 1]) {
    i++;
  }
  final x0 = math.log(kEqBands[i]), x1 = math.log(kEqBands[i + 1]);
  final h = x1 - x0;
  final y0 = gains[i], y1 = gains[i + 1];

  // Secant slopes either side of each knot, in log-f.
  double slope(int k) => k < 0 || k >= n - 1
      ? 0
      : (gains[k + 1] - gains[k]) /
          (math.log(kEqBands[k + 1]) - math.log(kEqBands[k]));
  final dPrev = slope(i - 1), d = slope(i), dNext = slope(i + 1);

  // Fritsch-Carlson tangents: zero at a local extremum (so the curve flattens
  // instead of overshooting), otherwise a harmonic mean of the two secants.
  double tangent(double a, double b) =>
      a * b <= 0 ? 0 : 2 * a * b / (a + b);
  final m0 = i == 0 ? d : tangent(dPrev, d);
  final m1 = i == n - 2 ? d : tangent(d, dNext);

  final t = (math.log(f) - x0) / h;
  final t2 = t * t, t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * y0 +
      (t3 - 2 * t2 + t) * h * m0 +
      (-2 * t3 + 3 * t2) * y1 +
      (t3 - t2) * h * m1;
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
  // No room for even a passthrough. The caller aborts well before this (a
  // player reporting < 2 sections is refused), but this is public engine API
  // and rule 4 is absolute: never emit more sections than the player allows.
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

  // Put the peaking filters on the SLIDER centres rather than an even log
  // spread. The user is drawing at these exact frequencies, so a filter at each
  // one is what reproduces what they drew; a generic spread leaves 250 Hz and
  // 500 Hz between centres and fits them ~2.5 dB short. Plus a low shelf, and a
  // high shelf unless the channel is band-limited — a sub has no top end to
  // shelve, and peaking filters alone cannot hold the outermost band.
  final shelves = narrow ? 1 : 2;
  final usable = [for (final f in kEqBands) if (f <= fitHi) f];
  final centers =
      usable.take(math.max(0, maxSections - shelves)).toList();
  if (centers.isEmpty) return const [BiquadSos.passthrough];

  final fit = fitBiquads(
    f,
    t,
    fs: fs,
    centers: centers,
    highShelf: !narrow,
  );

  final sections = fit.sections.take(maxSections).toList();
  for (final s in sections) {
    // The player validates nothing: an unstable section is accepted, stored and
    // then run. RBJ sections are stable by construction, so this is an assertion
    // about our own maths, not about input.
    final pole = poleModulus(s);
    if (!pole.isFinite ||
        pole >= 1 ||
        [s.b0, s.b1, s.b2, s.a1, s.a2].any((c) => !c.isFinite)) {
      throw const SonorityError(SonorityErrorCode.tuningUnstable);
    }
  }
  return sections;
}
