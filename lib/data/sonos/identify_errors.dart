/// Thrown when a speaker accepts the play command but never fetches the clip,
/// meaning it can't reach this device over the network. Lives in its own
/// web-safe file (no `dart:io`) so both the IO and web `IdentifyServiceClient`
/// impls and the UI (`identify_controls.dart`) can share it.
class SpeakerUnreachable implements Exception {
  const SpeakerUnreachable();
  @override
  String toString() =>
      'The speaker could not reach your phone to play the sound. Make sure '
      'your phone and speakers are on the same Wi‑Fi network. (Android '
      'emulators can’t reach speakers on your LAN — use a real device.)';
}
