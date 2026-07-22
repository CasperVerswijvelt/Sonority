import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/localized_error.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy_view.dart';
import '../widgets/identify_controls.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/scroll_footer.dart';
import '../widgets/section_header.dart';
import '../widgets/settings_section.dart';
import '../widgets/trueplay_control.dart';

/// A single standalone room shown as a pushed page: the speaker, shortcuts into
/// the bonding flows, and the Trueplay control. A page (not a sheet) so the rule
/// is uniform — sheets are read-only peeks; anything you can act on is a page.
class RoomScreen extends ConsumerWidget {
  final String uuid;
  const RoomScreen({super.key, required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(sonosControllerProvider).value;
    final member = system?.memberByUuid(uuid);

    if (member == null) {
      return AppScaffold(
        title: context.l10n.roomTitle,
        body: const Padding(
            padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }

    // Single standalone speaker (stereo pairs are groups → the group sheet).
    final device = system!.device(uuid);
    final devices = [if (device != null) device];
    // Soundbars this speaker could join as a front/surround (same rule the
    // overview uses to list home theaters).
    final soundbars = system.allMembers
        .where(
          (m) =>
              m.isHomeTheater || (system.device(m.uuid)?.isSoundbar ?? false),
        )
        .toList();

    return AppScaffold(
      title: member.zoneName,
      subtitle: context.l10n.roomTitle,
      actions: [
        if (device != null)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: context.l10n.roomRenameTooltip,
            onPressed: () => _rename(context, ref, device, member.zoneName),
          ),
      ],
      // The speaker sits at the top; the shortcuts + Trueplay float to the
      // bottom of the page (via ScrollFooter), matching the group page's
      // Separate button.
      body: ScrollFooter(
        padding: const EdgeInsets.symmetric(vertical: 8),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Put this speaker to use: shortcuts into the bonding flows so a
            // standalone room isn't a dead end (the flows do their own
            // validation). Descriptive rows (title + what it does), not bare
            // buttons.
            _ActionRow(
              icon: Icons.speaker_group_outlined,
              title: context.l10n.roomGroupWith,
              subtitle: context.l10n.roomGroupWithSubtitle,
              onTap: () => _leaveTo(context, '/group'),
            ),
            if (soundbars.isNotEmpty)
              _ActionRow(
                icon: Icons.surround_sound,
                title: context.l10n.roomAddToHomeTheater,
                subtitle: context.l10n.roomAddToHomeTheaterSubtitle,
                onTap: () => _addToHomeTheater(context, soundbars),
              ),
            Gap.s,
            // Settings: a flat, sectioned Trueplay row, not another card.
            SettingsSection(children: [TrueplayControl(devices: devices)]),
          ],
        ),
        children: [
          // Content: the speaker itself — a standalone speaker has no channel,
          // so no chip (parallels the group's per-speaker cards).
          if (device != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(kPageGutter, 4, kPageGutter, 0),
              child: SectionHeader(context.l10n.sectionSpeakers),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
              child: MemberChannelCard(
                icon: Icons.speaker,
                type: device.typeLabel,
                // Standalone speaker → both LED blink and the chime apply.
                trailing: speakerIdentifyButton(device, allowChime: true),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pops the room page, then pushes [location] — pop-then-push so that after the
/// guided flow completes we land back on the overview (the room is no longer
/// standalone), not on a now-stale room page.
void _leaveTo(BuildContext context, String location) {
  final router = GoRouter.of(context);
  context.pop();
  router.push(location);
}

/// "Add to a home theater": route into the HT setup flow keyed to a soundbar —
/// straight through with one soundbar, or a small chooser when there are several.
Future<void> _addToHomeTheater(
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
  _leaveTo(context, '/theater/$target/fronts');
}

/// A flat, tappable "do something with this speaker" row: icon + title + a line
/// describing where it leads, with a chevron. Reads as an action, distinct from
/// the content card above and the settings section below.
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: kPageGutter),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

Future<void> _rename(
  BuildContext context,
  WidgetRef ref,
  SonosDevice device,
  String current,
) async {
  final name = await showRenameDialog(context, current);
  if (name == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await ref
        .read(sonosControllerProvider.notifier)
        .renameRoom(device: device, name: name);
    messenger.showSnackBar(SnackBar(content: Text(l10n.roomRenamedTo(name))));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.roomRenameFailed(localizedError(l10n, e)))));
  }
}
