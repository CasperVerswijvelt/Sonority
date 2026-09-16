import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/front_layout.dart';
import '../../data/sonos/room_calibration.dart';
import 'card_grid.dart';
import 'entity_cards.dart' show groupKindL10n;
import 'entity_icons.dart';
import 'info_note.dart';
import 'pill_chip.dart';
import 'section_header.dart';

/// Whether a home-theater apply writes a bond at all — the ONE rule behind
/// [PickerContext.writes] for the fronts/surrounds flow.
///
/// Named and shared because both cost tests used to hand-write it, so the
/// regression it guards stayed green: gating on `diff.toRemove.isNotEmpty`
/// priced a purely ADDITIVE apply at zero, while Q20 measured exactly that
/// operation (added one satellite, removed none) taking the bar and both rears
/// to `available=0`. Every write costs the bond its tuning; only a genuine
/// no-op costs nothing.
bool htApplyWrites(HtDiff diff) => !diff.isNoOp;

/// Whether a speaker-group apply writes a bond at all — the same rule for the
/// group flow, and the gate that also enables Apply.
///
/// A CREATE always writes, and costs the speakers it bonds together (two
/// freshly tuned standalone speakers paired lose both tunings; that used to be
/// priced at zero). An EDIT writes only when the bond itself differs, compared
/// exactly as `editGroup` verifies it — order-insensitively except for the
/// coordinator, so re-picking a zone's members in another order is a no-op
/// rather than a warned-about write that never happens. A rename-only edit
/// writes no bond and costs no tuning.
bool groupApplyWrites({
  required ZoneGroupMember? existing,
  required Map<String, GroupChannel> channels,
  String? subUuid,
  String? coordUuid,
}) =>
    existing == null ||
    !existing.matchesGroupLayout(channels,
        subUuid: subUuid, coordUuid: coordUuid);

/// One block of a speaker picker: a heading plus the speakers under it.
///
/// [source] IS the discriminator — null means "free to use", set means "bonded
/// into that entity, and choosing one takes it from there" at a cost given by
/// [SonosSystem.tuningLostBySelection]. A separate kind enum would let
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
Widget? _sectionHeader(
  BuildContext context, {
  required SonosSystem system,
  required PickerSection section,
  required int sectionCount,
  required Map<String, RoomCalibration> calibration,
  Set<String> busy = const {},
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
    helper: sectionCost(l10n, system, src, calibration, busy: busy),
  );
}

String _kindLabel(AppLocalizations l10n, ZoneGroupMember m) =>
    m.isHomeTheater ? l10n.entityKindHomeTheater : groupKindL10n(l10n, m.groupKind);

