import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/cancellation.dart';
import 'package:sonority/data/sonos/identify_errors.dart';
import 'package:sonority/data/sonos/sonority_error.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/localized_error.dart';

void main() {
  // English is the only shipped locale; lookup is synchronous so no async setup.
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('AppLocalizations (en)', () {
    test('placeholder interpolation', () {
      expect(l10n.errEntityNotOnNetwork('Den'), '“Den” isn’t on the network.');
    });

    test('ICU plural picks the right branch', () {
      expect(l10n.stepBondNSpeakers(1), 'Bond 1 speaker');
      expect(l10n.stepBondNSpeakers(3), 'Bond 3 speakers');
    });
  });

  group('localizedError', () {
    test('maps a coded error to its localized string', () {
      expect(localizedError(l10n, const SonorityError(SonorityErrorCode.groupNeedsTwo)),
          'A group needs at least 2 speakers.');
    });

    test('falls back to English for an unrecognized error', () {
      expect(localizedError(l10n, Exception('boom')), 'boom');
    });

    test('maps a timeout and a SOAP busy fault', () {
      expect(localizedError(l10n, TimeoutException('x')), l10n.errTimeout);
    });

    // The engine renders these two via toString() (CLI/diagnostics stay
    // English); the UI renders them from the ARB. Pin the two so they can't
    // silently drift apart.
    test('engine English and localized strings agree for pass-through errors',
        () {
      expect(l10n.errChimeUnreachable, const SpeakerUnreachable().toString());
      expect(localizedError(l10n, const SpeakerUnreachable()),
          const SpeakerUnreachable().toString());
      expect(l10n.errAborted, const OperationCancelled().toString());
      expect(localizedError(l10n, const OperationCancelled()),
          const OperationCancelled().toString());
    });
  });

  group('captured-settings copy', () {
    // The profile-entity detail localizes SpeakerSettings.describe() rows via
    // these keys; pin the ones that are words (not number formats) so a rename
    // or deletion is caught.
    test('setting labels and value words resolve', () {
      expect(l10n.settingSubGain, 'Sub level');
      expect(l10n.settingSurroundLevel, 'Surround level (TV)');
      expect(l10n.settingOn, 'On');
      expect(l10n.settingOff, 'Off');
      expect(l10n.settingSurroundAmbient, 'Ambient');
      expect(l10n.settingSurroundFull, 'Full');
    });
  });
}
