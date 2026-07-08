import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/profiles/profile.dart';
import 'package:sonority/features/profiles/profile_shortcuts.dart';

void main() {
  Profile p(String id) => Profile(id: id, name: 'P $id', entities: const []);

  group('publish cap', () {
    test('caps at maxProfileShortcuts, preserving order', () {
      final many = [for (var i = 0; i < 7; i++) p('$i')];
      final published = shortcutProfiles(many);
      expect(published.length, maxProfileShortcuts);
      expect(published.map((x) => x.id).toList(), ['0', '1', '2', '3']);
    });

    test('passes through when under the cap', () {
      expect(shortcutProfiles([p('a'), p('b')]).length, 2);
    });
  });

  group('profile appearance JSON', () {
    test('round-trips iconId + color', () {
      final orig = Profile(
          id: '1', name: 'X', entities: const [], iconId: 'movie', color: 3);
      final back = Profile.fromJson(orig.toJson());
      expect(back.iconId, 'movie');
      expect(back.color, 3);
    });

    test('defaults gracefully for pre-feature profiles (no appearance keys)', () {
      final back = Profile.fromJson({'id': '1', 'name': 'Old', 'entities': []});
      expect(back.iconId, kDefaultProfileIcon);
      expect(back.color, 0);
    });
  });
}
