import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import 'bondable_speaker_tile.dart';
import 'diagram_labels.dart';
import 'entity_icons.dart';
import 'pill_chip.dart';

// -----------------------------------------------------------------------------
// View models
//
// The cards render one of these, never a domain `ZoneGroupMember` directly. Each
// model is built either from a LIVE member (`fromMember`, system guaranteed) or
// from a SNAPSHOT member (`fromSnapshot`, system may be null) — the throwaway
// member the profile builds via `EntitySnapshot.toMember()`. Only the fields a
// card actually shows live here, so the snapshot path can't accidentally surface
// live-only state (`reachable`, `satellites`, `ip`, …): the snapshot factory sets
// `reachable = true` (a stored config is always "openable"), fixing the case
// where a momentarily-offline speaker used to disable the profile tile.
// -----------------------------------------------------------------------------

/// A home theater: soundbar model + which extra-speaker groups are bonded.
class TheaterCardModel {
  final String title;
  final String soundbarLabel;
  final bool hasFronts;
  final bool hasSurrounds;
  final bool hasSub;

  const TheaterCardModel({
    required this.title,
    required this.soundbarLabel,
    required this.hasFronts,
    required this.hasSurrounds,
    required this.hasSub,
  });

  factory TheaterCardModel.fromMember(
          SonosSystem system, ZoneGroupMember member) =>
      _build(system, member);
  factory TheaterCardModel.fromSnapshot(
          SonosSystem? system, ZoneGroupMember member) =>
      _build(system, member);

  static TheaterCardModel _build(SonosSystem? system, ZoneGroupMember m) =>
      TheaterCardModel(
        title: m.zoneName,
        soundbarLabel: system?.device(m.uuid)?.modelName ?? 'Soundbar',
        hasFronts: hasChannel(m, SonosChannel.leftFront) ||
            hasChannel(m, SonosChannel.rightFront),
        hasSurrounds: hasChannel(m, SonosChannel.leftRear) ||
            hasChannel(m, SonosChannel.rightRear),
        hasSub: hasChannel(m, SonosChannel.sub),
      );
}

/// A bonded speaker group (stereo pair / zone / custom).
class GroupCardModel {
  final String title;
  final IconData icon;
  final String subtitle;

  const GroupCardModel(
      {required this.title, required this.icon, required this.subtitle});

  factory GroupCardModel.fromMember(
          SonosSystem system, ZoneGroupMember member) =>
      _build(system, member);
  factory GroupCardModel.fromSnapshot(
          SonosSystem? system, ZoneGroupMember member) =>
      _build(system, member);

  static GroupCardModel _build(SonosSystem? system, ZoneGroupMember m) {
    final memberUuids = m.groupChannels.keys.toList();
    final types = memberUuids
        .map((u) => system?.device(u)?.typeLabel)
        .whereType<String>()
        .toList();
    return GroupCardModel(
      title: m.zoneName,
      icon: groupKindIcon(m.groupKind),
      subtitle: [
        groupKindLabel(m.groupKind),
        '${memberUuids.length} speakers',
        if (types.isNotEmpty) types.join(', '),
        if (m.subUuid != null) 'Sub',
      ].join(' · '),
    );
  }
}

/// A single standalone speaker room.
class SingleCardModel {
  final String title;
  final String typeLabel;

  /// Whether the speaker is currently usable. Always true for a snapshot (a
  /// stored profile entity is always openable regardless of live reachability).
  final bool reachable;

  const SingleCardModel(
      {required this.title, required this.typeLabel, required this.reachable});

  factory SingleCardModel.fromMember(
      SonosSystem system, ZoneGroupMember member) {
    final d = system.device(member.uuid);
    return SingleCardModel(
      title: member.zoneName,
      typeLabel: d?.typeLabel ?? '',
      reachable: d == null || d.reachable,
    );
  }

