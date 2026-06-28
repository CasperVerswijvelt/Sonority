import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';

/// A small card showing one side of a pair/front layout: a LEFT/RIGHT label, a
/// speaker icon, the room name, and optional identify [controls]. Shared by the
/// front-surrounds and stereo-pair flows so the L/R cards stay consistent.
class SpeakerSideCard extends StatelessWidget {
  final String side;
  final SonosDevice? device;
  final Widget? controls;
  const SpeakerSideCard({
    super.key,
    required this.side,
    required this.device,
    this.controls,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(side,
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
            Gap.s,
            Icon(Icons.speaker, color: scheme.onSurfaceVariant),
            Gap.xs,
            Text(device?.roomName ?? '—',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge),
            if (device != null && controls != null) ...[
              Gap.xs,
              controls!,
            ],
          ],
        ),
      ),
    );
  }
}
