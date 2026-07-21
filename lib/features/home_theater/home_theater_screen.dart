import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../../state/trueplay_controller.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/busy_view.dart';
import '../widgets/card_grid.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/destructive_button.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/refresh_icon_button.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/scroll_footer.dart';
import '../widgets/section_header.dart';
import '../widgets/settings_section.dart';
import '../widgets/trueplay_control.dart';

/// Shows one home theater's current layout and the add/remove-fronts actions.
class HomeTheaterScreen extends ConsumerWidget {
  final String soundbarUuid;
  const HomeTheaterScreen({super.key, required this.soundbarUuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sonosControllerProvider);
    final controller = ref.read(sonosControllerProvider.notifier);
    final system = state.value;

    final member = system?.allMembers
        .where((m) => m.uuid == soundbarUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    final device = system?.device(soundbarUuid);

    // Bonded native members (bar + fronts + rears + sub); Amp fronts excluded.
    final bonded = (system != null && member != null)
        ? <String>{member.uuid, ...member.channelAssignments.values}
              .map((u) => system.device(u))
              .whereType<SonosDevice>()
              .where((d) => !d.isAmp)
              .toList()
        : <SonosDevice>[];

    Future<void> refreshAll() async {
      await controller.refresh();
      if (bonded.isNotEmpty) {
        await ref.read(trueplayControllerProvider.notifier).load(bonded);
      }
    }

    return AppScaffold(
      title: member?.zoneName ?? 'Home theater',
      subtitle: member == null ? null : 'Home theater',
      onRefresh: refreshAll,
      actions: [
        if (member != null && device != null)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Rename room',
            onPressed: () => _rename(context, ref, device, member.zoneName),
          ),
        RefreshIconButton(onRefresh: refreshAll),
      ],
      body: state.isLoading
          ? const BusyView(
              title: 'Updating your home theater…',
              subtitle:
                  'This can take up to ~20 seconds while Sonos reconfigures '
                  'and re-reads the layout.',
            )
          : (member == null || device == null)
          ? const MissingRoomView()
          : _Content(
              system: system!,
              member: member,
              bonded: bonded,
              onRemoveGroup: (channels, label, {bool separateAll = false}) =>
                  _confirmRemoveGroup(
                    context,
                    ref,
                    member,
                    device,
                    channels,
                    label,
                    separateAll: separateAll,
                  ),
              onConfigure: () => context.push('/theater/$soundbarUuid/fronts'),
            ),
    );
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

  Future<void> _confirmRemoveGroup(
    BuildContext context,
    WidgetRef ref,
    ZoneGroupMember member,
    SonosDevice device,
    Set<SonosChannel> channels,
    String label, {
    bool separateAll = false,
  }) async {
    final ok = await confirmDialog(
      context,
      icon: Icons.link_off,
      title: separateAll ? 'Separate home theater?' : 'Remove $label?',
      message: separateAll
          ? 'All extra speakers will be un-bonded and become standalone rooms '
                'again, leaving just the soundbar.'
          : 'These speakers will be un-bonded and become standalone rooms '
                'again. The rest of your home theater stays as it is.',
      confirmLabel: separateAll ? 'Separate' : 'Remove',
    );
    if (!ok || !context.mounted) return;

    final controller = ref.read(sonosControllerProvider.notifier);
    // No success toast — the progress screen already showed the outcome.
    await showBondingProgress(
      context,
      title: separateAll ? 'Separate home theater' : 'Remove $label',
      run: () => controller.removeHtRoles(
        soundbar: member,
        soundbarDevice: device,
        channels: channels,
        label: label,
      ),
    );
  }
}

/// One bonded-speaker group on the HT detail (Fronts / Surrounds / Sub).
class _Group {
  final String label;
  final IconData icon;
  final Set<SonosChannel> channels;
  const _Group(this.label, this.icon, this.channels);
}

const _htGroups = [
  _Group('Fronts', Icons.speaker, {
    SonosChannel.leftFront,
    SonosChannel.rightFront,
  }),
  _Group('Surrounds', Icons.surround_sound, {
    SonosChannel.leftRear,
    SonosChannel.rightRear,
  }),
  _Group('Sub', Icons.graphic_eq, {SonosChannel.sub}),
];

class _Content extends StatelessWidget {
  final SonosSystem system;
  final ZoneGroupMember member;
  final List<SonosDevice> bonded;
  final void Function(
    Set<SonosChannel> channels,
    String label, {
    bool separateAll,
  })
  onRemoveGroup;
  final VoidCallback onConfigure;

