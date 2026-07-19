import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';

/// Assigns which of two chosen speakers plays left vs right: one compact row per
/// speaker with a Left/Right segmented toggle. There are only two, so choosing a
/// side on one swaps them — [selected] is ordered `[left, right]`, and any change
/// calls [onSwap]. Shared by the home-theater setup (fronts / rear surrounds) and
/// the stereo-group flow.
class AssignSides extends StatelessWidget {
  final SonosSystem system;

  /// The two chosen uuids, order [left, right].
  final List<String> selected;
  final VoidCallback onSwap;

  const AssignSides({
    super.key,
    required this.system,
    required this.selected,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    if (selected.length != 2) {
      return const Text('Choose two speakers first.');
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 2; i++) _row(context, i),
        Gap.xs,
        Text('Tap a side to swap which speaker plays left or right.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _row(BuildContext context, int i) {
    final theme = Theme.of(context);
    final device = system.device(selected[i]);
    final isRight = i == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.speaker, color: theme.colorScheme.onSurfaceVariant),
          Gap.s,
          Expanded(
            child: Text(device?.roomName ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
          ),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Left')),
              ButtonSegment(value: true, label: Text('Right')),
            ],
            selected: {isRight},
            // Only two speakers, so picking the other side swaps the pair.
            onSelectionChanged: (s) {
              if (s.first != isRight) onSwap();
            },
          ),
        ],
      ),
    );
  }
}
