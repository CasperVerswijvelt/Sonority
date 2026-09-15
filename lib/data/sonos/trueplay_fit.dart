/// Frequency-domain IIR fit: turn a magnitude/dB target curve into a cascade of
/// biquad second-order sections, via an RBJ (peaking + low-shelf) cascade fitted
/// with a bounded Levenberg-Marquardt.
///
/// Pure Dart, no Flutter. Its output `List<BiquadSos>` drops straight into
/// [encodeSpectralPayload] (`trueplay_codec.dart`), so this is the stage between
/// "a correction curve someone chose" and "coefficients a speaker will run".
/// Where the curve comes from is not this file's business — today the EQ sliders
/// (`custom_eq.dart`), later a room measurement.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'trueplay_codec.dart';

/// Log-spaced points between [lo] and [hi] inclusive.
List<double> geomspace(double lo, double hi, int n) {
  if (n == 1) return [lo];
  final logLo = math.log(lo), step = (math.log(hi) - logLo) / (n - 1);
  return [for (var i = 0; i < n; i++) math.exp(logLo + step * i)];
}

/// RBJ peaking-EQ biquad at [f0] (Hz), quality [q], gain [gainDb] (dB), fs [fs].
BiquadSos rbjPeaking(double f0, double q, double gainDb, double fs) {
  final a = math.pow(10, gainDb / 40.0).toDouble();
  final w0 = 2 * math.pi * f0 / fs;
  final alpha = math.sin(w0) / (2 * q);
  final c = math.cos(w0);
  final a0 = 1 + alpha / a;
  return BiquadSos(
    (1 + alpha * a) / a0,
    (-2 * c) / a0,
    (1 - alpha * a) / a0,
    (-2 * c) / a0,
    (1 - alpha / a) / a0,
  );
}

/// RBJ low-shelf biquad (shelf slope S=1).
BiquadSos rbjLowShelf(double f0, double gainDb, double fs) {
  final a = math.pow(10, gainDb / 40.0).toDouble();
  final w0 = 2 * math.pi * f0 / fs;
  final c = math.cos(w0);
  final alpha = math.sin(w0) / 2 * math.sqrt((a + 1 / a) * (1 / 1.0 - 1) + 2);
  final tw = 2 * math.sqrt(a) * alpha;
  final a0 = (a + 1) + (a - 1) * c + tw;
  return BiquadSos(
    a * ((a + 1) - (a - 1) * c + tw) / a0,
    2 * a * ((a - 1) - (a + 1) * c) / a0,
    a * ((a + 1) - (a - 1) * c - tw) / a0,
    -2 * ((a - 1) + (a + 1) * c) / a0,
    ((a + 1) + (a - 1) * c - tw) / a0,
  );
}

/// Largest pole magnitude of one section — the roots of `z² + a1·z + a2`.
/// **> 1 ⇒ the section is UNSTABLE** (its output grows without bound).
///
/// RBJ sections are stable by construction, so [fitBiquads] output always passes;
/// this exists to vet coefficients from anywhere else *before* they are written to
/// a speaker, because the player itself does not — an unstable section is accepted,
/// stored, and then run.
double poleModulus(BiquadSos s) {
  final disc = s.a1 * s.a1 - 4 * s.a2;
  // disc < 0 ⇒ complex-conjugate pair, whose product a2 is |p|².
  if (disc < 0) return math.sqrt(s.a2.abs());
  final r = math.sqrt(disc);
  return math.max((-s.a1 + r).abs(), (-s.a1 - r).abs()) / 2;
}

