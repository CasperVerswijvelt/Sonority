import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A flat, tappable "do something with this device" row: icon + title + a line
/// describing where it leads, with a chevron. Reads as an action, distinct from
/// the content card above and any settings section below.
class ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // Full-bleed action row (not card-nested): square ink, not the rounded
      // listTileTheme default.
      shape: kFlatTileShape,
      contentPadding: const EdgeInsets.symmetric(horizontal: kPageGutter),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
