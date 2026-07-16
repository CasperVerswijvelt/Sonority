import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/channel_map.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/settings_section.dart';
import '../widgets/sheet_scaffold.dart';
import 'profile.dart';

/// Opens a read-only detail sheet for one entity within a profile. Mirrors the
/// matching system-overview detail (HT diagram / per-speaker channel cards) but
/// is driven entirely from the stored snapshot, then lists the per-speaker saved
/// settings. Takes the [entity] directly (no route/index), so it works for an
/// unsaved re-snapshot entity too.
Future<void> showEntitySheet(
        BuildContext context, EntitySnapshot entity, SonosSystem? system) =>
    showContentSheet<void>(context, _EntitySheet(entity: entity, system: system));

class _EntitySheet extends StatelessWidget {
  final EntitySnapshot entity;
  final SonosSystem? system;
  const _EntitySheet({required this.entity, required this.system});

  @override
  Widget build(BuildContext context) {
    final e = entity;
    // Same fallback pattern as entitySummary: prefer the live device type, fall
    // back to the captured room name, then a generic label.
    String typeOf(String uuid) =>
        system?.device(uuid)?.typeLabel ?? e.names[uuid] ?? 'Speaker';

    return ContentSheetScaffold(
      title: e.label,
      subtitle: e.kindLabel,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Content: the layout (diagram / per-speaker cards).
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _layout(e, system, typeOf),
            ),
          ),
          // Settings: a flat, sectioned per-speaker breakdown, not cards.
          _savedSettings(context, e, typeOf),
        ],
      ),
    );
  }
}

/// The layout visualization for the entity, matching its system-overview view.
List<Widget> _layout(
    EntitySnapshot e, SonosSystem? system, String Function(String) typeOf) {
  switch (e.kind) {
    case EntityKind.single:
      // A standalone speaker has no channel — type only, no chip.
      return [
        MemberChannelCard(icon: Icons.speaker, type: typeOf(e.primaryUuid)),
      ];

    case EntityKind.homeTheater:
      return [htDiagramForMember(system, e.toMember(), names: e.names)];

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

/// The per-speaker saved-settings section — a flat, divider-led block (settings,
/// not content cards). Settings are stored per speaker UUID; for a home theater
/// the whole-entity audio settings ride the coordinator (soundbar), while
/// satellites typically capture only volume.
Widget _savedSettings(
    BuildContext context, EntitySnapshot e, String Function(String) typeOf) {
  final theme = Theme.of(context);
  final muted = theme.textTheme.bodyMedium
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

  // Ordered UUIDs, primary first (map order), filtered to those that captured
  // something. Same format for HT and group maps.
  final ordered = e.kind == EntityKind.single
      ? [e.primaryUuid]
      : ChannelMap.parse(e.mapSet ?? '').entries.map((x) => x.uuid).toList();
  final withSettings =
      ordered.where((u) => !(e.settings[u]?.isEmpty ?? true)).toList();

  if (withSettings.isEmpty) {
    return SettingsSection(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Text(
          'No speaker settings saved in this profile.',
          textAlign: TextAlign.center,
          style: muted,
        ),
      ),
    ]);
  }
  return SettingsSection(children: [
    for (var i = 0; i < withSettings.length; i++) ...[
      if (i > 0) const Divider(height: 1),
      _SettingsBlock(
        title: typeOf(withSettings[i]),
        role: _roleLabel(e, withSettings[i]),
        rows: e.settings[withSettings[i]]!.describe(),
      ),
    ],
  ]);
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

/// One speaker's captured settings as a flat block: type + role header, then
/// label/value rows. No card — it lives inside a [SettingsSection].
class _SettingsBlock extends StatelessWidget {
  final String title;
  final String? role;
  final List<({String label, String value})> rows;
  const _SettingsBlock(
      {required this.title, required this.role, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
    );
  }
}