/// Magnitude response (dB) of a biquad cascade at frequencies [freqs] (Hz).
Float64List cascadeMagnitudeDb(
    List<BiquadSos> sections, List<double> freqs, double fs) {
  final out = Float64List(freqs.length);
  for (var i = 0; i < freqs.length; i++) {
    final w = 2 * math.pi * freqs[i] / fs;
    // z^-1 = e^{-jw}
    final cr = math.cos(w), ci = -math.sin(w);
    // z^-2
    final c2r = math.cos(2 * w), c2i = -math.sin(2 * w);
    var hr = 1.0, hi = 0.0;
    for (final s in sections) {
      final nr = s.b0 + s.b1 * cr + s.b2 * c2r;
      final ni = s.b1 * ci + s.b2 * c2i;
      final dr = 1 + s.a1 * cr + s.a2 * c2r;
      final di = s.a1 * ci + s.a2 * c2i;
      // (nr+j ni)/(dr+j di)
      final den = dr * dr + di * di;
      final qr = (nr * dr + ni * di) / den;
      final qi = (ni * dr - nr * di) / den;
      final tr = hr * qr - hi * qi;
      hi = hr * qi + hi * qr;
      hr = tr;
    }
    out[i] = 20 * math.log(math.sqrt(hr * hr + hi * hi)) / math.ln10;
  }
  return out;
}

/// Result of a biquad fit: the sections plus the fit error against the target.
class BiquadFit {
  final List<BiquadSos> sections;
  final double rmsDb;
  final double maxAbsDb;
  const BiquadFit(this.sections, this.rmsDb, this.maxAbsDb);
}

/// Fit a cascade of [nBands] fixed-center peaking biquads + one low-shelf to a
/// magnitude target [targetDb] sampled at [freqs] (Hz). Free parameters: each
/// band's gain and Q, plus the shelf frequency and gain — fitted with a bounded
/// Levenberg–Marquardt (numeric Jacobian). Reproduces a typical correction curve
/// to ~0.6 dB RMS.
///
/// The peaking centers default to `geomspace(bandLo, bandHi, nBands)`. Narrow
/// them for a **band-limited channel** — a Sonos sub only reproduces ~20–120 Hz,
/// so spreading 10 bands over the default 60–8000 Hz wastes most of them above
/// its passband: `fitBiquads(f, t, nBands: 6, bandLo: 25, bandHi: 110)`.
/// The low-shelf keeps its fixed 30–200 Hz frequency bounds either way — that
/// range is already entirely inside a sub's band, so nothing needs to scale.
///
/// Pass [centers] to place the peaking filters explicitly; it overrides
/// `nBands`/`bandLo`/`bandHi` entirely.
BiquadFit fitBiquads(
  List<double> freqs,
  List<double> targetDb, {
  int nBands = 10,
  double fs = 44100,
  int maxIters = 60,
  double bandLo = 60,
  double bandHi = 8000,
  List<double>? centers,
}) {
  final c = centers ?? geomspace(bandLo, bandHi, nBands);
  nBands = c.length;
  final p = 2 * nBands + 2; // gains, Qs, shelfF, shelfG
  final lo = Float64List(p), hi = Float64List(p);
  for (var i = 0; i < nBands; i++) {
    lo[i] = -18;
    hi[i] = 12; // gains
    lo[nBands + i] = 0.3;
    hi[nBands + i] = 6; // Qs
  }
  lo[p - 2] = 30;
  hi[p - 2] = 200; // shelf f
  lo[p - 1] = -24;
  hi[p - 1] = 6; // shelf g

  final theta = Float64List(p);
  for (var i = 0; i < nBands; i++) {
    theta[i] = 0; // flat gains
    theta[nBands + i] = 1; // Q=1
  }
  theta[p - 2] = 55;
  theta[p - 1] = -8;

  List<BiquadSos> build(Float64List t) {
    final s = <BiquadSos>[
      for (var i = 0; i < nBands; i++)
        rbjPeaking(c[i], math.max(t[nBands + i], 0.2), t[i], fs),
      rbjLowShelf(t[p - 2].clamp(30, 200), t[p - 1], fs),
    ];
    return s;
  }

  Float64List residual(Float64List t) {
    final m = cascadeMagnitudeDb(build(t), freqs, fs);
    final r = Float64List(freqs.length);
    for (var i = 0; i < r.length; i++) {
      r[i] = m[i] - targetDb[i];
    }
    return r;
  }

  double cost(Float64List r) {
    var s = 0.0;
    for (final v in r) {
      s += v * v;
    }
    return s;
  }

  final m = freqs.length;
  var r = residual(theta);
  var curCost = cost(r);
  var lambda = 1e-3;

  for (var iter = 0; iter < maxIters; iter++) {
    // Numeric Jacobian (forward diff), m x p.
    final jac = List<Float64List>.generate(m, (_) => Float64List(p));
    for (var k = 0; k < p; k++) {
      final eps = math.max(1e-4, theta[k].abs() * 1e-4);
      final saved = theta[k];
      theta[k] = (saved + eps).clamp(lo[k], hi[k]);
      final actualEps = theta[k] - saved == 0 ? eps : theta[k] - saved;
      final rp = residual(theta);
      theta[k] = saved;
      for (var i = 0; i < m; i++) {
        jac[i][k] = (rp[i] - r[i]) / actualEps;
      }
    }
    // Normal equations: A = JtJ + lambda*diag(JtJ), g = Jt r.
    final a = List<Float64List>.generate(p, (_) => Float64List(p));
    final g = Float64List(p);
    for (var i = 0; i < m; i++) {
      final ji = jac[i];
      final ri = r[i];
      for (var kk = 0; kk < p; kk++) {
        g[kk] += ji[kk] * ri;
        final ak = a[kk];
        for (var l = kk; l < p; l++) {
          ak[l] += ji[kk] * ji[l];
        }
      }
    }
    for (var kk = 0; kk < p; kk++) {
      for (var l = kk + 1; l < p; l++) {
        a[l][kk] = a[kk][l];
      }
    }

    var improved = false;
    for (var tryStep = 0; tryStep < 6; tryStep++) {
      final aug = List<Float64List>.generate(p, (i) {
        final row = Float64List.fromList(a[i]);
        row[i] += lambda * (a[i][i] + 1e-9);
        return row;
      });
      final delta = _solve(aug, Float64List.fromList(g));
      if (delta == null) {
        lambda *= 4;
        continue;
      }
      final trial = Float64List(p);
      for (var k = 0; k < p; k++) {
        trial[k] = (theta[k] - delta[k]).clamp(lo[k], hi[k]);
      }
      final rt = residual(trial);
      final ct = cost(rt);
      if (ct < curCost) {
        for (var k = 0; k < p; k++) {
          theta[k] = trial[k];
        }
        r = rt;
        curCost = ct;
        lambda = math.max(lambda * 0.5, 1e-9);
        improved = true;
        break;
      }
      lambda *= 4;
    }
    if (!improved && lambda > 1e12) break;
  }

  var rms = math.sqrt(curCost / m);
  var mx = 0.0;
  for (final v in r) {
    if (v.abs() > mx) mx = v.abs();
  }
  return BiquadFit(build(theta), rms, mx);
}

