import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/profiles/profile_ui.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The tonal icon must stay legible on its tonal card for every palette entry,
  // both brightnesses — the whole point of the contrast-guarded derivation.
  test('profileTonal icon clears ~3:1 on its card for every palette entry', () {
    for (var i = 0; i < profilePalette.length; i++) {
      for (final b in Brightness.values) {
        final t = profileTonal(i, b);
        expect(_contrast(t.icon, t.card), greaterThanOrEqualTo(2.9),
            reason: 'palette[$i] $b: icon vs card too low');
        // Label vs card should also read.
        expect(_contrast(t.label, t.card), greaterThanOrEqualTo(3.0),
            reason: 'palette[$i] $b: label vs card too low');
      }
    }
  });
}
