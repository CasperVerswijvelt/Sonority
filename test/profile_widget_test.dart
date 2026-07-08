import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/profiles/profile_widget.dart';

void main() {
  group('applyIdFromWidgetUri', () {
    test('extracts id from a canonical apply link', () {
      expect(
        applyIdFromWidgetUri(Uri.parse('sonority://apply?homeWidget=1&id=abc')),
        'abc',
      );
    });

    test('extracts id when the marker is absent (Android legacy shape)', () {
      expect(applyIdFromWidgetUri(Uri.parse('sonority://apply?id=xyz')), 'xyz');
    });

    test('returns null for null, wrong host, or missing/empty id', () {
      expect(applyIdFromWidgetUri(null), isNull);
      expect(applyIdFromWidgetUri(Uri.parse('sonority://other?id=x')), isNull);
      expect(applyIdFromWidgetUri(Uri.parse('sonority://apply')), isNull);
      expect(applyIdFromWidgetUri(Uri.parse('sonority://apply?id=')), isNull);
    });
  });

  group('hexColor', () {
    test('formats ARGB as #RRGGBB and drops alpha', () {
      expect(hexColor(const Color(0xFF1A1A1D)), '#1a1a1d');
      expect(hexColor(const Color(0x00FF8800)), '#ff8800');
      expect(hexColor(const Color(0xFF000000)), '#000000');
    });
  });
}
