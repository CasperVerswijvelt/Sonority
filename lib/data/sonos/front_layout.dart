import '../models/sonos_models.dart';
import 'channel_map.dart';

/// Pure (Flutter-free) builders for the `HTSatChanMapSet`. Kept dependency-free
/// so both [SonosRepository] and the CLI tools can use them without dragging in
/// `shared_preferences`/Flutter. Confirmed against a live Sonos Beam whose stock
/// layout is `RINCON_BEAM:CC;…:LR;…:RR;…:SW`.

/// General `HTSatChanMapSet` builder: sets the channels in [desired]
/// (channel → satellite UUID) on top of the soundbar, preserving any existing
/// channels not mentioned. The soundbar stays the `CC` primary. Generalises
/// [buildDedicatedFrontsMap] to surrounds (`LR`/`RR`) and a sub (`SW`) so the HT
/// flow can build a complete layout, and so a saved profile can be re-applied.
///
/// - To override fronts: pass `{leftFront: x, rightFront: y}`.
/// - For an Amp on both fronts: pass `{leftFront: amp, rightFront: amp}` — same
///   UUID groups into one `AMP:LF,RF` entry.
/// - Output channel order is canonical (LF, RF, LR, RR, SW) so encodings are
///   deterministic; Sonos ignores order. Removing a role is a separate
///   `RemoveHTSatellite` — this only adds/overrides.
///
/// The Sub (`SW`) is the one channel that can repeat — an HT supports up to two
/// Subs. A single Sub may still be passed as `desired[SonosChannel.sub]`;
/// [subUuids] adds any further Subs. Both are unioned with the existing Subs.
ChannelMap buildLayoutMap({
  required ZoneGroupMember soundbar,
  required SonosDevice soundbarDevice,
  required Map<SonosChannel, String> desired,
  List<String> subUuids = const [],
  bool preserveExisting = true,
}) {
  // Final channel → UUID: existing satellites (if preserving) overlaid by the
  // desired assignments. `channelAssignments` already skips the CC primary.
  final assign = <SonosChannel, String>{
    if (preserveExisting) ...soundbar.channelAssignments,
    ...desired,
  }..remove(SonosChannel.sub); // subs handled below (the channel can repeat)

  // Existing Subs (via uuidsForChannel — `channelAssignments` collapses dual-sub
  // to one) unioned with the requested Sub(s), order-preserving + de-duped.
  final subs = <String>{
    if (preserveExisting) ...soundbar.uuidsForChannel(SonosChannel.sub),
    if (desired[SonosChannel.sub] != null) desired[SonosChannel.sub]!,
    ...subUuids,
  };

  final entries = <ChannelMapEntry>[
    ChannelMapEntry.fromChannels(soundbarDevice.uuid, [SonosChannel.center]),
  ];
  // Group channels by UUID in canonical order (so an Amp's LF+RF collapse into
  // one entry, and output is stable).
  const order = [
    SonosChannel.leftFront,
    SonosChannel.rightFront,
    SonosChannel.leftRear,
    SonosChannel.rightRear,
  ];
  final byUuid = <String, List<SonosChannel>>{};
  for (final ch in order) {
    final uuid = assign[ch];
    if (uuid == null) continue;
    byUuid.putIfAbsent(uuid, () => []).add(ch);
  }
  for (final e in byUuid.entries) {
    entries.add(ChannelMapEntry.fromChannels(e.key, e.value));
  }
  for (final u in subs) {
    entries.add(ChannelMapEntry.fromChannels(u, [SonosChannel.sub]));
  }
  return ChannelMap(entries);
}

/// The minimal change to turn [current]'s live HT layout into [target].
class HtDiff {
  /// Current already equals target (same satellites on the same channels) —
  /// nothing to write at all.
  final bool isNoOp;

  /// Satellite UUIDs bonded now that the target no longer keeps at all — a
  /// genuine LEAVE (a dropped sub, or a speaker replaced by a different one).
  /// These must be `RemoveHTSatellite`'d first — `AddHTSatellite` 800s on a map
  /// that would drop a still-bonded speaker.
  ///
  /// A satellite that merely MOVES channel (stays in the target on a different
  /// channel, e.g. a fronts↔surrounds swap) is deliberately NOT here: it's left
  /// bonded and `AddHTSatellite` reassigns it in place. Removing movers first is
  /// what forced the "one speaker per side" in-between state, and it bought no
  /// reliability — a swap 800s mid-reshuffle and re-asserts several times either
  /// way (hardware-tested, `tool/diff_apply_spike.dart` case c), so we skip the
  /// strip and let the re-assert converge on the full target.
  final Set<String> toRemove;

  /// The target map to bond, unchanged — `bondAndVerify` adds whatever's missing.
  final ChannelMap target;

  const HtDiff(
      {required this.isNoOp, required this.toRemove, required this.target});
}

/// Diffs [current]'s live satellite layout against [target] so an apply can do
/// the minimum: skip when unchanged, `RemoveHTSatellite` only the satellites
/// that must change, then additively bond the target.
///
/// Keyed by UUID → set of channels (read via [ZoneGroupMember.uuidsForChannel])
/// so dual-sub (two `SW` UUIDs) and an Amp (`{LF,RF}` on one UUID) diff
/// correctly — `channelAssignments` collapses dual-sub, so it can't be used here.
HtDiff diffHtLayout({
  required ZoneGroupMember current,
  required ChannelMap target,
}) {
  // ponytail: diff over modelled SonosChannels only; the live rig is 5.1, so an
  // unmodelled token (Atmos/height) won't trigger a remove and bondAndVerify
  // ignores it too — widen this list if a layout ever needs those.
  const channels = [
    SonosChannel.leftFront,
    SonosChannel.rightFront,
    SonosChannel.leftRear,
    SonosChannel.rightRear,
    SonosChannel.sub,
  ];

  final cur = <String, Set<SonosChannel>>{};
  for (final ch in channels) {
    for (final uuid in current.uuidsForChannel(ch)) {
      (cur[uuid] ??= <SonosChannel>{}).add(ch);
    }
  }

  final tgt = <String, Set<SonosChannel>>{};
  for (final e in target.entries.skip(1)) {
    final set = e.channels.toSet();
    if (set.isNotEmpty) (tgt[e.uuid] ??= <SonosChannel>{}).addAll(set);
  }

  // Only satellites the target drops entirely must be RemoveHTSatellite'd first
  // (a genuine leave — the case AddHTSatellite 800s on). A satellite that stays
  // in the target on a different channel is left bonded and reassigned in place.
  final toRemove = <String>{
    for (final e in cur.entries)
      if (!tgt.containsKey(e.key)) e.key,
  };

  // Identical layout ⇒ no-op: same satellites, each on the exact same channels.
  // (A pure move has an empty toRemove but is NOT a no-op — it still writes.)
  final isNoOp = cur.length == tgt.length &&
      cur.entries.every((e) => _sameChannels(tgt[e.key], e.value));

  return HtDiff(isNoOp: isNoOp, toRemove: toRemove, target: target);
}

bool _sameChannels(Set<SonosChannel>? a, Set<SonosChannel> b) =>
    a != null && a.length == b.length && a.containsAll(b);
