import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/widgets/scroll_footer.dart';
import 'package:sonority/features/widgets/speaker_diagram.dart';

/// ScrollFooter wraps its children in an IntrinsicHeight (so the footer pins to
/// the bottom when content is short). The HT detail feeds it a SpeakerDiagram —
/// an AspectRatio with Expanded rows inside — which is exactly the kind of child
/// that can throw during intrinsic sizing. Guard the short (footer pinned), tall
/// (scrolls), and tiny-viewport (minHeight clamp) cases.
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
    expect(find.text('Separate'), findsOneWidget);
  });

  testWidgets('survives a viewport shorter than the padding', (tester) async {
    // maxHeight (30) < padding.vertical (40) — minHeight must clamp to 0, not
    // assert on a negative BoxConstraints.
    await tester.pumpWidget(host(height: 30));
    expect(tester.takeException(), isNull);
  });
}
