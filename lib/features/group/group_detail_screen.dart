import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/busy_view.dart';
import '../widgets/card_grid.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/destructive_button.dart';
import '../widgets/identify_controls.dart';
import '../widgets/info_note.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/scroll_footer.dart';
import '../widgets/section_header.dart';

/// A bonded speaker group (stereo pair / zone / custom) shown as a pushed page:
/// the group kind, one card per member speaker (type + channel), a rename action,
/// and a Separate button. Opened by tapping a group on the discovery overview.
///
/// A page (not a sheet), matching the home-theater detail — both are bonded
/// configs, so "tap a bonded thing" always opens a page, and Separate can push
/// the bonding progress screen without stacking a page over a sheet.
class GroupDetailScreen extends ConsumerWidget {
  final String uuid;
  const GroupDetailScreen({super.key, required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sonosControllerProvider);
    final system = state.value;
    final group = system?.allMembers
        .where((m) => m.uuid == uuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;

    if (state.isLoading) {
      return const AppScaffold(
        title: 'Speaker group',
        body: BusyView(title: 'Updating…'),
      );
    }
    if (system == null || group == null || !group.isGroup) {
      return const AppScaffold(
        title: 'Speaker group',
        body: Padding(padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }

    final device = system.device(group.uuid);
    return AppScaffold(
      title: group.zoneName,
      subtitle: groupKindLabel(group.groupKind),
      actions: [
        if (device != null)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Rename group',
            onPressed: () => _rename(context, ref, device, group.zoneName),
          ),
      ],
      // Separate is pinned to the bottom (via ScrollFooter) — always the last
      // thing on the page, whether the member list fits or has to scroll.
      body: ScrollFooter(
        padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 20),
        footer: DestructiveButton(
          icon: Icons.link_off,
          label: 'Separate',
          onPressed: () => _confirmSeparate(context, ref, group),
        ),
        children: [
          const SectionHeader('Speakers'),
          CardGrid([
            for (final e in group.groupChannels.entries)
              MemberChannelCard(
                icon: Icons.speaker,
                type: system.device(e.key)?.typeLabel ?? 'Speaker',
                channel: groupChannelShort(e.value),
                // Bonded member → LED only (chiming one plays the whole group).
                trailing: speakerIdentifyButton(system.device(e.key)),
              ),
            if (group.subUuid != null)
              MemberChannelCard(
                icon: Icons.graphic_eq,
                type: system.device(group.subUuid!)?.typeLabel ?? 'Sub',
                channel: 'Sub',
                trailing: speakerIdentifyButton(system.device(group.subUuid!)),
              ),
          ]),
          if (group.isZone && group.groupChannels.length >= kZoneWarnSize) ...[
            Gap.m,
            const InfoNote(
              'Large zones can drop out for the first minute after audio '
              'starts, and mixed or older speakers may keep dropping. Play '
              'something to confirm it stays stable for you.',
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
  BuildContext context,
  WidgetRef ref,
  ZoneGroupMember group,
) async {
  final ok = await confirmDialog(
    context,
    icon: Icons.link_off,
    title: 'Separate group?',
    message:
        'The speakers become standalone rooms again. Their original room '
        'names will be restored.',
    confirmLabel: 'Separate',
  );
  if (!ok || !context.mounted) return;
  final controller = ref.read(sonosControllerProvider.notifier);
  final router = GoRouter.of(context);
  final outcome = await showBondingProgress(
    context,
    title: 'Separate group',
    run: () => controller.separateGroup(group),
  );
  // The group is gone now — return to the overview.
  if (outcome == BondingOutcome.success) router.pop();
}
