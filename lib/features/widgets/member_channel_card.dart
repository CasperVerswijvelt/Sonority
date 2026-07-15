import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'pill_chip.dart';

/// One speaker in a bonded group / home theater: an icon, the speaker type as
/// the title (the room name is absorbed into the entity name, so the type is the
/// useful label), and its channel/role as a pill chip beneath. Shared by the
/// live group detail screen and the profile entity detail screen.
class MemberChannelCard extends StatelessWidget {
  final IconData icon;
  final String type;
  final String channel;
  const MemberChannelCard(
      {super.key,
      required this.icon,
      required this.type,
      required this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(icon, color: scheme.onPrimaryContainer),
            ),
            Gap.m,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type, style: theme.textTheme.titleMedium),
                  Gap.s,
                  PillChip(icon: icon, text: channel, color: scheme.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
