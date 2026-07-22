import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/app.dart';

// macOS must clamp overscroll (no rubber-band jitter); every other platform
// keeps its native physics. Regression guard for the overscroll-jitter fix.
void main() {
  Future<ScrollPhysics> physicsFor(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    late ScrollPhysics physics;
    await tester.pumpWidget(
      Theme(
        data: ThemeData(platform: platform),
        child: Builder(
          builder: (context) {
            physics = const AppScrollBehavior().getScrollPhysics(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return physics;
  }

  testWidgets('macOS clamps overscroll', (tester) async {
    expect(
      await physicsFor(tester, TargetPlatform.macOS),
      isA<ClampingScrollPhysics>(),
    );
  });

  testWidgets('iOS keeps its bouncy physics', (tester) async {
    expect(
      await physicsFor(tester, TargetPlatform.iOS),
      isA<BouncingScrollPhysics>(),
    );
  });
}
