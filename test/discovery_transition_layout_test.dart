import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The discovery screen's PageTransitionSwitcher must top-align its entries:
/// with the default center-aligned Stack, short (shrink-wrapped) system
/// content floats to the vertical middle mid-transition while the expanding
/// scanning placeholder inflates the Stack. Mirrors the switcher config in
/// discovery_screen.dart.
Widget _switcher(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 250),
        layoutBuilder: (entries) =>
            Stack(alignment: Alignment.topCenter, children: entries),
        transitionBuilder: (child, anim, secondaryAnim) => SharedAxisTransition(
          animation: anim,
          secondaryAnimation: secondaryAnim,
          transitionType: SharedAxisTransitionType.scaled,
          fillColor: Colors.transparent,
          child: child,
        ),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('short content stays top-aligned mid-transition', (
    tester,
  ) async {
    const shortContent = Key('short');
    final short = SingleChildScrollView(
      key: const ValueKey('system'),
      child: Column(
        children: [SizedBox(key: shortContent, height: 100, width: 100)],
      ),
    );
    const spinner = Center(
      key: ValueKey('scanning'),
      child: CircularProgressIndicator(),
    );

    await tester.pumpWidget(_switcher(short));
    expect(tester.getTopLeft(find.byKey(shortContent)).dy, 0);

    // Swap to the expanding placeholder and freeze mid-transition: the
    // outgoing short content must not sink toward the center (the default
    // center-aligned Stack would put it ~250px down). A few px of slack
    // absorbs the exit transition's zoom-out transform.
    await tester.pumpWidget(_switcher(spinner));
    await tester.pump(const Duration(milliseconds: 125));
    expect(tester.getTopLeft(find.byKey(shortContent)).dy, closeTo(0, 10));
  });
}
