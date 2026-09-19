import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A flat, tappable "do something with this device" row: icon + title + a line
/// describing where it leads, with a chevron. Reads as an action, distinct from
/// the content card above and any settings section below.
///
/// A null [onTap] states the action exists but can't apply here (same treatment
/// as `TrueplayControl`'s unsupported row): the subtitle carries the reason and
/// the chevron goes, because there is nowhere to go.
class ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      // Full-bleed action row (not card-nested): square ink, not the rounded
      // listTileTheme default.
      shape: kFlatTileShape,
      contentPadding: const EdgeInsets.symmetric(horizontal: kPageGutter),
      leading: Icon(
        icon,
        color: onTap == null ? scheme.onSurfaceVariant : scheme.primary,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