/// What taking a speaker out of [src] costs, as the section header's helper
/// line.
///
/// **Every source costs the same in Trueplay.** A stored tuning does survive an
/// absorb (which is why an HT target still skips the free — see
/// [SonosSystem.canAbsorbFrom]), but EXP-23 Q15/Q16 measured that it comes back
/// switched off and that switching it on destroys it — no safe delay, and the
/// role-preserving case died too. So there is no retention to promise a user,
/// and the header no longer pretends otherwise. Only a multi-speaker group adds
/// a fact the screen cannot show: taking one member dissolves the whole group.
/// A stereo pair is NOT exempt. It reads as self-evident only next to a heading
/// that names it; the review card carries no heading, and it is the last gate
/// before Apply. A pair is a "speaker group" in our own UI (Office · Stereo
/// pair), so the group sentence covers it without a second string.
@visibleForTesting
String sectionCost(
  AppLocalizations l10n,
  SonosSystem system,
  ZoneGroupMember src,
  Map<String, RoomCalibration> calibration, {
  Set<String> busy = const {},
}) {
  final members = system.bondMemberUuids(src);
  // Always state the consequence of picking — it is true whether or not any
  // calibration is at stake, and it is why these speakers are listed apart.
  final base = l10n.pickerSectionLeavesBond;
  // `isZone` was too narrow: a shipped CUSTOM L/R/Both group of 3+ speakers
  // dissolves identically and said nothing at all. Pairs included — see above.
  final dissolves = src.isGroup ? ' ${l10n.pickerCostZone}' : '';
  // UNKNOWN is not "no tuning". A speaker whose Trueplay read failed has no
  // entry at all, and staying quiet about the cost in that case errs in the one
  // direction that can destroy something. Only a bond we have read in full, and
  // read as untuned, gets the short line.
  // A read IN FLIGHT is a third state, and it is not the one to err loudly on:
  // the reads are kicked off when the flow opens, so treating "not answered
  // yet" as "unknown, warn" made "Expect to re-tune all of them." the DEFAULT
  // first impression of every bond block for as long as the reads took — then
  // silently retract. On Android, where Trueplay can't be measured at all and
  // nothing is ever tuned, that is the only thing a user would ever see.
  // Withholding the claim costs nothing: the sentences above are true either
  // way, and a genuinely failed read still lands on the loud branch.
  if (members.any(busy.contains)) return '$base$dissolves';
  final known = members.every((u) => calibration.containsKey(u));
  if (known && !members.any((u) => calibration[u]!.available)) {
    return '$base$dissolves';
  }
  return '$base$dissolves ${l10n.pickerCostCleared}';
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
}) {
  final owner = system.ownerOf(device.uuid);
  final source = owner == null ? null : system.memberByUuid(owner);
  final role = source == null ? null : _roleIn(l10n, source, device.uuid);
  // A Sub's type and its channel are the same word, and "Sub · Sub" is just
  // noise. Seen on hardware in the review card.
  if (role == null || role == device.typeLabel) return device.typeLabel;
  return '${device.typeLabel} · $role';
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
    if (channels.contains(SonosChannel.center)) l10n.pickerRoleCenter,
    if (channels.contains(SonosChannel.leftFront)) l10n.pickerRoleFrontL,
    if (channels.contains(SonosChannel.rightFront)) l10n.pickerRoleFrontR,
    if (channels.contains(SonosChannel.leftRear)) l10n.pickerRoleSurroundL,
    if (channels.contains(SonosChannel.rightRear)) l10n.pickerRoleSurroundR,
    // 'Sub' stays untranslated — Sonos' own product/channel token, like the
    // L/R group-channel shorts (same call as profile_entity_detail_screen).
    if (channels.contains(SonosChannel.sub)) 'Sub',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The speakers among [uuids] whose tuning is at risk — one that holds a stored
/// tuning, or one we could not read: their deduped display names, and how many
/// SPEAKERS that is.
///
/// The two numbers differ, and that is the point — a bonded speaker's room name
/// is the BOND's name, so members are named the way the cards are
/// ([bondedCardTitle]), and two identical models in one bond still collapse to
/// one label. Pluralise on [count], never on `names.length`.
///
/// [ownBond] is the entity being configured: its members drop the bond-name
/// prefix, since repeating the name of the thing on screen is noise.
///
/// A speaker with NO entry holds an unknown tuning, not a missing one — a read
/// that failed leaves nothing behind, and a speaker inside the ~20-30s
/// post-unbond window fails every time. It counts as at risk, the same
/// direction [sectionCost] already errs in: the two are rendered one above the
/// other, and the heading saying the tuning is cleared while the note names
/// nobody is the disagreement this list exists to prevent.
({List<String> names, int count}) tunedSpeakers(
  AppLocalizations l10n,
  SonosSystem system,
  Iterable<String> uuids,
  Map<String, RoomCalibration> calibration, {
  String? ownBond,
  Set<String> busy = const {},
}) {
  final tuned = uuids
      // Still being read — see [sectionCost]. Naming a speaker as at risk
      // before anyone has asked it anything is the same false alarm, and this
      // note sits directly under the headings that one governs.
      .where((u) => !busy.contains(u))
      // A line-out box (Amp / Port / Connect) has no drivers of its own, so
      // Sonos never tunes it — naming one gives advice that cannot be followed.
      // Same getter that keeps them out of the Trueplay lists everywhere else.
      .where((u) => !(system.device(u)?.drivesExternalSpeakers ?? false))
      .where((u) => calibration[u]?.available ?? true)
      .toList();
  final names = tuned
      .map((u) {
        final d = system.device(u);
        // Never a raw RINCON uuid in user-facing copy. Unresolvable is nearly
        // impossible now (discovery recovers every topology member), but a
        // generic word still reads as a speaker, and dropping the entry would
        // shorten an at-risk list this function exists to keep honest.
        if (d == null) return l10n.widgetsSpeaker;
        final owner = system.ownerOf(u);
        final src = owner == null ? null : system.memberByUuid(owner);
        // A soundbar has no owner of its own, so name the configured entity's
        // primary by type like the rest of its members.
        if (src == null) return u == ownBond ? d.typeLabel : d.roomName;
        final title = bondedCardTitle(l10n, system, device: d);
        return src.uuid == ownBond ? title : '${src.zoneName} · $title';
      })
      .toSet()
      .toList()
    ..sort();
  return (names: names, count: tuned.length);
}

/// Everything a bond-aware picker needs, gathered once per build so the
/// home-theater and group flows configure it instead of each re-deriving it.
///
/// The two flows differ only in which entity is being configured (and, for a
/// group edit, that its own members are part of the cost).
@immutable
class PickerContext {
  final SonosSystem system;
  final Map<String, RoomCalibration> calibration;

  /// The entity being configured — its own members are "available", not stolen.
  final String? exceptPrimary;

  /// Whether the apply about to run writes a bond at all.
  ///
  /// True for a group create (a create is a write), for a group edit whose bond
  /// differs, and for a home theater whose engine diff is not a no-op. False
  /// only for an apply that writes nothing, which therefore costs nothing —
  /// also what keeps a flow from warning the moment it opens.
  final bool writes;

  /// Speakers whose calibration read is in flight. A cost claim about one of
  /// these is a claim nobody has asked yet — see [sectionCost].
  final Set<String> busy;

  const PickerContext({
    required this.system,
    required this.calibration,
    this.exceptPrimary,
    this.writes = false,
    this.busy = const {},
  });

  /// What the DESTINATION costs, which no source bond can know about: the
  /// configured entity's own current members, plus everything [selected] —
  /// the speakers joining the new bond.
  ///
  /// Every member, not only a dropped one: a purely additive `AddHTSatellite`
  /// was measured dropping the bar and both rears to `available=0` with nothing
  /// removed (CLAUDE.md, Q20), `AddBondedZones` rebuilds the bond even on an
  /// unchanged map (Q8a), and which satellites survive is not predictable. The
  /// selection is in there because a bonding change costs the bond it creates,
  /// not just the ones it empties — two freshly tuned standalone speakers
  /// paired together lose both tunings, and that used to be priced at zero.
  Set<String> _destinationCost(Set<String> selected) {
    if (!writes) return const {};
    final live =
        exceptPrimary == null ? null : system.memberByUuid(exceptPrimary!);
    return {
      ...selected,
      if (live != null) ...system.bondMemberUuids(live),
    };
  }

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
  String? titleOverride(BuildContext context, SonosDevice d) =>
      isBonded(d.uuid) ? bondedCardTitle(context.l10n, system, device: d) : null;

  Widget? header(BuildContext context, PickerSection s, int count) =>
      _sectionHeader(context,
          system: system,
          section: s,
          sectionCount: count,
          calibration: calibration,
          busy: busy);

  /// The speakers [selected] costs their Trueplay tuning, named for display.
  ///
  /// THE one cost computation behind every screen in a flow — the picker note
  /// and the home-theater review card render it with different sentences but
  /// must never disagree about who is on the list, which they did until this
  /// was a single method.
  ///
  /// Takes the [AppLocalizations] rather than a `BuildContext`: this is pure
  /// text, so it stays callable (and testable) without an element tree.
  ({List<String> names, int count}) tuningCost(
      AppLocalizations l10n, Set<String> selected) {
    final losing = system.tuningLostBySelection(
      selected: selected,
      exceptPrimary: exceptPrimary,
      alsoLosing: _destinationCost(selected),
    );
    return tunedSpeakers(l10n, system, losing, calibration,
        ownBond: exceptPrimary, busy: busy);
  }

  /// The source groups this selection DISSOLVES, as a sentence, or null.
  ///
  /// A group does not shrink when a member is taken — absorbing one dissolves
  /// the whole bond (EXP-23 Q12), and a stereo pair is a group here (it is
  /// listed as one in the UI), so both break up.
  ///
  /// A home theater is the third case and behaves differently: it SURVIVES
  /// minus the speakers taken. It still has to be named. Its own members all
  /// lose their tuning (Q20) and the card otherwise says nothing at all about
  /// modifying a second entity — the user picked from a heading two screens
  /// back and the review card has no heading to carry it.
  ///
  /// The section header states this per block, but the review step is the last
  /// screen before Apply and the only gate there is — the removal confirm
  /// dialog was deleted in favour of it — and an UNTUNED group priced nothing,
  /// so the card said nothing destructive about a dissolve it was about to
  /// cause. Trueplay can't even be measured from Android, so an untuned group
  /// is the common case, not the corner one.
  String? dissolveNote(AppLocalizations l10n, Set<String> selected) {
    final broken = <String>{};
    final shrunk = <String>{};
    for (final u in selected) {
      final owner = system.ownerOf(u);
      if (owner == null || owner == exceptPrimary) continue;
      final src = system.memberByUuid(owner);
      if (src == null) continue;
      (src.isGroup ? broken : shrunk).add(src.zoneName);
    }
    final sentences = <String>[
      if (broken.isNotEmpty)
        l10n.pickerCostDissolves(
            (broken.toList()..sort()).join(', '), broken.length),
      if (shrunk.isNotEmpty)
        l10n.pickerCostLeavesHt(
            (shrunk.toList()..sort()).join(', '), shrunk.length),
    ];
    return sentences.isEmpty ? null : sentences.join(' ');
  }

  /// [tuningCost] as the one-sentence note under a picker list, or null when
  /// nothing tuned is at stake.
  String? warning(AppLocalizations l10n, Set<String> selected) {
    final tuned = tuningCost(l10n, selected);
    if (tuned.names.isEmpty) return null;
    // Plural on the SPEAKER count, not the name count — two identical models in
    // one bond share a label, and "its … re-tune it" would then be wrong.
    return l10n.speakerStealTrueplayWarning(tuned.names.join(', '), tuned.count);
  }
}

/// The candidate list as bond-grouped blocks, with the selection's calibration
/// cost underneath. Shared so the two flows lay out identically; each supplies
/// only its own [card] (they differ in channel selectors and caps).
class SpeakerPickerSections extends StatelessWidget {
  final PickerContext ctx;
  final List<SonosDevice> candidates;
  final Widget Function(SonosDevice device) card;

  /// The current selection — the calibration cost is the union over every bond
  /// it takes from, so it cannot be precomputed per section.
  final Set<String> selected;

  const SpeakerPickerSections({
    super.key,
    required this.ctx,
    required this.candidates,
    required this.card,
    required this.selected,
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
        if (ctx.warning(context.l10n, selected) case final w?) ...[
          Gap.m,
          InfoNote(w),
        ],
      ],
    );
  }
}
