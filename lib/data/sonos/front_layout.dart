import '../models/sonos_models.dart';
import 'channel_map.dart';

/// Pure (Flutter-free) builder for the dedicated-front `HTSatChanMapSet`.
///
/// Kept dependency-free so both [SonosRepository] and the CLI tools can use it
/// without dragging in `shared_preferences`/Flutter.
///
/// Builds: the soundbar primary (kept as-is, e.g. `CC` center) plus the two
/// chosen speakers mapped to the front L/R channels, preserving any existing
/// rear surrounds / sub. Confirmed against a live Sonos Beam whose stock layout
/// is `RINCON_BEAM:CC;…:LR;…:RR;…:SW`.
ChannelMap buildDedicatedFrontsMap({
  required ZoneGroupMember soundbar,
  required SonosDevice soundbarDevice,
  required SonosDevice leftSpeaker,
  required SonosDevice rightSpeaker,
}) {
  return ChannelMap([
    ..._preservedNonFrontEntries(soundbar, soundbarDevice),
    ChannelMapEntry.fromChannels(leftSpeaker.uuid, [SonosChannel.leftFront]),
    ChannelMapEntry.fromChannels(rightSpeaker.uuid, [SonosChannel.rightFront]),
  ]);
}

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
ChannelMap buildLayoutMap({
  required ZoneGroupMember soundbar,
  required SonosDevice soundbarDevice,
  required Map<SonosChannel, String> desired,
  bool preserveExisting = true,
}) {
  // Final channel → UUID: existing satellites (if preserving) overlaid by the
  // desired assignments. `channelAssignments` already skips the CC primary.
  final assign = <SonosChannel, String>{
    if (preserveExisting) ...soundbar.channelAssignments,
    ...desired,
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
    SonosChannel.sub,
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
  return ChannelMap(entries);
}

/// The minimal change to turn [current]'s live HT layout into [target].
class HtDiff {
  /// Current already equals target (same satellites on the same channels) —
  /// nothing to write at all.
  final bool isNoOp;

  /// Satellite UUIDs bonded now whose channel assignment differs from [target]
  /// (dropped, moved, or replaced). These must be `RemoveHTSatellite`'d before
  /// the additive bond — `AddHTSatellite` 800s on a map that would drop them.
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

  // A satellite bonded now must go first if target doesn't keep it on the exact
  // same channel set (dropped / moved / replaced).
  final toRemove = <String>{
    for (final e in cur.entries)
      if (!_sameChannels(tgt[e.key], e.value)) e.key,
  };

  // No removals AND target adds no new satellites ⇒ identical layout.
  final isNoOp = toRemove.isEmpty && tgt.length == cur.length;

  return HtDiff(isNoOp: isNoOp, toRemove: toRemove, target: target);
}

bool _sameChannels(Set<SonosChannel>? a, Set<SonosChannel> b) =>
    a != null && a.length == b.length && a.containsAll(b);

/// Variant of [buildDedicatedFrontsMap] where a single Sonos Amp drives BOTH
/// passive front speakers — it takes both front channels in one entry
/// (`AMP:LF,RF`). The official app won't bond an Amp as fronts to a soundbar.
ChannelMap buildAmpFrontsMap({
  required ZoneGroupMember soundbar,
  required SonosDevice soundbarDevice,
  required SonosDevice ampDevice,
}) {
  return ChannelMap([
    ..._preservedNonFrontEntries(soundbar, soundbarDevice),
    ChannelMapEntry.fromChannels(
        ampDevice.uuid, [SonosChannel.leftFront, SonosChannel.rightFront]),
  ]);
}

/// The soundbar primary (kept as-is, e.g. `CC` center) plus any existing
/// rears/sub, with any prior front (`LF`/`RF`) satellites dropped — the shared
/// base for both front-layout recipes.
Iterable<ChannelMapEntry> _preservedNonFrontEntries(
  ZoneGroupMember soundbar,
  SonosDevice soundbarDevice,
) {
  final existing = (soundbar.htSatChanMapSet?.isNotEmpty ?? false)
      ? ChannelMap.parse(soundbar.htSatChanMapSet!)
      // Bare soundbar with no satellites: it becomes the center channel and
      // the new front(s) take over front L/R.
      : ChannelMap([
          ChannelMapEntry.fromChannels(
              soundbarDevice.uuid, [SonosChannel.center]),
        ]);

  return existing.entries.where((e) {
    final isFrontSat = e != existing.primary &&
        (e.hasChannel(SonosChannel.leftFront) ||
            e.hasChannel(SonosChannel.rightFront));
    return !isFrontSat;
  });
}
