import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/room_calibration.dart';
import 'card_grid.dart';
import 'entity_cards.dart' show groupKindL10n;
import 'entity_icons.dart';
import 'info_note.dart';
import 'pill_chip.dart';
import 'section_header.dart';

/// One block of a speaker picker: a heading plus the speakers under it.
///
/// [source] IS the discriminator — null means "free to use", set means "bonded
/// into that entity, and choosing one takes it from there" at a cost given by
/// [SonosSystem.tuningLostByTaking]. A separate kind enum would let
/// `{bond, source: null}` exist, which rendered as a headerless block.
@immutable
class PickerSection {
  final ZoneGroupMember? source;
  final List<SonosDevice> devices;

  const PickerSection({required this.devices, this.source});

  bool get isAvailable => source == null;
}

/// Split [candidates] into ordered picker blocks: everything free to use —
/// which includes the entity's OWN current members ([exceptPrimary]), since
/// those cost nothing to keep — then one block per bond a speaker would have to
/// be taken from.
///
/// Grouping by source is what lets the picker state provenance ONCE in a header
/// instead of repeating it on every card — and it is why a card inside a bond
/// block can title itself by speaker type: a bonded speaker has no name of its
/// own (Sonos absorbs it into the bond's), so three members of one zone would
/// otherwise render as three identically-titled cards.
///
/// Pure and order-stable: within a block, [candidates] order is preserved, and
/// bond blocks appear in the order their first member does.
List<PickerSection> pickerSections({
  required SonosSystem system,
  required List<SonosDevice> candidates,
  String? exceptPrimary,
}) {
  final free = <SonosDevice>[];
  final byOwner = <String, List<SonosDevice>>{};
  for (final d in candidates) {
    final owner = system.ownerOf(d.uuid);
    if (owner == null || owner == exceptPrimary) {
      free.add(d);
    } else {
      byOwner.putIfAbsent(owner, () => []).add(d);
    }
  }
  return [
    if (free.isNotEmpty) PickerSection(devices: free),
    for (final e in byOwner.entries)
      if (system.memberByUuid(e.key) case final src?)
        PickerSection(source: src, devices: e.value),
  ];
}

/// The heading for [section], or null when the picker has nothing to
/// disambiguate — a single block needs no chrome, so a system with no other
/// bonds looks exactly as it did before speakers could be taken from one.
///
Widget? pickerSectionHeader(
  BuildContext context, {
  required SonosSystem system,
  required PickerSection section,
  required int sectionCount,
  required Map<String, RoomCalibration> calibration,
  required bool absorbing,
}) {
  // Only the plain "Available" block is chrome-free when it stands alone; a
  // lone BOND block still has to say whose speakers these are and what taking
  // one costs (a fully-bonded system has no free speakers at all).
  final l10n = context.l10n;
  final src = section.source;
  if (src == null) {
    return sectionCount < 2
        ? null
        : SectionHeader(l10n.pickerSectionAvailable,
            icon: Icons.speaker_outlined);
  }
  return SectionHeader(
    '${src.zoneName} · ${_kindLabel(l10n, src)}',
    icon: src.isHomeTheater
        ? Icons.surround_sound
        : groupKindIcon(src.groupKind),
    helper: _cost(context, system, src, calibration, absorbing),
  );
}

String _kindLabel(AppLocalizations l10n, ZoneGroupMember m) =>
    m.isHomeTheater ? l10n.entityKindHomeTheater : groupKindL10n(l10n, m.groupKind);

