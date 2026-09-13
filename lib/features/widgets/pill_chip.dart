import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A small rounded pill: an optional icon + label tinted [color], on a faint
/// tint of the same color. Used on cards to tag a bonded group's role (Fronts /
/// Surrounds / Sub) or a group member's channel (L / R / L+R).
class PillChip extends StatelessWidget {
  /// Omit for a tag whose text already carries the whole meaning — a channel
  /// token like `LR` says everything a glyph could, and an icon just competes
  /// with two characters of pure signal.
  final IconData? icon;
  final String text;
  final Color color;

  /// Solid [color] fill with on-color content instead of the faint tint — for a
  /// state *badge* (the profile tile's "Active") rather than a tag, which needs
  /// to stand out against a tinted card. Same pill, one knob: the app has
  /// exactly one pill widget.
  final bool filled;

  const PillChip({
    super.key,
    this.icon,
    required this.text,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled
        ? (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black)
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