  factory SingleCardModel.fromSnapshot(
          SonosSystem? system, ZoneGroupMember member) =>
      SingleCardModel(
        title: member.zoneName,
        // The device may not be on the LAN (a profile snapshots a config that
        // isn't necessarily live), so fall back to a generic label rather than
        // an empty subtitle.
        typeLabel:
            system?.device(member.uuid)?.typeLabel ?? 'Standalone speaker',
        reachable: true,
      );
}

// -----------------------------------------------------------------------------
// Cards — dumb renderers over the models above, shared by the system overview
// (live) and the profile detail list (snapshot). [onTap] and [footer] are
// interaction/decoration the caller supplies (the overview routes to the live
// detail; the profile routes to the entity detail + passes a "settings saved"
// footer).
// -----------------------------------------------------------------------------

/// A home theater: soundbar avatar + model + Fronts/Surrounds/Sub chips.
class TheaterEntityCard extends StatelessWidget {
  final TheaterCardModel model;
  final VoidCallback? onTap;
  final Widget? footer;
  const TheaterEntityCard(
      {super.key, required this.model, this.onTap, this.footer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.surround_sound,
                      color: scheme.onPrimaryContainer),
                ),
                Gap.m,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        model.soundbarLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      Gap.s,
                      _GroupChips(
                        hasFronts: model.hasFronts,
                        hasSurrounds: model.hasSurrounds,
                        hasSub: model.hasSub,
                      ),
                      if (footer != null) ...[Gap.s, footer!],
                    ],
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bonded speaker group (stereo pair / zone / custom): kind + members + Sub.
class GroupEntityCard extends StatelessWidget {
  final GroupCardModel model;
  final VoidCallback? onTap;
  final Widget? footer;
  const GroupEntityCard(
      {super.key, required this.model, this.onTap, this.footer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        titleAlignment: ListTileTitleAlignment.center,
        onTap: onTap,
        leading: Icon(model.icon),
        title: Text(model.title),
        subtitle: _subtitle(Text(model.subtitle), footer),
        isThreeLine: footer != null,
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// A single standalone speaker room. Unreachable speakers are flagged and made
/// non-tappable regardless of the passed [onTap].
class SingleEntityCard extends StatelessWidget {
  final SingleCardModel model;
  final VoidCallback? onTap;
  final Widget? footer;
  const SingleEntityCard(
      {super.key, required this.model, this.onTap, this.footer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unreachable = !model.reachable;
    final tap = unreachable ? null : onTap;
    final text = unreachable ? unreachableSpeakerHint : model.typeLabel;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        titleAlignment: ListTileTitleAlignment.center,
        onTap: tap,
        leading: Icon(
          unreachable ? Icons.warning_amber_rounded : Icons.speaker_outlined,
          color: unreachable ? scheme.error : null,
        ),
        title: Text(model.title),
        subtitle: _subtitle(
          Text(text, style: unreachable ? TextStyle(color: scheme.error) : null),
          footer,
        ),
        isThreeLine: footer != null,
        trailing: tap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// A ListTile subtitle that stacks the standard text over an optional [footer].
Widget _subtitle(Widget text, Widget? footer) => footer == null
    ? text
    : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [text, const SizedBox(height: 6), footer],
      );

/// Chips on a home-theater card marking which extra-speaker groups are bonded.
class _GroupChips extends StatelessWidget {
  final bool hasFronts;
  final bool hasSurrounds;
  final bool hasSub;
  const _GroupChips(
      {required this.hasFronts,
      required this.hasSurrounds,
      required this.hasSub});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[
      if (hasFronts)
        PillChip(icon: Icons.speaker, text: 'Fronts', color: scheme.primary),
      if (hasSurrounds)
        PillChip(
            icon: Icons.surround_sound,
            text: 'Surrounds',
            color: scheme.primary),
      if (hasSub)
        PillChip(
            icon: Icons.graphic_eq, text: 'Subwoofer', color: scheme.primary),
    ];
    if (chips.isEmpty) {
      chips.add(PillChip(
        icon: Icons.info_outline,
        text: 'No extra speakers',
        color: scheme.onSurfaceVariant,
      ));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}
