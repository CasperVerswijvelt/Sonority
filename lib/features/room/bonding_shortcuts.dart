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

/// Whether the standalone speaker [uuid] can start a group — it must itself be
/// groupable AND have at least one other groupable speaker to pair with, so the
/// group flow can't dead-end on a single speaker.
bool canGroupSpeaker(SonosSystem system, String uuid) {
  final z = system.zoneableSpeakers;
  return z.length >= 2 && z.any((d) => d.uuid == uuid);
}

/// Whether a standalone Sub can join a new group — a group needs ≥2 speakers
/// (the Sub rides along as the SW channel), so there must be two to bond.
bool canGroupSub(SonosSystem system) => system.zoneableSpeakers.length >= 2;

/// Pops the current page, then pushes [location] — pop-then-push so that after
/// the guided flow completes we land back on the overview (the device is no
/// longer standalone), not on a now-stale detail page.
void leaveTo(BuildContext context, String location) {
  final router = GoRouter.of(context);
  context.pop();
  router.push(location);
}

/// "Add to a home theater": route into the HT setup flow keyed to a soundbar —
/// straight through with one soundbar, or a chooser when there are several. The
/// originating [speaker] or [sub] is passed on so the flow pre-selects it.
Future<void> addToHomeTheater(
  BuildContext context,
  List<ZoneGroupMember> soundbars, {
  String? speaker,
  String? sub,
}) async {
  String? target;
  if (soundbars.length == 1) {
    target = soundbars.first.uuid;
  } else {
    target = await showDialog<String>(
      context: context,
      builder: (ctx) => _HomeTheaterChooser(soundbars: soundbars),
    );
  }
  if (target == null || !context.mounted) return;
  final q = speaker != null
      ? '?speaker=$speaker'
      : sub != null
          ? '?sub=$sub'
          : '';
  leaveTo(context, '/theater/$target/fronts$q');
}

/// Pick-a-home-theater dialog: one clearly-tappable row per HT (glyph + name +
/// chevron), not bare text options.
class _HomeTheaterChooser extends StatelessWidget {
  final List<ZoneGroupMember> soundbars;
  const _HomeTheaterChooser({required this.soundbars});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.roomAddToWhichHomeTheater),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: soundbars.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => ListTile(
            title: Text(soundbars[i].zoneName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, soundbars[i].uuid),
          ),
        ),
      ),
    );
  }
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
