import '../../data/models/sonos_models.dart';

/// Best-effort speaker label for a bonded channel, derived from the
/// authoritative `HTSatChanMapSet`: discovered device name → satellite zone
/// name → generic. Returns null when no speaker is assigned to [channel].
String? labelForChannel(
    SonosSystem system, ZoneGroupMember member, SonosChannel channel) {
  final uuid = member.channelAssignments[channel];
  if (uuid == null) return null;
  final dev = system.device(uuid);
  if (dev != null) return dev.roomName;
  final sat = member.satellites.where((s) => s.uuid == uuid);
  if (sat.isNotEmpty && sat.first.zoneName.isNotEmpty) return sat.first.zoneName;
  return 'Speaker';
}

/// Whether a speaker is currently bonded to [channel].
bool hasChannel(ZoneGroupMember member, SonosChannel channel) =>
    member.channelAssignments.containsKey(channel);