/// What taking a speaker out of [src] costs, or null when nothing in that bond
/// holds a tuning — warning about calibration that does not exist would be
/// false. Wording tracks [SonosSystem.tuningLostByTaking] exactly, including
/// which rows are measured and which are inferred.
String _cost(
  BuildContext context,
  SonosSystem system,
  ZoneGroupMember src,
  Map<String, RoomCalibration> calibration,
  bool absorbing,
) {
  final l10n = context.l10n;
  final members = system.bondMemberUuids(src);
  // Always state the consequence of picking — it is true whether or not any
  // calibration is at stake, and it is why these speakers are listed apart.
  final base = l10n.pickerSectionLeavesBond;
  if (!members.any((u) => calibration[u]?.available ?? false)) return base;
  // Anything that cannot be absorbed has to be freed first, and then the whole
  // source bond pays. That is every source in a group flow (AddBondedZones
  // absorbs from nothing) AND a home-theater source in either flow (absorbing
  // out of another HT is unmeasured, so it is not assumed) — which is why both
  // flows say the same thing about a home-theater source.
  if (!absorbing || !system.canAbsorbFrom(src)) {
    return '$base ${l10n.pickerCostFreedFirst(members.length)}';
  }
  if (src.isStereoPair) return '$base ${l10n.pickerCostPair}';
  return '$base ${l10n.pickerCostZone}';
}

/// The card title for [uuid] in a bond block: the speaker TYPE, plus the
/// channel it currently holds when the bond gives it a distinguishing one —
/// `One · LR`.
///
/// One string in one style on purpose. A bonded speaker has no name of its own
/// (Sonos absorbs it into the bond's), so the channel is not decoration — it is
/// the part that tells two same-model cards apart, and styling it more faintly
/// than the type would work against the only job it has.
String bondedCardTitle(
  AppLocalizations l10n,
  SonosSystem system, {
  required SonosDevice device,
  String? exceptPrimary,
}) {
  final owner = system.ownerOf(device.uuid);
  final source = owner == null || owner == exceptPrimary
      ? null
      : system.memberByUuid(owner);
  final role = source == null ? null : _roleIn(l10n, source, device.uuid);
  return role == null ? device.typeLabel : '${device.typeLabel} · $role';
}

/// Whether Trueplay is ACTIVE on this speaker (stored *and* enabled), as a tag
/// for its card. "Trueplay off" on a dormant tuning and "not tuned" on every
/// free speaker are both noise — the useful signal is "calibrated right now".
/// Says nothing about whether the stored correction still fits.
Widget? trueplayBadge(BuildContext context, RoomCalibration? calibration) =>
    (calibration?.active ?? false)
        ? PillChip(
            icon: Icons.graphic_eq,
            text: context.l10n.speakerBadgeTrueplay,
            color: Theme.of(context).colorScheme.secondary,
          )
        : null;

