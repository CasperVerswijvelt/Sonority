import 'dart:async';

import 'soap_client.dart';

/// Turns a raw engine exception into a short, plain-English sentence for the
/// failed-step text on the apply/bond progress screen. The full technical
/// detail still lands in the raw operation log (the terminal-toggle view in
/// `bonding_progress_screen.dart`), so this only needs to read cleanly — it
/// doesn't have to be exhaustive.
///
/// Only the ugly-`toString()` faults (a raw timeout / SOAP fault) get a bespoke
/// sentence; everything else falls through to the tail, which returns the
/// exception's own text minus Dart's noisy `Exception: ` prefix. Exceptions that
/// already carry user-facing copy pass straight through there unchanged — e.g.
/// `OperationCancelled` ('Aborted', kept verbatim so an abort reads as neutral,
/// not a failure) and `SpeakerUnreachable` — both pinned by tests.
String friendlyError(Object e) {
  if (e is TimeoutException) {
    return 'The speaker didn’t respond in time. It may still be settling — '
        'try again in a moment.';
  }
  if (e is SonosSoapException) {
    // Sonos UPnP fault codes we've confirmed on hardware (see CLAUDE.md).
    switch (e.faultCode) {
      case '800':
        return 'Sonos is busy rearranging speakers right now. Wait a moment '
            'and try again.';
      case '401':
        return 'Sonos wouldn’t bond these speakers this way (unsupported '
            'combination).';
      case '402':
        return 'Sonos rejected the request as invalid.';
    }
    final code = e.faultCode;
    return code == null
        ? 'Sonos reported an error. See the raw log for details.'
        : 'Sonos reported an error (code $code). See the raw log for details.';
  }
  // Unknown: keep the message but drop the noisy `Exception: ` prefix Dart adds,
  // so our own `Exception('…')` sentences read cleanly.
  final s = e.toString();
  const prefix = 'Exception: ';
  return s.startsWith(prefix) ? s.substring(prefix.length) : s;
}
