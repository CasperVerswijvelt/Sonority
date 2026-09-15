import 'package:flutter/material.dart';

/// One `label … value` line of a per-speaker breakdown.
///
/// Shared so the profile's captured-settings block and the Trueplay breakdown
/// read the same: the label is the muted half, the value is the payload and
/// carries the weight.
///
/// The two halves are merged for accessibility: as siblings a screen reader
/// announced "Era 100" and "Couldn't read" as unrelated nodes, six times over
/// on a 5.1 system, so the pairing was only visible to sighted users.
class LabelValueRow extends StatelessWidget {
  final String label;
  final String value;

  const LabelValueRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      body?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Text(value, style: body?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
