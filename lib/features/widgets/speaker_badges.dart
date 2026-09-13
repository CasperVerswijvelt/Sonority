import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/room_calibration.dart';
import 'pill_chip.dart';

/// The tags a speaker carries in a bonding picker: the bond it must be taken
/// from, and whether it holds a Trueplay tuning.
///
/// Shared by the home-theater and group flows so a candidate reads the same in
/// both. Built with [PillChip] — the app's one tag form — so a picker tags a
/// speaker exactly the way an entity card tags a role.
///
/// The Trueplay pill appears ONLY when the speaker actually holds a tuning:
/// "not tuned" on every free speaker would be noise, and the thing worth
/// surfacing is a calibration that a bonding change could cost. It reports
/// `available`/`enabled` and nothing more — a stored tuning is not evidence the
/// correction still fits (see `tuningLostByTaking`).
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
  return [
    if (source != null)
      PillChip(
        icon: Icons.link,
        text: switch (_roleIn(source, uuid)) {
          final role? =>
            '${l10n.speakerBadgeFromBond(source.zoneName)} \u00b7 $role',
          _ => l10n.speakerBadgeFromBond(source.zoneName),
        },
        color: scheme.onSurfaceVariant,
      ),
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
/// `L+R`, so printing it would add noise without telling two of them apart (use
/// the Identify button for that).
///
/// This matters because a bonded speaker has NO name of its own — Sonos absorbs
/// it into the bond's — so two satellites of one home theater would otherwise
/// render as two identical cards.
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
/// or null when nothing is taken (or nothing tuned is at stake).
///
/// Every case is hardware-measured — see [SonosSystem.tuningLostByTaking]. Only
/// speakers that actually hold a tuning are named: warning about calibration on
/// a speaker that has none would be false.
String? stealWarning(
  BuildContext context, {
  required SonosSystem system,
  required Set<String> selected,
  required Map<String, RoomCalibration> calibration,
  String? exceptPrimary,
}) {
  // Group the picks by the bond each must come out of.
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
