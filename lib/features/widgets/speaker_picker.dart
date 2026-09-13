import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/room_calibration.dart';
import 'entity_cards.dart' show groupKindL10n;
import 'entity_icons.dart';
import 'pill_chip.dart';
import 'section_header.dart';

/// Which block of the picker a speaker belongs to.
enum PickerSectionKind {
  /// Free to bond — nothing else claims it.
  available,

  /// Bonded into some OTHER pair / home theater / group; choosing it takes it
  /// from there, at a cost given by [SonosSystem.tuningLostByTaking].
  bond,
}

/// One block of a speaker picker: a heading plus the speakers under it.
@immutable
class PickerSection {
  final PickerSectionKind kind;

  /// The bond these speakers must be taken from. Only set for [kind] `bond`.
  final ZoneGroupMember? source;
  final List<SonosDevice> devices;

  const PickerSection({
    required this.kind,
    required this.devices,
    this.source,
  });
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
    if (free.isNotEmpty)
      PickerSection(kind: PickerSectionKind.available, devices: free),
    for (final e in byOwner.entries)
      PickerSection(
        kind: PickerSectionKind.bond,
        source: system.memberByUuid(e.key),
        devices: e.value,
      ),
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
}) {
  if (sectionCount < 2) return null;
  final l10n = context.l10n;
  return switch (section.kind) {
    PickerSectionKind.available =>
      SectionHeader(l10n.pickerSectionAvailable, icon: Icons.speaker_outlined),
    PickerSectionKind.bond => switch (section.source) {
        final src? => SectionHeader(
            '${src.zoneName} · ${_kindLabel(l10n, src)}',
            icon: src.isHomeTheater
                ? Icons.surround_sound
                : groupKindIcon(src.groupKind),
            helper: _cost(context, system, src, calibration),
          ),
        _ => null,
      },
  };
}

String _kindLabel(AppLocalizations l10n, ZoneGroupMember m) =>
    m.isHomeTheater ? l10n.entityKindHomeTheater : groupKindL10n(l10n, m.groupKind);

/// What taking a speaker out of [src] costs, or null when nothing in that bond
/// holds a tuning — warning about calibration that does not exist would be
/// false. Wording follows the measured rule (EXP-23): a stereo pair costs only
/// the speakers left behind; a home theater or group costs every member.
String? _cost(
  BuildContext context,
  SonosSystem system,
  ZoneGroupMember src,
  Map<String, RoomCalibration> calibration,
) {
  final members = system.bondMemberUuids(src);
  if (!members.any((u) => calibration[u]?.available ?? false)) return null;
  return src.isStereoPair
      ? context.l10n.pickerCostPair
      : context.l10n.pickerCostWholeBond(members.length);
}

/// The tags a speaker carries on its card: the channel it currently holds, and
/// whether it holds a Trueplay tuning. Provenance is NOT here — that is the
/// section header's job (see [pickerSections]).
///
/// The channel pill exists because a bonded speaker has no name of its own, so
/// `L`/`R`/`LR` is what tells two members of one bond apart. Null for a
/// full-range zone member (every one is `L+R`, so it disambiguates nothing —
/// the Identify button does that).
///
/// The Trueplay pill appears only when the speaker actually holds a tuning:
/// "not tuned" on every free speaker would be noise. It reports
/// `available`/`enabled` and nothing more — a stored tuning is not evidence the
/// correction still fits.
List<Widget> speakerBadges(
  BuildContext context, {
  required SonosSystem system,
  required String uuid,
  RoomCalibration? calibration,
  String? exceptPrimary,
}) {
  final scheme = Theme.of(context).colorScheme;
  final l10n = context.l10n;
  final owner = system.ownerOf(uuid);
  final source = owner == null || owner == exceptPrimary
      ? null
      : system.memberByUuid(owner);
  final role = source == null ? null : _roleIn(source, uuid);
  return [
    if (role != null)
      PillChip(text: role, color: scheme.onSurfaceVariant),
    if (calibration?.available ?? false)
      PillChip(
        icon: Icons.graphic_eq,
        text: calibration!.enabled
            ? l10n.speakerBadgeTrueplayOn
            : l10n.speakerBadgeTrueplayOff,
        color: calibration.enabled ? scheme.secondary : scheme.onSurfaceVariant,
      ),
  ];
}

/// The channel [uuid] currently holds inside [source], short form — `L`/`R` for
/// a stereo pair, `LR`/`RR`/`SW` for a home-theater satellite. Null when the
/// bond gives it no distinguishing role: every member of a full-range zone is
/// `L+R`.
String? _roleIn(ZoneGroupMember source, String uuid) {
  if (source.isGroup) {
    final c = source.groupChannels[uuid];
    return c == null || c == GroupChannel.both ? null : groupChannelShort(c);
  }
  for (final e in source.channelAssignments.entries) {
    if (e.value == uuid) return e.key.token;
  }
  return null;
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
    losing.addAll(system.tuningLostByTaking(source, entry.value));
  }
  final tuned = losing
      .where((u) => calibration[u]?.available ?? false)
      .map((u) => system.device(u)?.roomName ?? u)
      .toSet()
      .toList()
    ..sort();
  if (tuned.isEmpty) return null;
  return context.l10n.speakerStealTrueplayWarning(tuned.join(', '), tuned.length);
}