  const _Content({
    required this.system,
    required this.member,
    required this.bonded,
    required this.onRemoveGroup,
    required this.onConfigure,
  });

  /// Speaker model per bonded speaker in a group (e.g. "Play:1, Play:1") — the
  /// room name just echoes the HT name, so the model is the useful detail. One
  /// entry per distinct device (an Amp driving both fronts shows once).
  List<String> _models(Set<SonosChannel> channels) {
    final seen = <String>{};
    final out = <String>[];
    for (final c in channels) {
      for (final uuid in member.uuidsForChannel(c)) {
        if (!seen.add(uuid)) continue;
        out.add(system.device(uuid)?.typeLabel ?? 'Speaker');
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = [
      for (final g in _htGroups)
        if (g.channels.any((c) => hasChannel(member, c))) g,
    ];
    // Edge-to-edge list so the Trueplay settings section can be full-bleed
    // (flat, sectioned — a setting, not another content card); content blocks
    // carry their own horizontal padding. Separate sits pinned at the bottom
    // (via ScrollFooter) so the destructive action is always at the end.
    return ScrollFooter(
      padding: const EdgeInsets.symmetric(vertical: 20),
      footer: present.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageGutter,
                20,
                kPageGutter,
                0,
              ),
              child: DestructiveButton(
                icon: Icons.link_off,
                label: 'Separate',
                onPressed: () => onRemoveGroup(
                  {for (final g in present) ...g.channels},
                  'all extra speakers',
                  separateAll: true,
                ),
              ),
            ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              htDiagramForMember(system, member),
              Gap.l,
              FilledButton.icon(
                onPressed: onConfigure,
                // A settings cog reads as "configure this layout"; the sliders
                // glyph (Icons.tune) is reserved for the audio/Trueplay surfaces
                // so a layout action never looks like EQ (which we don't do).
                icon: const Icon(Icons.settings),
                label: const Text('Configure'),
              ),
              Gap.l,
              const SectionHeader('Bonded speakers'),
              if (present.isEmpty)
                Text(
                  'Just the soundbar — no fronts, surrounds or sub bonded yet. '
                  'Tap “Configure” to add some.',
                  style: theme.mutedText,
                )
              else
                CardGrid([
                  for (final g in present)
                    _GroupCard(
                      group: g,
                      models: _models(g.channels),
                      onRemove: () => onRemoveGroup(g.channels, g.label),
                    ),
                ]),
            ],
          ),
        ),
        Gap.m,
        SettingsSection(children: [TrueplayControl(devices: bonded)]),
        if (member.hasDedicatedFronts)
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
            child: Text(
              'Trueplay can only be measured from the Sonos app on iOS — '
              'tune the home theater, and the fronts separately as a stereo '
              'pair. Heads-up: Sonos often clears a tuning when speakers are '
              'bonded/unbonded, so you may see “Not tuned” after changing the '
              'layout and have to redo it. Sonority only toggles a stored '
              'tuning.',
              style: theme.mutedText,
            ),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  final _Group group;
  final List<String> models;
  final VoidCallback onRemove;
  const _GroupCard({
    required this.group,
    required this.models,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(group.icon, color: theme.colorScheme.primary),
        title: Text(group.label),
        subtitle: Text(models.isEmpty ? 'Bonded' : models.join(', ')),
        trailing: TextButton(
          onPressed: onRemove,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: const Text('Remove'),
        ),
      ),
    );
  }
}
