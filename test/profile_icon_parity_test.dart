import 'package:flutter_test/flutter_test.dart';

import 'package:sonority/features/profiles/profile_ui.dart';

/// Guards the hand-synced icon maps keyed by the curated [profileIconIds]:
/// `_profileSfIcons` (SFIcon glyphs) and `_sfSymbolNames` (SF-symbol names for
/// the native shortcut + widget). Adding an icon to one but forgetting another
/// silently falls back to a default glyph — this catches it.
void main() {
  test('profile icon maps share identical key sets', () {
    final ids = profileIconIds.toSet();
    expect(profileSfIconKeys, ids);
    expect(sfSymbolNameKeys, ids);
  });
}
