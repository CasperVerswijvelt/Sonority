/// Recipes for Sonos **speaker groups** — the channel-map bonds (`AddBondedZones`)
/// behind stereo pairs, zones, and custom L/R layouts. 2–16 individual speakers
/// bond into one room; each plays a chosen channel; an optional Sub joins on `SW`.
///
/// Pure (no Flutter / repository deps) so the CLI tools can reuse it — same
/// reason `front_layout.dart` exists separately.
library;

import 'channel_map.dart';

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

/// True when a group edit ONLY removes members: same coordinator, a strictly
/// smaller membership, and every kept member keeping the exact channels it has.
///
/// That is precisely the shape `zones.updateZoneDefinition` accepts — the
/// namespace allows **add or remove, one direction per call, membership only**
/// (hardware-confirmed; a channel change or a simultaneous add+remove is refused
/// with `update only allows add or remove, not both`). It is also the shape
/// `AddBondedZones` faults on, which is why the legacy SOAP path had to dissolve
/// the whole group and rebuild it. Both maps are raw `UUID:CH,CH;…` strings.
bool groupEditIsPureDrop({
  required String currentMap,
  required String targetMap,
}) {
  final current = ChannelMap.parse(currentMap).entries;
  final target = ChannelMap.parse(targetMap).entries;
  if (current.isEmpty || target.isEmpty) return false;
  if (current.first.uuid != target.first.uuid) return false;
  if (target.length >= current.length) return false;

  final currentTokens = {for (final e in current) e.uuid: e.tokens};
  for (final e in target) {
    final was = currentTokens[e.uuid];
    if (was == null) return false; // an add — not a pure drop
    if (!_sameTokens(was, e.tokens)) return false; // a reassignment
  }
  return true;
}

/// Token-set comparison that keeps MULTIPLICITY: `LF,LF` (single-sided, a stereo
/// pair's left half) is a different assignment from `LF`, so a plain Set compare
/// would call two different bond shapes equal. Order within an entry is still
/// irrelevant.
bool _sameTokens(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final x = [...a]..sort();
  final y = [...b]..sort();
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

/// True when two raw channel maps describe the same bond.
///
/// The FIRST entry is the coordinator, so it must match exactly. The remaining
/// entries are compared **unordered**, because which order Sonos lists the rest
/// in is not part of the bond's identity — and it does not preserve ours.
/// Requiring the whole list to match positionally cost a real failure: the map
/// we asked for didn't match the definition Sonos had already stored for it, so
/// we added a duplicate, Sonos deduped it onto the existing one, and nothing new
/// appeared for us to activate (1 of 3 rounds in `tool/bond_timing.dart`).
///
/// Token order *within* an entry is likewise irrelevant, but token multiplicity
/// is not — see [_sameTokens].
bool sameChannelMap(String a, String b) {
  final x = ChannelMap.parse(a).entries;
  final y = ChannelMap.parse(b).entries;
  if (x.length != y.length || x.isEmpty) return false;
  if (x.first.uuid != y.first.uuid) return false;
  if (!_sameTokens(x.first.tokens, y.first.tokens)) return false;
  final rest = {for (final e in y.skip(1)) e.uuid: e.tokens};
  if (rest.length != y.length - 1) return false; // a duplicated member uuid
  for (final e in x.skip(1)) {
    final other = rest[e.uuid];
    if (other == null || !_sameTokens(e.tokens, other)) return false;
  }
  return true;
}
