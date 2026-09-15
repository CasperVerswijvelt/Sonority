import 'package:flutter/material.dart';

/// One `label … value` line of a per-speaker breakdown.
///
/// Shared so the profile's captured-settings block and the Trueplay breakdown
/// read the same: the label is the muted half, the value is the payload and
/// carries the weight.
class LabelValueRow extends StatelessWidget {
  final String label;
  final String value;

  const LabelValueRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: body?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(value, style: body?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
