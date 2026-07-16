import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'pill_chip.dart';

/// One speaker in a bonded group / home theater: an icon, the speaker type as
/// the title (the room name is absorbed into the entity name, so the type is the
/// useful label), and — when it has one — its channel/role as a pill chip
/// beneath. A standalone speaker has no channel, so [channel] is omitted and no
/// chip shows. Shared by the group + room + profile entity sheets.
class MemberChannelCard extends StatelessWidget {
  final IconData icon;
  final String type;
  final String? channel;
  const MemberChannelCard(
      {super.key, required this.icon, required this.type, this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final channel = this.channel;
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
                  if (channel != null) ...[
                    Gap.s,
                    PillChip(icon: icon, text: channel, color: scheme.primary),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
