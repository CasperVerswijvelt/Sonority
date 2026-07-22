import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/widgets/card_grid.dart';
import 'package:sonority/features/widgets/scroll_footer.dart';
import 'package:sonority/features/widgets/speaker_diagram.dart';

/// ScrollFooter pins its footer to the bottom when content is short and scrolls
/// when it's tall. The HT detail feeds it a SpeakerDiagram (AspectRatio +
/// Expanded rows) and the group detail feeds it a CardGrid (a LayoutBuilder on
/// wide layouts) — both must lay out without throwing. Guard the short (footer
/// pinned), tall (scrolls), tiny-viewport, and LayoutBuilder-child cases.
void main() {
  Widget host({required double height}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: height,
            child: ScrollFooter(
              padding: const EdgeInsets.all(20),
              footer: FilledButton(
                onPressed: () {},
                child: const Text('Separate'),
              ),
              children: const [
                SpeakerDiagram(
                  soundbarLabel: 'Arc',
                  frontLeftLabel: 'Era 100',
                  frontRightLabel: 'Era 100',
                  rearLeftLabel: 'Era 300',
                  rearRightLabel: 'Era 300',
                  subCount: 1,
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('lays out a diagram + footer with room to spare', (tester) async {
    await tester.pumpWidget(host(height: 900));
    expect(tester.takeException(), isNull);
    expect(find.text('Separate'), findsOneWidget);
  });

  testWidgets('lays out when content overflows the viewport', (tester) async {
    await tester.pumpWidget(host(height: 200));
    expect(tester.takeException(), isNull);
    // Footer sits at the end of the scroll (not pinned), so it's reachable by
    // scrolling down when the content is taller than the viewport.
    await tester.scrollUntilVisible(find.text('Separate'), 200);
    expect(find.text('Separate'), findsOneWidget);
  });

  testWidgets('survives a viewport shorter than the padding', (tester) async {
    // maxHeight (30) < padding.vertical (40) — must not assert on a negative
    // constraint.
    await tester.pumpWidget(host(height: 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out a CardGrid (LayoutBuilder) child on a wide viewport', (
    tester,
  ) async {
    // The default 800×600 surface is ≥ kWideLayoutBreakpoint, so CardGrid
    // returns a LayoutBuilder. It must not be intrinsic-queried by ScrollFooter
    // (that throws "LayoutBuilder does not support returning intrinsic
    // dimensions") — the exact crash on the group/HT detail pages on desktop.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollFooter(
            padding: const EdgeInsets.all(20),
            footer: FilledButton(
              onPressed: () {},
              child: const Text('Separate'),
            ),
            children: [
              CardGrid([
                for (var i = 0; i < 3; i++)
                  Card(child: SizedBox(height: 80, child: Text('card $i'))),
              ]),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Separate'), findsOneWidget);
  });
}
