import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/features/speaker_eq/speaker_eq_screen.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/state/sonos_controller.dart';

import 'eq_fakes.dart';

/// The confirm latch on the EQ screen.
///
/// Applying an EQ overwrites the single calibration slot, and the coefficients
/// can never be read back — so a regression that skips this dialog destroys a
/// user's Trueplay measurement with no way back, and nothing at runtime would
/// say so. Every assertion here is on what the fake actually recorded, not on
/// widget state, because widget state reads the same whether or not the write
/// went out.
class _StubSonos extends SonosController {
  final SonosSystem system;
  _StubSonos(this.system);

  @override
  Future<SonosSystem?> build() async => system;
}

final _system = SonosSystem(
  groups: [
    const ZoneGroup(
      coordinatorUuid: 'RINCON_BAR',
      members: [ZoneGroupMember(uuid: 'RINCON_BAR', zoneName: 'Living')],
    ),
  ],
  devicesByUuid: {barDevice.uuid: barDevice},
);

void main() {
  Future<void> open(
    WidgetTester tester,
    FakeApply apply, {
    required SonosRepository repo,
  }) async {
    // A phone-height test window puts the footer (Apply / Remove) below the
    // fold, where an off-screen sliver is never built and no finder can reach
    // it. Taller viewport, so the whole page is on screen.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...eqOverrides(apply, repo: repo),
          sonosControllerProvider.overrideWith(() => _StubSonos(_system)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SpeakerEqScreen(uuid: 'RINCON_BAR'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Flushes the footer's "Applied" timer so no timer outlives the test.
  Future<void> settleAll(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('a stored calibration is confirmed before anything is written',
      (tester) async {
    final apply = FakeApply();
    // foreign: the speaker already holds a tuning we did not author.
    await open(tester, apply, repo: FakeRepo(apply: apply, foreign: true));

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Replace the existing calibration?'), findsOneWidget);
    expect(apply.posts, 0, reason: 'nothing may go out before the answer');

    await tester.tap(find.text('Cancel'));
    await settleAll(tester);
    expect(apply.posts, 0,
        reason: 'backing out of the dialog must abandon the apply');
    expect(apply.applied, isEmpty);
  });

  testWidgets('confirming lets the apply through', (tester) async {
    final apply = FakeApply();
    await open(tester, apply, repo: FakeRepo(apply: apply, foreign: true));

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await settleAll(tester);

    expect(apply.posts, greaterThan(0));
    expect(apply.applied.keys, ['RINCON_BAR']);
  });

  testWidgets('with nothing stored there is nothing to confirm', (tester) async {
    // The dialog is the price of destroying something. A speaker holding no
    // tuning has nothing to destroy, and nagging there would train the user to
    // dismiss the one that matters.
    final apply = FakeApply();
    await open(tester, apply, repo: FakeRepo(apply: apply));

    await tester.tap(find.text('Apply'));
    await settleAll(tester);
    expect(find.text('Replace the existing calibration?'), findsNothing);
    expect(apply.posts, greaterThan(0));
  });

  testWidgets('declining the remove dialog clears nothing', (tester) async {
    // ClearAllTunings is the one irreversible call in the feature.
    final apply = FakeApply();
    await open(tester, apply, repo: FakeRepo(apply: apply));

    await tester.tap(find.text('Apply'));
    await settleAll(tester);

    await tester.tap(find.text('Remove EQ'));
    await tester.pumpAndSettle();
    expect(find.text('Remove the EQ?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleAll(tester);
    expect(apply.cleared, isEmpty);

    await tester.tap(find.text('Remove EQ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await settleAll(tester);
    expect(apply.cleared, ['RINCON_BAR']);
  });
}
