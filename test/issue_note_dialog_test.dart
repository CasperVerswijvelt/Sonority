import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/widgets/issue_note_dialog.dart';
import 'package:sonority/l10n/app_localizations.dart';

/// The gate that stops an unexplained diagnostics bundle reaching the developer:
/// Continue must stay dead until the description is long enough, and cancelling
/// must yield null so the caller builds nothing.
void main() {
  /// Opens the dialog and returns the future holding its result.
  Future<Future<String?>> open(WidgetTester tester) async {
    late Future<String?> result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => result = showIssueNoteDialog(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  VoidCallback? continueAction(WidgetTester tester) => tester
      .widget<TextButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(TextButton),
        ),
      )
      .onPressed;

  testWidgets('Continue is disabled until the minimum length', (tester) async {
    await open(tester);
    expect(continueAction(tester), isNull, reason: 'empty');

    await tester.enterText(find.byType(TextField), 'a' * (kMinIssueNoteLength - 1));
    await tester.pump();
    expect(continueAction(tester), isNull, reason: 'one char short');

    await tester.enterText(find.byType(TextField), 'a' * kMinIssueNoteLength);
    await tester.pump();
    expect(continueAction(tester), isNotNull, reason: 'at the threshold');
  });

  testWidgets('whitespace does not count toward the minimum', (tester) async {
    await open(tester);
    await tester.enterText(
      find.byType(TextField),
      '${' ' * 40}${'a' * (kMinIssueNoteLength - 1)}${' ' * 40}',
    );
    await tester.pump();
    expect(continueAction(tester), isNull);
  });

  testWidgets('Continue returns the trimmed text', (tester) async {
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), '  fronts bond but stay silent  ');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await result, 'fronts bond but stay silent');
  });

  testWidgets('Cancel returns null so nothing is collected', (tester) async {
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), 'a' * kMinIssueNoteLength);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
