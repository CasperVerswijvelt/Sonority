import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

/// Terse access to the generated strings from any widget: `context.l10n.foo`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The current strings **without a BuildContext** — for the state layer
/// (`sonos_controller.dart`) and other context-less code that must produce
/// user-facing text (progress step labels, error wording). Resolves the system
/// locale against the supported set (falls back to English) and loads it
/// synchronously (gen-l10n's `lookupAppLocalizations` is synchronous).
AppLocalizations appL10n() {
  final resolved = basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(resolved);
}
