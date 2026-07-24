import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'bonding_shortcuts.dart';

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
    // Soundbars this speaker could join as a front/surround.
    final soundbars = homeTheaterTargets(system);

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
            if (canGroupSpeaker(system, uuid))
              ActionRow(
                icon: Icons.speaker_group_outlined,
                title: context.l10n.roomGroupWith,
                subtitle: context.l10n.roomGroupWithSubtitle,
                onTap: () => leaveTo(context, '/group?speaker=$uuid'),
              ),
            if (soundbars.isNotEmpty)
              ActionRow(
                icon: Icons.surround_sound,
                title: context.l10n.roomAddToHomeTheater,
                subtitle: context.l10n.roomAddToHomeTheaterSubtitle,
                onTap: () => addToHomeTheater(context, soundbars, speaker: uuid),
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
