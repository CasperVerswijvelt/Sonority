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
