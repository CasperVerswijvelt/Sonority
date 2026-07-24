import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/localized_error.dart';
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

    final member = system?.memberByUuid(soundbarUuid);
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
      title: member?.zoneName ?? context.l10n.htHomeTheater,
      subtitle: member == null ? null : context.l10n.htHomeTheater,
      onRefresh: refreshAll,
      actions: [
        if (member != null && device != null)
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: context.l10n.htRenameRoomTooltip,
            onPressed: () => _rename(context, ref, device, member.zoneName),
          ),
        RefreshIconButton(onRefresh: refreshAll),
      ],
      body: state.isLoading
          ? BusyView(
              title: context.l10n.htUpdatingTitle,
              subtitle: context.l10n.htUpdatingSubtitle,
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
    final l10n = context.l10n;
    try {
      await ref
          .read(sonosControllerProvider.notifier)
          .renameRoom(device: device, name: name);
      messenger.showSnackBar(SnackBar(content: Text(l10n.htRenamedTo(name))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(l10n.htRenameFailed(localizedError(l10n, e)))));
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
    final l10n = context.l10n;
    final ok = await confirmDialog(
      context,
      icon: Icons.link_off,
      title: separateAll
          ? l10n.htSeparateConfirmTitle
          : l10n.htRemoveConfirmTitle(label),
      message:
          separateAll ? l10n.htSeparateMessage : l10n.htRemoveMessage,
      confirmLabel: separateAll ? l10n.htSeparate : l10n.actionRemove,
    );
    if (!ok || !context.mounted) return;

    final controller = ref.read(sonosControllerProvider.notifier);
    // No success toast — the progress screen already showed the outcome.
    await showBondingProgress(
      context,
      title: separateAll
          ? l10n.htSeparateProgressTitle
          : l10n.htRemoveProgressTitle(label),
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

List<_Group> _htGroupsFor(AppLocalizations l10n) => [
      _Group(l10n.htGroupFronts, Icons.speaker, {
        SonosChannel.leftFront,
        SonosChannel.rightFront,
      }),
      _Group(l10n.htGroupSurrounds, Icons.surround_sound, {
        SonosChannel.leftRear,
        SonosChannel.rightRear,
      }),
      _Group(l10n.htGroupSubwoofer, Icons.graphic_eq, {SonosChannel.sub}),
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
  List<String> _models(Set<SonosChannel> channels, String fallback) {
    final seen = <String>{};
    final out = <String>[];
    for (final c in channels) {
      for (final uuid in member.uuidsForChannel(c)) {
        if (!seen.add(uuid)) continue;
        out.add(system.device(uuid)?.typeLabel ?? fallback);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final present = [
      for (final g in _htGroupsFor(l10n))
        if (g.channels.any((c) => hasChannel(member, c))) g,
    ];
    // The settings register (Trueplay) and the destructive Separate both pin to
    // the bottom via ScrollFooter: a full-bleed, flat, sectioned Trueplay row
    // (a setting, not another content card) with its single leading divider,
    // then Separate last so the destructive action is at the very end. Content
    // blocks above carry their own horizontal padding.
    return ScrollFooter(
      padding: const EdgeInsets.symmetric(vertical: 20),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSection(children: [TrueplayControl(devices: bonded)]),
          if (member.hasDedicatedFronts)
            Padding(
              padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
              child: Text(l10n.htTrueplayNote, style: theme.mutedText),
            ),
          if (present.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 0),
              child: DestructiveButton(
                icon: Icons.link_off,
                label: l10n.htSeparate,
                onPressed: () => onRemoveGroup(
                  {for (final g in present) ...g.channels},
                  l10n.htAllExtraSpeakers,
                  separateAll: true,
                ),
              ),
            ),
        ],
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
                label: Text(l10n.htConfigure),
              ),
              Gap.l,
              SectionHeader(l10n.htBondedSpeakers),
              if (present.isEmpty)
                Text(
                  l10n.htNoBonded,
                  style: theme.mutedText,
                )
              else
                CardGrid([
                  for (final g in present)
                    _GroupCard(
                      group: g,
                      models: _models(g.channels, l10n.htSpeakerFallback),
                      onRemove: () => onRemoveGroup(g.channels, g.label),
                    ),
                ]),
              // Breathing room between the content and the pinned settings
              // divider (which otherwise hugs the last bonded-speaker card).
              Gap.m,
            ],
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
      child: ListTile(
        leading: Icon(group.icon, color: theme.colorScheme.primary),
        title: Text(group.label),
        subtitle: Text(models.isEmpty ? context.l10n.htBonded : models.join(', ')),
        trailing: TextButton(
          onPressed: onRemove,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: Text(context.l10n.actionRemove),
        ),
      ),
    );
  }
}
