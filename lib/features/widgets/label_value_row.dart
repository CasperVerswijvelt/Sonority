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
    // A Wrap, NOT a Row. A Row lays its non-flex children out with unbounded
    // main-axis constraints, so a bare `Text(value)` never wrapped: it took the
    // whole width, `freeSpace` went negative and the `Expanded` label was
    // clamped to zero — measured in the Trueplay indent, the speaker name went
    // 102.75px → 11.75px at 1.5x text scale and 0px (plus a RenderFlex
    // overflow, silently clipped in release) from 2x. The name is the entire
    // payload of a breakdown row, so that is the feature gone.
    //
    // Making the value `Flexible` instead fixes the overflow but splits the
    // width by FLEX, which ignores what the text actually needs: at 1.0x, where
    // the pair fits on one line today, the value wrapped onto two. A Wrap sizes
    // both halves to their intrinsic width when they fit — pixel-identical to
    // the old row — stacks them onto two lines when they don't, and bounds each
    // half to the row width so its own text wraps instead of overflowing.
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        // Full width so `spaceBetween` has the row's slack to work with and
        // keeps the value's right edge at the row's; a Wrap left to itself
        // shrinks to its content and the value stops being right-aligned.
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 2, // only bites once the pair has stacked
            children: [
              Text(label,
                  style:
                      body?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: body?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
