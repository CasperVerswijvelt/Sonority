import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/channel_map.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy_view.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/speaker_diagram.dart';
import 'profile.dart';
import 'profile_controller.dart';

/// Read-only detail for one entity within a profile. Mirrors the matching
/// system-overview detail (HT diagram / per-speaker channel cards) but is driven
/// entirely from the stored snapshot, then lists the per-speaker saved settings.
class ProfileEntityDetailScreen extends ConsumerWidget {
  final String profileId;
  final int entityIndex;
  const ProfileEntityDetailScreen(
      {super.key, required this.profileId, required this.entityIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref
        .watch(profilesProvider)
        .value
        ?.where((p) => p.id == profileId)
        .cast<Profile?>()
        .firstOrNull;
    final system = ref.watch(sonosControllerProvider).value;

    final e = (profile != null && entityIndex < profile.entities.length)
        ? profile.entities[entityIndex]
        : null;
    if (e == null) {
      return const AppScaffold(title: 'Entity', body: MissingRoomView());
    }

    // Same fallback pattern as entitySummary: prefer the live device type, fall
    // back to the captured room name, then a generic label.
    String typeOf(String uuid) =>
        system?.device(uuid)?.typeLabel ?? e.names[uuid] ?? 'Speaker';

    return AppScaffold(
      title: e.label,
      subtitle: e.kindLabel,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ..._layout(context, e, system, typeOf),
          Gap.l,
          ..._savedSettings(context, e, typeOf),
        ],
      ),
    );
  }

  /// The layout visualization for the entity, matching its system-overview view.
  List<Widget> _layout(BuildContext context, EntitySnapshot e,
      SonosSystem? system, String Function(String) typeOf) {
    switch (e.kind) {
      case EntityKind.single:
        return [
          MemberChannelCard(
            icon: Icons.speaker,
            type: typeOf(e.primaryUuid),
            channel: 'Standalone',
          ),
        ];

      case EntityKind.homeTheater:
        final m = e.toMember();
        return [
          SpeakerDiagram(
            soundbarLabel: typeOf(e.primaryUuid),
            frontLeftLabel: typeForChannel(
                system, m, SonosChannel.leftFront,
                names: e.names),
            frontRightLabel: typeForChannel(
                system, m, SonosChannel.rightFront,
                names: e.names),
            rearLeftLabel: typeForChannel(system, m, SonosChannel.leftRear,
                names: e.names),
            rearRightLabel: typeForChannel(system, m, SonosChannel.rightRear,
                names: e.names),
            subCount: m.subUuids.length,
          ),
        ];

      case EntityKind.stereoPair:
      case EntityKind.zone:
      case EntityKind.custom:
        final m = e.toMember();
        return [
          for (final entry in m.groupChannels.entries) ...[
            MemberChannelCard(
              icon: Icons.speaker,
              type: typeOf(entry.key),
              channel: groupChannelShort(entry.value),
            ),
            Gap.s,
          ],
          if (m.subUuid != null)
            MemberChannelCard(
              icon: Icons.graphic_eq,
              type: typeOf(m.subUuid!),
              channel: 'Sub',
            ),
        ];
    }
  }

  /// The per-speaker saved-settings section. Settings are stored per speaker
  /// UUID; for a home theater the whole-entity audio settings ride the
  /// coordinator (soundbar), while satellites typically capture only volume.
  List<Widget> _savedSettings(
      BuildContext context, EntitySnapshot e, String Function(String) typeOf) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    // Ordered UUIDs, primary first (map order), filtered to those that captured
    // something. Same format for HT and group maps.
    final ordered = e.kind == EntityKind.single
        ? [e.primaryUuid]
        : ChannelMap.parse(e.mapSet ?? '').entries.map((x) => x.uuid).toList();
    final withSettings = ordered
        .where((u) => !(e.settings[u]?.isEmpty ?? true))
        .toList();

    return [
      Text('Saved settings', style: theme.textTheme.titleSmall),
      Gap.s,
      if (withSettings.isEmpty)
        Text('No speaker settings saved in this profile.', style: muted)
      else
        for (final uuid in withSettings) ...[
          _SettingsCard(
            title: typeOf(uuid),
            role: _roleLabel(e, uuid),
            rows: e.settings[uuid]!.describe(),
          ),
          Gap.s,
        ],
    ];
  }

  /// Short role of [uuid] within the entity, for the settings-card subtitle.
  String? _roleLabel(EntitySnapshot e, String uuid) {
    if (e.mapSet == null) return null;
    switch (e.kind) {
      case EntityKind.single:
        return null;
      case EntityKind.stereoPair:
      case EntityKind.zone:
      case EntityKind.custom:
        final m = e.toMember();
        if (uuid == m.subUuid) return 'Sub';
        final ch = m.groupChannels[uuid];
        return ch == null ? null : groupChannelShort(ch);
      case EntityKind.homeTheater:
        if (uuid == e.primaryUuid) return 'Soundbar';
        final m = e.toMember();
        final channels = m.channelAssignments.entries
            .where((a) => a.value == uuid)
            .map((a) => a.key)
            .toSet();
        final parts = <String>[
          if (channels.contains(SonosChannel.leftFront) ||
              channels.contains(SonosChannel.rightFront))
            'Front',
          if (channels.contains(SonosChannel.leftRear)) 'Surround L',
          if (channels.contains(SonosChannel.rightRear)) 'Surround R',
          if (channels.contains(SonosChannel.sub)) 'Sub',
        ];
        return parts.isEmpty ? null : parts.join(' · ');
    }
  }
}

/// One speaker's captured settings: type + role header, then label/value rows.
class _SettingsCard extends StatelessWidget {
  final String title;
  final String? role;
  final List<({String label, String value})> rows;
  const _SettingsCard(
      {required this.title, required this.role, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (role != null)
              Text(role!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            Gap.s,
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r.label,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    Text(r.value,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
