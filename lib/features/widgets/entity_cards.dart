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

/// Colour role for an entity-card chip. Resolved to a real colour at render
/// (the model is built without a [BuildContext]): [normal] = the composition
/// accent, [warning] = a caution (e.g. a zone that can drop out), [positive] = a
/// highlight (e.g. a config the Sonos app won't build).
enum EntityChipTone { normal, warning, positive }

/// One composition pill on an entity card (an icon + short label + tone).
class EntityChip {
  final IconData icon;
  final String label;
  final EntityChipTone tone;
  const EntityChip(this.icon, this.label,
      {this.tone = EntityChipTone.normal});
}

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
          const EntityChip(Icons.speaker, 'Fronts'),
        if (hasChannel(m, SonosChannel.leftRear) ||
            hasChannel(m, SonosChannel.rightRear))
          const EntityChip(Icons.surround_sound, 'Surrounds'),
        if (hasChannel(m, SonosChannel.sub))
          const EntityChip(Icons.graphic_eq, 'Subwoofer'),
      ];
      return EntityCardModel(
        icon: Icons.surround_sound,
        title: m.zoneName,
        subtitle: type,
        chips: [
          if (chips.isEmpty)
            const EntityChip(Icons.info_outline, 'No extra speakers')
          else
            ...chips,
          ..._metaChips(system, m),
        ],
      );
    }
    if (m.isGroup) {
      return EntityCardModel(
        icon: groupKindIcon(m.groupKind),
        title: m.zoneName,
        // No per-speaker type list — tap through for speaker details.
        chips: [
          EntityChip(groupKindIcon(m.groupKind), groupKindLabel(m.groupKind)),
          EntityChip(Icons.speaker, '${m.groupChannels.length} speakers'),
          if (m.subUuid != null) const EntityChip(Icons.graphic_eq, 'Sub'),
          ..._metaChips(system, m),
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

  /// Trailing status/highlight chips shared by HT + group cards: a drop-out
  /// caution for a large zone, and a positive "not in the Sonos app" flag for a
  /// config the official app won't build.
  static List<EntityChip> _metaChips(SonosSystem? system, ZoneGroupMember m) => [
        if (m.isZone && m.groupChannels.length >= kZoneWarnSize)
          const EntityChip(Icons.warning_amber_rounded, 'Can drop out',
              tone: EntityChipTone.warning),
        if (unofficialConfigLabel(system, m) != null)
          const EntityChip(Icons.lock_open, 'Not in the Sonos app',
              tone: EntityChipTone.positive),
      ];
}

/// A short reason an entity is a config the **Sonos app won't build** (so we can
/// flag it as a Sonority-only capability), or null for an ordinary config. Kept
/// conservative — only cases we can detect confidently, no model whitelist:
/// - a home theater with dedicated front L/R,
/// - a stereo pair of two different models,
/// - a custom per-speaker L/R/Both group.
/// The mixed-pair case needs a live [system] to compare models; skipped when the
/// system is absent (a profile snapshot).
String? unofficialConfigLabel(SonosSystem? system, ZoneGroupMember m) {
  if (m.isHomeTheater && m.hasDedicatedFronts) return 'Dedicated fronts';
  if (m.groupKind == GroupKind.custom) return 'Custom layout';
  if (m.isStereoPair && system != null) {
    final models = m.groupChannels.keys
        .map((u) => system.device(u)?.modelName)
        .whereType<String>()
        .toSet();
    if (models.length > 1) return 'Mixed-model pair';
  }
  return null;
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
                                  color: switch (c.tone) {
                                    EntityChipTone.normal => scheme.primary,
                                    EntityChipTone.warning => scheme.error,
                                    EntityChipTone.positive => scheme.tertiary,
                                  }),
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
