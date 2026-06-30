/// Recipes for Sonos **speaker groups** — the channel-map bonds (`AddBondedZones`)
/// behind stereo pairs, zones, and custom L/R layouts. 2–16 individual speakers
/// bond into one room; each plays a chosen channel; an optional Sub joins on `SW`.
///
/// Pure (no Flutter / repository deps) so the CLI tools can reuse it — same
/// reason `front_layout.dart` exists separately.
library;

/// The channel a group member plays. Confirmed on hardware (`tool/lr_audiotest.dart`):
/// Sonos honours these per-speaker — `both` plays full stereo, `left`/`right` only
/// that side.
enum GroupChannel {
  both('LF,RF'),
  left('LF,LF'),
  right('RF,RF');

  const GroupChannel(this.tokens);
  final String tokens;
}

/// Builds the `ChannelMapSet` for `AddBondedZones`. The first member is the
/// coordinator (the room that stays visible); an optional [subUuid] is appended
/// as `SW`. e.g. `A:LF,LF;B:RF,RF;SUB:SW` (stereo pair + sub).
String buildGroupMap(
  List<({String uuid, GroupChannel channel})> members, {
  String? subUuid,
}) {
  final parts = [for (final m in members) '${m.uuid}:${m.channel.tokens}'];
  if (subUuid != null) parts.add('$subUuid:SW');
  return parts.join(';');
}

/// Shorthand for an all-full-range zone (every member `LF,RF`). Coordinator first.
String buildZoneMap(List<String> uuids) => buildGroupMap(
    [for (final u in uuids) (uuid: u, channel: GroupChannel.both)]);
