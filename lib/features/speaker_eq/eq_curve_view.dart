import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/sonos/custom_eq.dart';

/// One labelled curve on the EQ plot.
@immutable
class EqCurve {
  final Float64List db;
  final Color color;
  final bool dashed;
  const EqCurve(this.db, this.color, {this.dashed = false});
}

/// The EQ plot: dB against log frequency, with the correction rails drawn.
///
/// Takes a *list* of curves rather than fixed slots, so the measurement step can
/// later add the measured response and the base correction without changing this
/// widget. Today it is handed one: the correction being applied.
///
/// It is deliberately NOT handed the fitted cascade's achieved response as a
/// second line. The fitter reproduces this curve to well under a dB, so the two
/// drew on top of each other — while costing a ~15 ms Levenberg-Marquardt solve
/// per slider frame. The part that genuinely differs from the slider positions is
/// the per-frequency clamp, and that is already in this curve.
class EqCurveView extends StatelessWidget {
  final List<double> freqs;
  final List<EqCurve> curves;
  const EqCurveView({super.key, required this.freqs, required this.curves});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 2.2,
      child: CustomPaint(
        painter: _EqPainter(
          freqs: freqs,
          curves: curves,
          grid: scheme.outlineVariant,
          label: scheme.onSurfaceVariant,
          textDirection: Directionality.of(context),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _EqPainter extends CustomPainter {
  final List<double> freqs;
  final List<EqCurve> curves;
  final Color grid;
  final Color label;
  final TextDirection textDirection;

  _EqPainter({
    required this.freqs,
    required this.curves,
    required this.grid,
    required this.label,
    required this.textDirection,
  });

  // A little headroom beyond the rails so a clamped curve visibly sits ON the
  // rail rather than being cropped at the edge of the plot.
  static const _top = kEqMaxBoostDb + 3;
  static const _bottom = -kEqMaxCutDb - 3;

  double _x(double f, Size s) {
    final lo = math.log(freqs.first), hi = math.log(freqs.last);
    return (math.log(f) - lo) / (hi - lo) * s.width;
  }

  double _y(double db, Size s) =>
      (_top - db) / (_top - _bottom) * s.height;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final railPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Zero line, then the two correction rails — the rails are the honest part:
    // the clamp is on the composed curve, so a user must be able to see it bite.
    canvas.drawLine(Offset(0, _y(0, size)), Offset(size.width, _y(0, size)),
        railPaint);
    for (final db in [kEqMaxBoostDb, -kEqMaxCutDb]) {
      _dashedLine(canvas, Offset(0, _y(db, size)),
          Offset(size.width, _y(db, size)), railPaint);
    }

    for (final f in kEqBands) {
      final x = _x(f, size);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      _text(canvas, eqBandLabel(f), Offset(x, size.height - 14));
    }

    for (final c in curves) {
      final path = Path();
      for (var i = 0; i < freqs.length; i++) {
        final p = Offset(_x(freqs[i], size), _y(c.db[i], size));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = c.dashed ? 1.5 : 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(
          a + dir * d, a + dir * math.min(d + dash, total), paint);
    }
  }

  void _text(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
          text: s, style: TextStyle(color: label, fontSize: 10)),
      textDirection: textDirection,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(_EqPainter old) =>
      old.curves != curves || old.grid != grid;
}