/// The channel [uuid] currently holds inside [source], as a short human label —
/// `Front L`, `Surround R`, `Sub`, or `L`/`R` in a stereo pair. Null when the
/// bond gives it no distinguishing role (every member of a full-range zone is
/// `L+R`, so it separates nobody — Identify does that).
///
/// Deliberately NOT shared with `_roleLabel` in `profile_entity_detail_screen`:
/// that one collapses both fronts into one "Front" because a profile summary
/// does not need to tell them apart, and here telling them apart is the entire
/// job. Same words, different granularity.
String? _roleIn(AppLocalizations l10n, ZoneGroupMember source, String uuid) {
  if (source.isGroup) {
    final c = source.groupChannels[uuid];
    return c == null || c == GroupChannel.both ? null : groupChannelShort(c);
  }
  final channels = source.channelAssignments.entries
      .where((e) => e.value == uuid)
      .map((e) => e.key)
      .toSet();
  final parts = [
    if (channels.contains(SonosChannel.center)) l10n.pickerRoleCentre,
    if (channels.contains(SonosChannel.leftFront)) l10n.pickerRoleFrontL,
    if (channels.contains(SonosChannel.rightFront)) l10n.pickerRoleFrontR,
    if (channels.contains(SonosChannel.leftRear)) l10n.pickerRoleSurroundL,
    if (channels.contains(SonosChannel.rightRear)) l10n.pickerRoleSurroundR,
    if (channels.contains(SonosChannel.sub)) 'Sub', // Sonos' own channel token
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The calibration cost of a selection that takes speakers out of other bonds,
/// or null when nothing tuned is at stake.
///
/// This stays selection-dependent on purpose, so it cannot move into a section
/// header: taking BOTH halves of a stereo pair costs nothing, taking one costs
/// the other (EXP-23 Q7/Q9). Only speakers that actually hold a tuning are
/// named.
String? stealWarning(
  BuildContext context, {
  required SonosSystem system,
  required Set<String> selected,
  required Map<String, RoomCalibration> calibration,
  required bool absorbing,
  String? exceptPrimary,
}) {
  final byOwner = <String, Set<String>>{};
  for (final uuid in selected) {
    final owner = system.ownerOf(uuid);
    if (owner == null || owner == exceptPrimary) continue;
    byOwner.putIfAbsent(owner, () => {}).add(uuid);
  }
  final losing = <String>{};
  for (final entry in byOwner.entries) {
    final source = system.memberByUuid(entry.key);
    if (source == null) continue;
    losing.addAll(system.tuningLostByTaking(source, entry.value,
        destinationAbsorbs: absorbing));
  }
  // Name them the way the cards do. A bonded speaker's room name is the BOND's
  // name, so several losers would otherwise render as the same word — here the
  // two members of one zone were both just "Eetkamer".
  final tuned = losing
      .where((u) => calibration[u]?.available ?? false)
      .map((u) {
        final d = system.device(u);
        if (d == null) return u;
        final owner = system.ownerOf(u);
        final src = owner == null ? null : system.memberByUuid(owner);
        return src == null
            ? d.roomName
            : '${src.zoneName} · ${bondedCardTitle(context.l10n, system, device: d)}';
      })
      .toSet()
      .toList()
    ..sort();
  if (tuned.isEmpty) return null;
  return context.l10n.speakerStealTrueplayWarning(tuned.join(', '), tuned.length);
}


/// Everything a bond-aware picker needs, gathered once per build so the
/// home-theater and group flows configure it instead of each re-deriving it.
///
/// The two flows differ in exactly two values — which entity is being
/// configured, and whether its bonding call can absorb a speaker out of another
/// bond — so those are the only fields that vary.
@immutable
class PickerContext {
  final SonosSystem system;
  final Map<String, RoomCalibration> calibration;

  /// True for a home-theater target (`AddHTSatellite` absorbs a live pair or
  /// zone); false for a group target (`AddBondedZones` absorbs nothing).
  final bool absorbing;

  /// The entity being configured — its own members are "available", not stolen.
  final String? exceptPrimary;

  const PickerContext({
    required this.system,
    required this.calibration,
    required this.absorbing,
    this.exceptPrimary,
  });

  List<PickerSection> sections(List<SonosDevice> candidates) => pickerSections(
        system: system,
        candidates: candidates,
        exceptPrimary: exceptPrimary,
      );

  /// Whether this speaker is shown under a bond heading (and so titles by type).
  bool isBonded(String uuid) {
    final owner = system.ownerOf(uuid);
    return owner != null && owner != exceptPrimary;
  }

  /// The card title: room name normally, `Type · Channel` under a bond heading.
  String? titleOverride(BuildContext context, SonosDevice d) => isBonded(d.uuid)
      ? bondedCardTitle(context.l10n, system,
          device: d, exceptPrimary: exceptPrimary)
      : null;

  Widget? header(BuildContext context, PickerSection s, int count) =>
      pickerSectionHeader(context,
          system: system,
          section: s,
          sectionCount: count,
          calibration: calibration,
          absorbing: absorbing);

  String? warning(BuildContext context, Set<String> selected) => stealWarning(
        context,
        system: system,
        selected: selected,
        calibration: calibration,
        absorbing: absorbing,
        exceptPrimary: exceptPrimary,
      );
}

/// The candidate list as bond-grouped blocks, with the selection's calibration
/// cost underneath. Shared so the two flows lay out identically; each supplies
/// only its own [card] (they differ in channel selectors and caps).
class SpeakerPickerSections extends StatelessWidget {
  final PickerContext ctx;
  final List<SonosDevice> candidates;
  final Widget Function(SonosDevice device) card;
  final String? warning;

  const SpeakerPickerSections({
    super.key,
    required this.ctx,
    required this.candidates,
    required this.card,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final sections = ctx.sections(candidates);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sections) ...[
          if (ctx.header(context, s, sections.length) case final h?) h,
          CardGrid([for (final d in s.devices) card(d)]),
          if (s != sections.last) Gap.m,
        ],
        if (warning case final w?) ...[Gap.m, InfoNote(w)],
      ],
    );
  }
}
