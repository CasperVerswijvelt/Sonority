import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A section label shared across the overview and the sub-screens so every
/// "group of things below me" header reads the same: a muted `titleSmall` title
/// with an optional leading [icon], an optional right-aligned "+" ([onAdd]), and
/// an optional muted [helper] paragraph underneath. Carries its own bottom gap.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  /// Optional muted explanation shown under the title.
  final String? helper;

  /// When set, a small right-aligned "+" button (e.g. create a group).
  final VoidCallback? onAdd;
  final String? addTooltip;

  const SectionHeader(
    this.title, {
    super.key,
    this.icon,
    this.helper,
    this.onAdd,
    this.addTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                Gap.s,
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (onAdd != null)
                IconButton.outlined(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  tooltip: addTooltip,
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    side: BorderSide(color: scheme.outlineVariant),
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (helper != null) ...[
            Gap.xs,
            Text(helper!, style: theme.mutedText),
          ],
        ],
      ),
    );
  }
}
