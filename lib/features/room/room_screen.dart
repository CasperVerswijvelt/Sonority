import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/busy_view.dart';
import '../widgets/identify_controls.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/settings_section.dart';
import '../widgets/sheet_scaffold.dart';
import '../widgets/trueplay_control.dart';

/// Opens a standalone room (or stereo pair) as a modal sheet. Currently hosts the
/// Trueplay control (kept off the main list to avoid clutter) plus rename.
Future<void> showRoomSheet(BuildContext context, String uuid) =>
    showSheet<void>(context, _RoomSheet(uuid: uuid));

class _RoomSheet extends ConsumerWidget {
  final String uuid;
  const _RoomSheet({required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(sonosControllerProvider).value;
    final member = system?.allMembers
        .where((m) => m.uuid == uuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;

    if (member == null) {
      return const SheetScaffold(
        title: 'Room',
        body: Padding(padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }

    // Single standalone speaker (stereo pairs are groups → the group sheet).
    final device = system!.device(uuid);
    final devices = [if (device != null) device];
    // Soundbars this speaker could join as a front/surround (same rule the
    // overview uses to list home theaters).
    final soundbars = system.allMembers
        .where((m) =>
            m.isHomeTheater || (system.device(m.uuid)?.isSoundbar ?? false))
        .toList();

    return SheetScaffold(
      title: member.zoneName,
      subtitle: 'Room',
      trailing: device == null
          ? null
          : IconButton(
              icon: const Icon(Icons.drive_file_rename_outline),
              tooltip: 'Rename room',
              onPressed: () => _rename(context, ref, device, member.zoneName),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Content: the speaker itself — a standalone speaker has no channel,
          // so no chip (parallels the group sheet's per-speaker cards).
          if (device != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(kPageGutter, 4, kPageGutter, 16),
              child: MemberChannelCard(
                icon: Icons.speaker,
                type: device.typeLabel,
                // Standalone speaker → both LED blink and the chime apply.
                trailing: speakerIdentifyButton(device, allowChime: true),
              ),
            ),
          // Put this speaker to use: shortcuts into the bonding flows so a
          // standalone room isn't a dead end (the flows do their own validation).
          // Descriptive rows (title + what it does), not bare buttons.
          _ActionRow(
            icon: Icons.speaker_group_outlined,
            title: 'Group with another speaker',
            subtitle: 'Stereo pair, full-range zone, or custom L/R',
            onTap: () => _leaveTo(context, '/group'),
          ),
          if (soundbars.isNotEmpty)
            _ActionRow(
              icon: Icons.surround_sound,
              title: 'Add to a home theater',
              subtitle: 'As a front, surround, or sub',
              onTap: () => _addToHomeTheater(context, soundbars),
            ),
          Gap.s,
          // Settings: a flat, sectioned Trueplay row, not another card.
          SettingsSection(children: [TrueplayControl(devices: devices)]),
        ],
      ),
    );
  }
}

/// Closes the room sheet, then pushes [location] — pop-then-push so a root-level
/// guided flow doesn't stack on top of the modal sheet.
void _leaveTo(BuildContext context, String location) {
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.push(location);
}

/// "Add to a home theater": route into the HT setup flow keyed to a soundbar —
/// straight through with one soundbar, or a small chooser when there are several.
Future<void> _addToHomeTheater(
    BuildContext context, List<ZoneGroupMember> soundbars) async {
  String? target;
  if (soundbars.length == 1) {
    target = soundbars.first.uuid;
  } else {
    target = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to which home theater?'),
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

Future<void> _rename(BuildContext context, WidgetRef ref, SonosDevice device,
    String current) async {
  final name = await showRenameDialog(context, current);
  if (name == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(sonosControllerProvider.notifier)
        .renameRoom(device: device, name: name);
    messenger.showSnackBar(SnackBar(content: Text('Renamed to “$name”.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
  }
}
