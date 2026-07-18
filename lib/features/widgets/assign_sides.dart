import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import 'speaker_side_card.dart';

/// The two-speaker L/R assignment row: a [SpeakerSideCard] per side with a swap
/// button between them, plus a "tap swap if reversed" hint. Shared by the
/// home-theater setup (fronts / rear surrounds) and the stereo-group flow so the
/// L/R assignment reads identically everywhere.
class AssignSides extends StatelessWidget {
  final SonosSystem system;

  /// The two chosen uuids, order [left, right].
  final List<String> selected;
  final String leftLabel;
  final String rightLabel;
  final VoidCallback onSwap;
  final Widget Function(SonosDevice device) identifyControls;

  const AssignSides({
    super.key,
    required this.system,
    required this.selected,
    required this.leftLabel,
    required this.rightLabel,
    required this.onSwap,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    if (selected.length != 2) {
      return const Text('Choose two speakers first.');
    }
    final left = system.device(selected[0]);
    final right = system.device(selected[1]);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: SpeakerSideCard(
                    side: leftLabel,
                    device: left,
                    controls: left == null ? null : identifyControls(left))),
            IconButton.filledTonal(
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Swap sides',
            ),
            Expanded(
                child: SpeakerSideCard(
                    side: rightLabel,
                    device: right,
                    controls: right == null ? null : identifyControls(right))),
          ],
        ),
        Gap.s,
        Text('Tap swap if the sides are reversed.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
