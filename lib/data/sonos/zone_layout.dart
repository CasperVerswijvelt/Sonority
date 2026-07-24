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

/// Short channel label for the group detail UI: `L` / `R` / `L+R`.
String groupChannelShort(GroupChannel c) => switch (c) {
      GroupChannel.left => 'L',
      GroupChannel.right => 'R',
      GroupChannel.both => 'L+R',
    };

/// Full channel label for group summaries: `Left` / `Right` / `Both`.
String groupChannelLabel(GroupChannel c) => switch (c) {
      GroupChannel.left => 'Left',
      GroupChannel.right => 'Right',
      GroupChannel.both => 'Both',
    };

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

/// Whether an edit of a live group (from [currentUuids] — its bonded members
/// incl. any Sub, coordinator first — to [targetUuids] with coordinator
/// [targetCoordUuid]) can apply IN PLACE via a single `AddBondedZones` re-assert,
/// vs. needing a dissolve-then-recreate. In place iff the coordinator is
/// unchanged AND no current member is dropped (adds + channel reassignments only).
/// Hardware-confirmed (`tool/group_reassert_spike.dart`): `AddBondedZones`
/// adds/reassigns a live group in place, but faults on any map that drops a
/// currently-bonded member — so a removal (or a coordinator change) must dissolve.
bool groupEditIsInPlace({
  required List<String> currentUuids,
  required List<String> targetUuids,
  required String targetCoordUuid,
}) =>
    currentUuids.isNotEmpty &&
    targetCoordUuid == currentUuids.first &&
    currentUuids.every(targetUuids.contains);
