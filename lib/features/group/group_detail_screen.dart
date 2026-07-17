import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/busy_view.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/destructive_button.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/identify_controls.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/sheet_scaffold.dart';

/// Opens a bonded speaker group (stereo pair / zone / custom) as a modal sheet:
/// the group kind, one card per member speaker (type + channel), a rename action,
/// and a pinned Separate. Opened by tapping a group on the discovery overview.
Future<void> showGroupSheet(BuildContext context, String uuid) =>
    showSheet<void>(context, _GroupSheet(uuid: uuid));

class _GroupSheet extends ConsumerWidget {
  final String uuid;
  const _GroupSheet({required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(sonosControllerProvider).value;
    final group = system?.memberByUuid(uuid);

    if (system == null || group == null || !group.isGroup) {
      return const SheetScaffold(
        title: 'Speaker group',
        body: Padding(padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }

    final device = system.device(group.uuid);
    return SheetScaffold(
      title: group.zoneName,
      subtitle: groupKindLabel(group.groupKind),
      trailing: device == null
          ? null
          : IconButton(
              icon: const Icon(Icons.drive_file_rename_outline),
              tooltip: 'Rename group',
              onPressed: () => _rename(context, ref, device, group.zoneName),
            ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(kPageGutter, 4, kPageGutter, 20),
        child: Column(
          // Bonded member → LED only (chiming one plays the whole group).
          children: groupMemberCards(
            group,
            typeOf: (uuid) => system.device(uuid)?.typeLabel ?? 'Speaker',
            trailing: (uuid) => speakerIdentifyButton(system.device(uuid)),
          ),
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
        child: DestructiveButton(
          icon: Icons.link_off,
          label: 'Separate',
          onPressed: () => _confirmSeparate(context, ref, group),
        ),
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

Future<void> _confirmSeparate(
    BuildContext context, WidgetRef ref, ZoneGroupMember group) async {
  final ok = await confirmDialog(
    context,
    icon: Icons.link_off,
    title: 'Separate group?',
    message: 'The speakers become standalone rooms again. Their original room '
        'names will be restored.',
    confirmLabel: 'Separate',
  );
  if (!ok || !context.mounted) return;
  final controller = ref.read(sonosControllerProvider.notifier);
  final outcome = await showBondingProgress(
    context,
    title: 'Separate group',
    run: () => controller.separateGroup(group),
  );
  // The group is gone now — close the sheet.
  if (outcome == BondingOutcome.success && context.mounted) {
    Navigator.of(context).pop();
  }
}
