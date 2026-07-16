import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/busy_view.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/settings_section.dart';
import '../widgets/sheet_scaffold.dart';
import '../widgets/trueplay_control.dart';

/// Opens a standalone room (or stereo pair) as a modal sheet. Currently hosts the
/// Trueplay control (kept off the main list to avoid clutter) plus rename.
Future<void> showRoomSheet(BuildContext context, String uuid) =>
    showContentSheet<void>(context, _RoomSheet(uuid: uuid));

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
      return const ContentSheetScaffold(
        title: 'Room',
        body: Padding(padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }

    // Single standalone speaker (stereo pairs are groups → the group sheet).
    final device = system!.device(uuid);
    final devices = [if (device != null) device];

    return ContentSheetScaffold(
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: MemberChannelCard(icon: Icons.speaker, type: device.typeLabel),
            ),
          // Settings: a flat, sectioned Trueplay row, not another card.
          SettingsSection(children: [TrueplayControl(devices: devices)]),
          const SizedBox(height: 8),
        ],
      ),
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
