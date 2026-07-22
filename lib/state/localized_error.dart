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
    switch (e.code) {
      case SonorityErrorCode.systemNotFound:
        return l10n.errSystemNotFound;
      case SonorityErrorCode.noDevicesFound:
        return l10n.errNoDevicesFound;
      case SonorityErrorCode.descriptionsUnreadable:
        return l10n.errDescriptionsUnreadable;
      case SonorityErrorCode.topologyUnreadable:
        return l10n.errTopologyUnreadable;
      case SonorityErrorCode.entityNotOnNetwork:
        return l10n.errEntityNotOnNetwork(a);
      case SonorityErrorCode.coordinatorNotOnNetwork:
        return l10n.errCoordinatorNotOnNetwork(a);
      case SonorityErrorCode.speakerInEntityNotOnNetwork:
        return l10n.errSpeakerInEntityNotOnNetwork(a);
      case SonorityErrorCode.subNotOnNetwork:
        return l10n.errSubNotOnNetwork(a);
      case SonorityErrorCode.soundbarNotOnNetwork:
        return l10n.errSoundbarNotOnNetwork(a);
      case SonorityErrorCode.entityMissingSpeakers:
        return l10n.errEntityMissingSpeakers(a);
      case SonorityErrorCode.malformedGroup:
        return l10n.errMalformedGroup;
      case SonorityErrorCode.malformedHomeTheater:
        return l10n.errMalformedHomeTheater;
      case SonorityErrorCode.didNotForm:
        return l10n.errDidNotForm(a);
      case SonorityErrorCode.didNotCreateGroup:
        return l10n.errDidNotCreateGroup;
      case SonorityErrorCode.didNotSeparate:
        return l10n.errDidNotSeparate;
      case SonorityErrorCode.didNotRemove:
        return l10n.errDidNotRemove(a);
      case SonorityErrorCode.groupNeedsTwo:
        return l10n.errGroupNeedsTwo;
      case SonorityErrorCode.speakerIpUnknown:
        return l10n.errSpeakerIpUnknown;
      case SonorityErrorCode.soundbarIpUnknown:
        return l10n.errSoundbarIpUnknown;
      case SonorityErrorCode.coordinatorIpUnknown:
        return l10n.errCoordinatorIpUnknown;
      case SonorityErrorCode.bondingIncomplete:
        return l10n.errBondingIncomplete(a);
      case SonorityErrorCode.noLanIpForChime:
        return l10n.errNoLanIpForChime;
      case SonorityErrorCode.cannotBlinkLight:
        return l10n.errCannotBlinkLight;
    }
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
