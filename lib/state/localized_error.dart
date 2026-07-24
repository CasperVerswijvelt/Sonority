import 'dart:async';

import '../core/l10n.dart';
import '../data/sonos/cancellation.dart';
import '../data/sonos/friendly_error.dart';
import '../data/sonos/identify_errors.dart';
import '../data/sonos/soap_client.dart';
import '../data/sonos/sonority_error.dart';

/// Words an engine/state error for on-screen display, translated via
/// [AppLocalizations]. The counterpart to the engine's English `friendlyError`
/// (kept for CLI tools / the diagnostics bundle) — this is the single place the
/// UI turns a raw exception into user copy. Anything unrecognized falls back to
/// `friendlyError`'s English so no error is ever swallowed.
///
/// Pass `context.l10n`, or `appL10n()` from context-less code.
String localizedError(AppLocalizations l10n, Object e) {
  if (e is SonorityError) {
    final a = e.arg ?? '';
    // A switch *expression* so a future SonorityErrorCode added without a case
    // here is a compile error, not a silent English fallthrough.
    return switch (e.code) {
      SonorityErrorCode.systemNotFound => l10n.errSystemNotFound,
      SonorityErrorCode.noDevicesFound => l10n.errNoDevicesFound,
      SonorityErrorCode.descriptionsUnreadable => l10n.errDescriptionsUnreadable,
      SonorityErrorCode.topologyUnreadable => l10n.errTopologyUnreadable,
      SonorityErrorCode.entityNotOnNetwork => l10n.errEntityNotOnNetwork(a),
      SonorityErrorCode.coordinatorNotOnNetwork =>
        l10n.errCoordinatorNotOnNetwork(a),
      SonorityErrorCode.speakerInEntityNotOnNetwork =>
        l10n.errSpeakerInEntityNotOnNetwork(a),
      SonorityErrorCode.subNotOnNetwork => l10n.errSubNotOnNetwork(a),
      SonorityErrorCode.soundbarNotOnNetwork => l10n.errSoundbarNotOnNetwork(a),
      SonorityErrorCode.entityMissingSpeakers => l10n.errEntityMissingSpeakers(a),
      SonorityErrorCode.malformedGroup => l10n.errMalformedGroup,
      SonorityErrorCode.malformedHomeTheater => l10n.errMalformedHomeTheater,
      SonorityErrorCode.didNotForm => l10n.errDidNotForm(a),
      SonorityErrorCode.didNotCreateGroup => l10n.errDidNotCreateGroup,
      SonorityErrorCode.didNotSeparate => l10n.errDidNotSeparate,
      SonorityErrorCode.didNotRemove => l10n.errDidNotRemove(a),
      SonorityErrorCode.groupNeedsTwo => l10n.errGroupNeedsTwo,
      SonorityErrorCode.speakerIpUnknown => l10n.errSpeakerIpUnknown,
      SonorityErrorCode.soundbarIpUnknown => l10n.errSoundbarIpUnknown,
      SonorityErrorCode.coordinatorIpUnknown => l10n.errCoordinatorIpUnknown,
      SonorityErrorCode.bondingIncomplete => l10n.errBondingIncomplete(a),
      SonorityErrorCode.noLanIpForChime => l10n.errNoLanIpForChime,
      SonorityErrorCode.cannotBlinkLight => l10n.errCannotBlinkLight,
    };
  }
  if (e is OperationCancelled) return l10n.errAborted;
  if (e is SpeakerUnreachable) return l10n.errChimeUnreachable;
  if (e is TimeoutException) return l10n.errTimeout;
  if (e is SonosSoapException) {
    switch (e.faultCode) {
      case '800':
        return l10n.errSonosBusy;
      case '401':
        return l10n.errUnsupportedCombo;
      case '402':
        return l10n.errInvalidRequest;
    }
    final code = e.faultCode;
    return code == null ? l10n.errSonosGeneric : l10n.errSonosCode(code);
  }
  // Unknown: fall back to the engine's English (never swallow an error).
  return friendlyError(e);
}