/// Solve A x = b (A is p×p, destructive copy) via Gaussian elimination with
/// partial pivoting. Returns null if singular.
Float64List? _solve(List<Float64List> a, Float64List b) {
  final n = b.length;
  for (var col = 0; col < n; col++) {
    var piv = col;
    var best = a[col][col].abs();
    for (var row = col + 1; row < n; row++) {
      final v = a[row][col].abs();
      if (v > best) {
        best = v;
        piv = row;
      }
    }
    if (best < 1e-15) return null;
    if (piv != col) {
      final tr = a[piv];
      a[piv] = a[col];
      a[col] = tr;
      final tb = b[piv];
      b[piv] = b[col];
      b[col] = tb;
    }
    final pivRow = a[col];
    final pivVal = pivRow[col];
    for (var row = col + 1; row < n; row++) {
      final f = a[row][col] / pivVal;
      if (f == 0) continue;
      final ar = a[row];
      for (var k = col; k < n; k++) {
        ar[k] -= f * pivRow[k];
      }
      b[row] -= f * b[col];
    }
  }
  final x = Float64List(n);
  for (var row = n - 1; row >= 0; row--) {
    var s = b[row];
    final ar = a[row];
    for (var k = row + 1; k < n; k++) {
      s -= ar[k] * x[k];
    }
    x[row] = s / ar[row];
  }
  return x;
}
