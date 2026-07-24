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
    // Content fits, so nothing scrolls: total height must equal the viewport
    // exactly (regression guard — the footer's min-height fills the leftover
    // space precisely, so its padding never tips it into a few px of scroll).
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, 0);
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

  testWidgets('a footer taller than the leftover space scrolls, not overflows', (
    tester,
  ) async {
    // Regression: a SwitchListTile subtitle that wraps makes the footer taller
    // than the leftover viewport. ScrollFooter must let it scroll — not clamp it
    // to a too-short box and overflow (ListTile mis-reports its intrinsic height
    // when the subtitle wraps, which SliverFillRemaining trusted → 16px overflow).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 420,
              child: ScrollFooter(
                padding: const EdgeInsets.only(top: 8, bottom: 80),
                footer: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    Divider(height: 1),
                    SwitchListTile(
                      value: false,
                      onChanged: null,
                      secondary: Icon(Icons.tune),
                      title: Text('Save audio settings'),
                      subtitle: Text(
                        'EQ, night sound, speech enhancement, sub & surround '
                        'levels, lip sync & more',
                      ),
                    ),
                    SwitchListTile(
                      value: false,
                      onChanged: null,
                      secondary: Icon(Icons.volume_up),
                      title: Text('Save volume'),
                      subtitle: Text(
                        'Applying the profile will change how loud each speaker '
                        'plays',
                      ),
                    ),
                  ],
                ),
                children: [
                  for (var i = 0; i < 3; i++)
                    Card(child: SizedBox(height: 90, child: Text('entity $i'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Save volume'), 100);
    expect(find.text('Save volume'), findsOneWidget);
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
