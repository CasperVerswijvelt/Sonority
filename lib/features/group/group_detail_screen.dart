import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/busy_view.dart';
import '../widgets/destructive_button.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/refresh_icon_button.dart';
import '../widgets/rename_dialog.dart';

/// Detail page for a bonded speaker group (stereo pair / zone / custom): the
/// group kind, one card per member speaker (type + channel chip), and rename /
/// separate actions. Reached by tapping a group on the discovery overview.
class GroupDetailScreen extends ConsumerWidget {
  final String uuid;
  const GroupDetailScreen({super.key, required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(sonosControllerProvider).value;
    final group = system?.allMembers
        .where((m) => m.uuid == uuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    Future<void> refresh() =>
        ref.read(sonosControllerProvider.notifier).refresh();

    return AppScaffold(
      title: group?.zoneName ?? 'Speaker group',
      subtitle: (group != null && group.isGroup)
          ? groupKindLabel(group.groupKind)
          : null,
      onRefresh: refresh,
      actions: [
        if (system != null &&
            group != null &&
            system.device(group.uuid) != null)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Rename group',
            onPressed: () => _rename(
                context, ref, system.device(group.uuid)!, group.zoneName),
          ),
        RefreshIconButton(onRefresh: refresh),
      ],
      body: (system == null || group == null || !group.isGroup)
          ? const MissingRoomView()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final e in group.groupChannels.entries) ...[
                  MemberChannelCard(
                    icon: Icons.speaker,
                    type: system.device(e.key)?.typeLabel ?? 'Speaker',
                    channel: groupChannelShort(e.value),
                  ),
                  Gap.s,
                ],
                if (group.subUuid != null) ...[
                  MemberChannelCard(
                    icon: Icons.graphic_eq,
                    type: system.device(group.subUuid!)?.typeLabel ?? 'Sub',
                    channel: 'Sub',
                  ),
                  Gap.s,
                ],
                Gap.l,
                DestructiveButton(
                  icon: Icons.link_off,
                  label: 'Separate',
                  onPressed: () => _confirmSeparate(context, ref, group),
                ),
              ],
            ),
    );
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
    // The group is gone now — return to the overview.
    if (outcome == BondingOutcome.success && context.mounted) context.pop();
  }
}
