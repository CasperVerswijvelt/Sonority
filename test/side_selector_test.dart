import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/features/widgets/selectable_speaker_card.dart';

/// The in-card Left/Right toggle for a two-speaker pair (HT fronts/surrounds,
/// group stereo). Both flows derive the side from list order and pass a single
/// [onSwap]; guard the contract that only a genuine flip fires it.
void main() {
  Future<int> pump(
    WidgetTester tester, {
    required bool isRight,
    required String tap,
  }) async {
    var swaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SideSelector(isRight: isRight, onSwap: () => swaps++),
        ),
      ),
    );
    await tester.tap(find.text(tap));
    await tester.pump();
    return swaps;
  }

  testWidgets('tapping the opposite side fires onSwap', (tester) async {
    expect(await pump(tester, isRight: false, tap: 'Right'), 1);
    expect(await pump(tester, isRight: true, tap: 'Left'), 1);
  });

  testWidgets('tapping the already-selected side is a no-op', (tester) async {
    expect(await pump(tester, isRight: false, tap: 'Left'), 0);
    expect(await pump(tester, isRight: true, tap: 'Right'), 0);
  });
}
