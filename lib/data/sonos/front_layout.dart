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
