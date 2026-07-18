import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The single glyph treatment for every "thing with an icon": a rounded-square
/// tonal tile holding a Material [icon] (or an arbitrary [child], e.g. a profile
/// SF Symbol). One shape everywhere — entity cards, bonded-member cards and the
/// profile tile — so the glyph SHAPE is uniform and only the fill COLOR varies
/// (neutral `primaryContainer` for system entities; a profile's custom accent).
class EntityGlyph extends StatelessWidget {
  final IconData? icon;

  /// Overrides [icon] with an arbitrary glyph widget (the profile tile passes an
  /// SF Symbol here). Exactly one of [icon] / [child] must be set.
  final Widget? child;
  final Color? background;
  final Color? foreground;
  final double size;

  const EntityGlyph({
    super.key,
    this.icon,
    this.child,
    this.background,
    this.foreground,
    this.size = 44,
  }) : assert(icon != null || child != null, 'icon or child required');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: child ??
          Icon(icon,
              color: foreground ?? scheme.onPrimaryContainer, size: size * 0.5),
    );
  }
}
