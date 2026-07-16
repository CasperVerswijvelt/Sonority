import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A small rounded pill: an icon + label tinted [color], on a faint tint of the
/// same color. Used on cards to tag a bonded group's role (Fronts / Surrounds /
/// Sub) or a group member's channel (L / R / L+R).
class PillChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const PillChip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
