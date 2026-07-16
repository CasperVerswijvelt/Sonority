import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A light informational note: an info icon + a muted paragraph in a tinted
/// card. Shared by the create/re-snapshot primers (and anywhere a "heads-up"
/// blurb is shown) so the treatment doesn't drift.
class InfoNote extends StatelessWidget {
  final String text;
  const InfoNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            Gap.s,
            Expanded(child: Text(text, style: theme.mutedText)),
          ],
        ),
      ),
    );
  }
}
