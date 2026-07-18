import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import 'member_channel_card.dart';
import 'speaker_diagram.dart';

/// Speaker TYPE for a bonded channel (e.g. "Play:1", "Sub (Gen 1/2)"), or null
/// when no speaker is assigned — the room name just echoes the HT name, so the
/// type is the useful label on the diagram.
///
/// [names] (UUID → captured room name) is an optional fallback for when the
/// diagram is driven from a stored profile snapshot and the device isn't
/// currently present — live callers pass none.
String? typeForChannel(
    SonosSystem? system, ZoneGroupMember member, SonosChannel channel,
    {Map<String, String>? names}) {
  final uuid = member.channelAssignments[channel];
  if (uuid == null) return null;
  return system?.device(uuid)?.typeLabel ?? names?[uuid] ?? appL10n().widgetsSpeaker;
}

/// Whether a speaker is currently bonded to [channel].
bool hasChannel(ZoneGroupMember member, SonosChannel channel) =>
    member.channelAssignments.containsKey(channel);

/// A [SpeakerDiagram] for an HT [member], labelling each channel by speaker
/// type. Shared by the HT detail screen and the profile entity detail (fed a
/// snapshot member) so the "render a member as a diagram" wiring lives once.
/// (The front-surrounds flow builds its diagram from a pending *selection*, not
/// a member, so it stays bespoke.) [names] is the snapshot name fallback.
SpeakerDiagram htDiagramForMember(SonosSystem? system, ZoneGroupMember member,
        {Map<String, String>? names}) =>
    SpeakerDiagram(
      soundbarLabel:
          system?.device(member.uuid)?.typeLabel ?? names?[member.uuid],
      frontLeftLabel:
          typeForChannel(system, member, SonosChannel.leftFront, names: names),
      frontRightLabel:
          typeForChannel(system, member, SonosChannel.rightFront, names: names),
      rearLeftLabel:
          typeForChannel(system, member, SonosChannel.leftRear, names: names),
      rearRightLabel:
          typeForChannel(system, member, SonosChannel.rightRear, names: names),
      subCount: member.subUuids.length,
    );

/// The per-member channel cards for a bonded speaker group (stereo pair / zone /
/// custom): one card per member (type + L/R/Both), then the sub if present, each
/// followed by a [Gap.s]. Shared by the group detail sheet and the profile entity
/// detail so the "render a group's members" wiring lives once. [typeOf] maps a
/// UUID to its display type (live device type, snapshot-name fallback, …);
/// [trailing] is an optional per-speaker widget (e.g. an identify button —
/// omitted in read-only views).
List<Widget> groupMemberCards(
  ZoneGroupMember member, {
  required String Function(String uuid) typeOf,
  Widget? Function(String uuid)? trailing,
}) =>
    [
      for (final e in member.groupChannels.entries) ...[
        MemberChannelCard(
          icon: Icons.speaker,
          type: typeOf(e.key),
          channel: groupChannelShort(e.value),
          trailing: trailing?.call(e.key),
        ),
        Gap.s,
      ],
      if (member.subUuid != null)
        MemberChannelCard(
          icon: Icons.graphic_eq,
          type: typeOf(member.subUuid!),
          channel: 'Sub',
          trailing: trailing?.call(member.subUuid!),
        ),
    ];
