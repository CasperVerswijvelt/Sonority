import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/core/theme.dart';
import 'package:sonority/features/widgets/label_value_row.dart';

/// A `Row` gives its NON-flex children unbounded main-axis constraints, so a
/// bare `Text` value never wraps: it claimed the whole width, `freeSpace` went
/// negative and the `Expanded` label was clamped to zero. Measured in the
/// Trueplay breakdown's real indent at 1080x2400 dpr 3, the label went
/// 102.75 → 11.75 → 0 → 0 px across these four scales, and from 2.0 the row
/// overflowed (silently clipped in a release build).
///
/// The speaker name is the entire payload of the breakdown — the counter
/// already says how many, the row exists to say WHICH — so losing the label is
/// losing the feature. Hence a real test rather than an eyeball at 1.0.
void main() {
  // gutter + a 24pt icon + the ListTile's 16pt title gap, as the Trueplay
  // breakdown indents its rows.
  const indent = EdgeInsets.fromLTRB(kPageGutter + 40, 0, kPageGutter, 12);

  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    testWidgets('label and value both keep width at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: scale, maxScaleFactor: scale, child: child!),
        home: const Scaffold(
          body: Padding(
            padding: indent,
            child: LabelValueRow(label: 'Era 100', value: "Couldn't read"),
          ),
        ),
      ));

      final label = tester.getSize(find.text('Era 100'));
      final value = tester.getSize(find.text("Couldn't read"));
      printOnFailure('label $label · value $value');
      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
      expect(label.width, greaterThan(0),
          reason: 'the speaker name is the payload');
      expect(value.width, greaterThan(0));
      // "Era 100" is the shorter string, so it can never legitimately need
      // more lines than "Couldn't read". It is what catches 1.5x, where the
      // label kept a non-zero 11.75px box and wrapped into nine lines.
      expect(label.height, lessThanOrEqualTo(value.height),
          reason: 'the shorter half was squeezed narrower than the longer one');
    });
  }

  testWidgets('at 1.0 the label reads left and the value right-aligned',
      (tester) async {
    // Guards the fix against being "fixed" into a different layout: the
    // existing screenshots show label-left / value-right, and making the value
    // flexible must not disturb that.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: indent,
          child: LabelValueRow(label: 'Era 100', value: "Couldn't read"),
        ),
      ),
    ));

    final row = tester.getRect(find.byType(LabelValueRow));
    expect(tester.getTopLeft(find.text('Era 100')).dx, row.left);
    expect(tester.getTopRight(find.text("Couldn't read")).dx, row.right);
    // One line each: the pair fits at 1.0, and a fix that made it stack would
    // have changed every screenshot.
    expect(tester.getSize(find.text("Couldn't read")).height,
        tester.getSize(find.text('Era 100')).height);
  });
}
