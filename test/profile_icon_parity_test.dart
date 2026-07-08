import 'package:flutter_test/flutter_test.dart';

import 'package:sonority/features/profiles/profile_shortcuts.dart';
import 'package:sonority/features/profiles/profile_ui.dart';

/// Guards the three hand-synced icon maps keyed by the same iconIds:
/// [profileIconChoices] (Material), `_profileSfIcons` (iOS SFIcon), and
/// `_sfSymbols` (native shortcut SF-symbol names). Adding an icon to one but
/// forgetting another silently falls back to a default glyph — this catches it.
void main() {
  test('profile icon maps share identical key sets', () {
    final material = profileIconChoices.keys.toSet();
    expect(profileSfIconKeys, material);
    expect(shortcutSfSymbolKeys, material);
  });
}
