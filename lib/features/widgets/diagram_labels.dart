import '../../data/models/sonos_models.dart';

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
  return system?.device(uuid)?.typeLabel ?? names?[uuid] ?? 'Speaker';
}

/// Whether a speaker is currently bonded to [channel].
bool hasChannel(ZoneGroupMember member, SonosChannel channel) =>
    member.channelAssignments.containsKey(channel);
