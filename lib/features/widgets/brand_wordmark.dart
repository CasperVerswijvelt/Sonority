import 'package:flutter/material.dart';

/// The Sonority wordmark, tinted to the theme text colour. The single
/// white-on-alpha asset works in light and dark via a `srcIn` ColorFilter —
/// `Image(color:)` renders blank under CanvasKit on web (the screenshot host),
/// so ColorFiltered is used instead. Shown in the app bar on a phone and in the
/// nav rail's leading slot on a wide window.
class BrandWordmark extends StatelessWidget {
  final double height;
  const BrandWordmark({super.key, this.height = 20});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
      child: Image.asset('assets/brand/sonority_wordmark.png', height: height),
    );
  }
}
