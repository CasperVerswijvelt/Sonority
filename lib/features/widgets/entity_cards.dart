import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import 'diagram_labels.dart';
import 'entity_glyph.dart';
import 'entity_icons.dart';
import 'pill_chip.dart';

// -----------------------------------------------------------------------------
// View model
//
// The card renders one of these, never a domain `ZoneGroupMember` directly, so a
// card can't accidentally surface live-only state (`satellites`, `ip`, …) — only
// the fields it shows live here. Built either from a LIVE member (`fromMember`,
// system guaranteed) or from a SNAPSHOT member (`fromSnapshot`, system may be
// null — the throwaway member a profile builds via `EntitySnapshot.toMember()`);
// the snapshot factory forces `reachable = true` (a stored config is always
// "openable"), fixing the case where a momentarily-offline speaker used to
// disable the profile tile.
//
// COMPOSITION is carried as `chips` (visual pills), not a `·`-joined string, so
// an entity's kind/parts read at a glance and different kinds look distinct.
// -----------------------------------------------------------------------------

/// One composition pill on an entity card (an icon + short label).
typedef EntityChip = ({IconData icon, String label});

/// The compact tile for any entity kind — the overview (home theaters, groups &
/// singles) and every profile tile. [subtitle] is the secondary line (soundbar
/// or speaker type); [chips] are the composition pills (parts of a home theater,
/// a group's kind + size). A single standalone speaker has just a [subtitle].
class EntityCardModel {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<EntityChip> chips;

  /// Whether the speaker is currently usable — only a live single can be false;
  /// snapshots and HT/group tiles are always openable.
  final bool reachable;

  const EntityCardModel({
    required this.icon,
    required this.title,
    this.subtitle,
    this.chips = const [],
    this.reachable = true,
  });

  factory EntityCardModel.fromMember(SonosSystem system, ZoneGroupMember m) {
    final d = system.device(m.uuid);
    return _build(system, m, reachable: d == null || d.reachable);
  }

  factory EntityCardModel.fromSnapshot(SonosSystem? system, ZoneGroupMember m) =>
      _build(system, m, reachable: true);

  static EntityCardModel _build(SonosSystem? system, ZoneGroupMember m,
      {required bool reachable}) {
    if (m.isHomeTheater) {
      final type = system?.device(m.uuid)?.typeLabel ?? 'Soundbar';
      final chips = <EntityChip>[
        if (hasChannel(m, SonosChannel.leftFront) ||
            hasChannel(m, SonosChannel.rightFront))
          (icon: Icons.speaker, label: 'Fronts'),
        if (hasChannel(m, SonosChannel.leftRear) ||
            hasChannel(m, SonosChannel.rightRear))
          (icon: Icons.surround_sound, label: 'Surrounds'),
        if (hasChannel(m, SonosChannel.sub))
          (icon: Icons.graphic_eq, label: 'Subwoofer'),
      ];
      return EntityCardModel(
        icon: Icons.surround_sound,
        title: m.zoneName,
        subtitle: type,
        chips: chips.isEmpty
            ? const [(icon: Icons.info_outline, label: 'No extra speakers')]
            : chips,
      );
    }
    if (m.isGroup) {
      return EntityCardModel(
        icon: groupKindIcon(m.groupKind),
        title: m.zoneName,
        // No per-speaker type list — tap through for speaker details.
        chips: [
          (icon: groupKindIcon(m.groupKind), label: groupKindLabel(m.groupKind)),
          (icon: Icons.speaker, label: '${m.groupChannels.length} speakers'),
          if (m.subUuid != null) (icon: Icons.graphic_eq, label: 'Sub'),
        ],
      );
    }
    return EntityCardModel(
      icon: Icons.speaker_outlined,
      title: m.zoneName,
      // The device may not be on the LAN (a profile snapshots a config that
      // isn't necessarily live), so fall back to a generic label rather than an
      // empty subtitle.
      subtitle: system?.device(m.uuid)?.typeLabel ?? 'Standalone speaker',
      reachable: reachable,
    );
  }
}

/// Shown wherever an unreachable speaker ([SonosDevice.reachable] == false)
/// surfaces — we have it from the topology but couldn't read its description.
const unreachableSpeakerHint =
    'Couldn’t read this speaker’s details — check it’s powered on and on the '
    'same network.';

/// The one entity card — a dumb renderer over [EntityCardModel], shared by the
/// system overview (live) and the profile detail list (snapshot). [onTap] adds a
/// chevron; [footer] (e.g. saved-settings pills) stacks under the composition. An
/// unreachable single is flagged with a warning glyph + hint and made
/// non-tappable regardless of the passed [onTap].
class EntityCard extends StatelessWidget {
  final EntityCardModel model;
  final VoidCallback? onTap;
  final Widget? footer;
  const EntityCard({super.key, required this.model, this.onTap, this.footer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unreachable = !model.reachable;
    final tap = unreachable ? null : onTap;

    return Padding(
      padding: const EdgeInsets.only(bottom: kCardGap),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(kCardRadius),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                EntityGlyph(
                  icon: unreachable ? Icons.warning_amber_rounded : model.icon,
                  background: unreachable ? scheme.errorContainer : null,
                  foreground: unreachable ? scheme.onErrorContainer : null,
                ),
                Gap.m,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.title, style: theme.textTheme.bodyLarge),
                      if (unreachable)
                        Text(unreachableSpeakerHint,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.error))
                      else if (model.subtitle != null)
                        Text(model.subtitle!,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      if (!unreachable && model.chips.isNotEmpty) ...[
                        Gap.s,
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in model.chips)
                              PillChip(
                                  icon: c.icon,
                                  text: c.label,
                                  color: scheme.primary),
                          ],
                        ),
                      ],
                      if (footer != null) ...[Gap.s, footer!],
                    ],
                  ),
                ),
                if (tap != null) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
