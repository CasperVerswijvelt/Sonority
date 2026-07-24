import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'entity_glyph.dart';
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

  /// Optional trailing widget (e.g. a `SpeakerIdentifyButton`) shown at the end
  /// of the row. Omitted in read-only contexts like the profile-entity snapshot.
  final Widget? trailing;
  const MemberChannelCard(
      {super.key,
      required this.icon,
      required this.type,
      this.channel,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final channel = this.channel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            EntityGlyph(icon: icon),
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
