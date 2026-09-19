import 'package:flutter/material.dart';

/// A vertical EQ band slider whose track fills **from 0 dB**, not from the
/// minimum.
///
/// Flutter's `Slider` always paints its active track from the low end, which on
/// an EQ reads as "every band is turned up a lot" when in fact they're all at
/// rest. An equaliser's rest position is the middle, so the fill has to start
/// there and grow up or down. Flutter ships no centre-origin track, hence the
/// custom [SliderTrackShape] — the rest is a stock Slider.
class EqSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final String Function(double) semanticFormatter;
  final ValueChanged<double> onChanged;

  const EqSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.semanticFormatter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackShape: _CentreOriginTrackShape(origin: _originFraction),
          trackHeight: 4,
          activeTrackColor: scheme.primary,
          // outlineVariant, not surfaceContainerHighest: the track sits on a
          // card, where a container tone is almost the same value as the card
          // itself and the band's travel disappears.
          inactiveTrackColor: scheme.outlineVariant,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        ),
        // Continuous, NOT divisions — the caller quantises instead. A discrete
        // Slider animates its thumb to each division over 75ms, which on a drag
        // reads as the thumb lagging a little behind the finger. The step is
        // unchanged; only the animation is gone.
        //
        // No `label` either: the value bubble it puts in an overlay duplicates
        // the dB readout already sitting above every band.
        child: Slider(
          value: value,
          min: min,
          max: max,
          semanticFormatterCallback: semanticFormatter,
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// Where 0 dB sits along the track, 0..1 from the minimum.
  double get _originFraction => (0 - min) / (max - min);
}

/// Paints a thin full-length track with a thicker segment between [origin] and
/// the thumb.
class _CentreOriginTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  final double origin;
  const _CentreOriginTrackShape({required this.origin});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;

    final canvas = context.canvas;
    final full = sliderTheme.trackHeight ?? 4;
    final thin = full / 2;
    final radius = Radius.circular(full / 2);

    // The whole range stays visible, thin — a band's travel should be legible
    // without touching it.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: rect.center, width: rect.width, height: thin),
        Radius.circular(thin / 2),
      ),
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.grey,
    );

    // 0 dB → thumb, at full thickness. LTR only matters for which side is which;
    // the widget is rotated, so "left" is the bottom of the visible slider.
    final originX = textDirection == TextDirection.ltr
        ? rect.left + rect.width * origin
        : rect.right - rect.width * origin;
    final lo = originX < thumbCenter.dx ? originX : thumbCenter.dx;
    final hi = originX < thumbCenter.dx ? thumbCenter.dx : originX;
    if (hi - lo > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            lo,
            rect.center.dy - full / 2,
            hi,
            rect.center.dy + full / 2,
          ),
          radius,
        ),
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.blue,
      );
    }
  }
}
