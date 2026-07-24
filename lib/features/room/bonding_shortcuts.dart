import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';

/// Shortcuts into the bonding flows, shared by the standalone room and Sub pages
/// so an unbonded device isn't a dead end. The flows do their own speaker
/// selection + validation; these just route into them.

/// Soundbars / home theaters a loose speaker or Sub could join (the same rule
/// the overview uses to list home theaters).
List<ZoneGroupMember> homeTheaterTargets(SonosSystem system) => system.allMembers
    .where((m) => m.isHomeTheater || (system.device(m.uuid)?.isSoundbar ?? false))
    .toList();

/// Pops the current page, then pushes [location] — pop-then-push so that after
/// the guided flow completes we land back on the overview (the device is no
/// longer standalone), not on a now-stale detail page.
void leaveTo(BuildContext context, String location) {
  final router = GoRouter.of(context);
  context.pop();
  router.push(location);
}

/// "Add to a home theater": route into the HT setup flow keyed to a soundbar —
/// straight through with one soundbar, or a small chooser when there are several.
Future<void> addToHomeTheater(
  BuildContext context,
  List<ZoneGroupMember> soundbars,
) async {
  String? target;
  if (soundbars.length == 1) {
    target = soundbars.first.uuid;
  } else {
    target = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.l10n.roomAddToWhichHomeTheater),
        children: [
          for (final s in soundbars)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s.uuid),
              child: Text(s.zoneName),
            ),
        ],
      ),
    );
  }
  if (target == null || !context.mounted) return;
  leaveTo(context, '/theater/$target/fronts');
}

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
