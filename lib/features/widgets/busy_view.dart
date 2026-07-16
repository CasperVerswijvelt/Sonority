import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// A friendly full-screen busy state with a title + explanation, so long
/// (~20s) Sonos reconfigurations don't look like a frozen plain spinner.
class BusyView extends StatelessWidget {
  final String title;
  final String? subtitle;

  const BusyView({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                style: Theme.of(context).mutedText,
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

/// Shown when a room/member referenced by the route no longer exists in the
/// current topology (e.g. after a rescan). Offers a way back to discovery.
class MissingRoomView extends StatelessWidget {
  const MissingRoomView({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline, size: 56),
              Gap.m,
              const Text('This room is no longer available. Rescan to refresh.'),
              Gap.l,
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to scan'),
              ),
            ],
          ),
        ),
      );
}
