import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A friendly full-screen busy state with a title + explanation, so long
/// (~20s) Sonos reconfigurations don't look like a frozen plain spinner.
class BusyView extends StatelessWidget {
  final String title;
  final String? subtitle;

  const BusyView({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                color: scheme.primary,
                backgroundColor: scheme.primary.withValues(alpha: 0.15),
              ),
            ),
            Gap.l,
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              Gap.s,
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            Gap.l,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(minHeight: 6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
