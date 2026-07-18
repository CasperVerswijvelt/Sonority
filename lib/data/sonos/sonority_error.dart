/// A user-facing engine/state error carried as **identity, not prose**.
///
/// The engine (`lib/data/sonos/`) is pure Dart and must not import the generated
/// `AppLocalizations` (a Flutter type). So instead of throwing an English
/// sentence, throw a [SonorityError] with a [code] (+ optional [arg]); the UI/
/// state layer words it:
///   - `friendlyError()` (this package, English) — for CLI tools, the
///     diagnostics bundle, and as the fallback. Also `toString()` here.
///   - `localizedError()` (`lib/state/localized_error.dart`) — translated via
///     `AppLocalizations` for on-screen display.
/// Keep the English in [message] and the localized copy (same keys) in step.
class SonorityError implements Exception {
  final SonorityErrorCode code;

  /// Optional single interpolation value — an entity/room label, a channel
  /// list, or the noun for a remove ("Surrounds"). Meaning depends on [code].
  final String? arg;

  const SonorityError(this.code, [this.arg]);

  /// English rendering — used by `toString()` (raw logs / CLI) and as the
  /// English fallback in `friendlyError`.
  String get message {
    final a = arg ?? '';
    switch (code) {
      case SonorityErrorCode.systemNotFound:
        return 'Couldn’t find your Sonos system on the network.';
      case SonorityErrorCode.noDevicesFound:
        return 'No Sonos devices found. Check Wi-Fi and local network access.';
      case SonorityErrorCode.descriptionsUnreadable:
        return 'Found Sonos players but could not read their descriptions.';
      case SonorityErrorCode.topologyUnreadable:
        return 'Could not read the Sonos topology from any player.';
      case SonorityErrorCode.entityNotOnNetwork:
        return '“$a” isn’t on the network.';
      case SonorityErrorCode.coordinatorNotOnNetwork:
        return '“$a” coordinator isn’t on the network.';
      case SonorityErrorCode.speakerInEntityNotOnNetwork:
        return 'A speaker in “$a” isn’t on the network.';
      case SonorityErrorCode.subNotOnNetwork:
        return 'The Sub for “$a” isn’t on the network.';
      case SonorityErrorCode.soundbarNotOnNetwork:
        return 'Soundbar for “$a” isn’t on the network.';
      case SonorityErrorCode.entityMissingSpeakers:
        return '“$a” is missing speakers.';
      case SonorityErrorCode.malformedGroup:
        return 'Stored group is malformed.';
      case SonorityErrorCode.malformedHomeTheater:
        return 'Stored home theater is malformed.';
      case SonorityErrorCode.didNotForm:
        return 'Sonos did not form “$a”.';
      case SonorityErrorCode.didNotCreateGroup:
        return 'Sonos did not create the group — a speaker may be incompatible.';
      case SonorityErrorCode.didNotSeparate:
        return 'Sonos did not separate the group — try again.';
      case SonorityErrorCode.didNotRemove:
        return 'Sonos did not remove the $a — try again.';
      case SonorityErrorCode.groupNeedsTwo:
        return 'A group needs at least 2 speakers.';
      case SonorityErrorCode.speakerIpUnknown:
        return 'Speaker IP unknown; rescan and retry.';
      case SonorityErrorCode.soundbarIpUnknown:
        return 'Soundbar IP unknown; rescan and retry.';
      case SonorityErrorCode.coordinatorIpUnknown:
        return 'Coordinator IP unknown; rescan and retry.';
      case SonorityErrorCode.bondingIncomplete:
        return 'Bonding did not complete — these channels never joined: $a. '
            'Try again, or finish in the Sonos app.';
      case SonorityErrorCode.noLanIpForChime:
        return 'No LAN IP found to serve the chime from.';
      case SonorityErrorCode.cannotBlinkLight:
        return 'Could not reach the speaker to blink its light.';
    }
  }

  @override
  String toString() => message;
}

/// Stable identity for each user-facing engine/state error. Add a case here,
/// the English in [SonorityError.message], and the matching localized string in
/// `localizedError` + `app_en.arb` (key `err<Code>`).
enum SonorityErrorCode {
  systemNotFound,
  noDevicesFound,
  descriptionsUnreadable,
  topologyUnreadable,
  entityNotOnNetwork,
  coordinatorNotOnNetwork,
  speakerInEntityNotOnNetwork,
  subNotOnNetwork,
  soundbarNotOnNetwork,
  entityMissingSpeakers,
  malformedGroup,
  malformedHomeTheater,
  didNotForm,
  didNotCreateGroup,
  didNotSeparate,
  didNotRemove,
  groupNeedsTwo,
  speakerIpUnknown,
  soundbarIpUnknown,
  coordinatorIpUnknown,
  bondingIncomplete,
  noLanIpForChime,
  cannotBlinkLight,
}
