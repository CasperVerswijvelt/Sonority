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
  final existing = (soundbar.htSatChanMapSet?.isNotEmpty ?? false)
      ? ChannelMap.parse(soundbar.htSatChanMapSet!)
      // Bare soundbar with no satellites: it becomes the center channel and
      // the two new speakers take over front L/R.
      : ChannelMap([
          ChannelMapEntry.fromChannels(
              soundbarDevice.uuid, [SonosChannel.center]),
        ]);

  // Drop any prior front assignments, then add the new ones.
  final preserved = existing.entries.where((e) {
    final isFrontSat = e != existing.primary &&
        (e.hasChannel(SonosChannel.leftFront) ||
            e.hasChannel(SonosChannel.rightFront));
    return !isFrontSat;
  });

  return ChannelMap([
    ...preserved,
    ChannelMapEntry.fromChannels(leftSpeaker.uuid, [SonosChannel.leftFront]),
    ChannelMapEntry.fromChannels(rightSpeaker.uuid, [SonosChannel.rightFront]),
  ]);
}
