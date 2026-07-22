import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/l10n/app_localizations.dart';
import 'package:sonority/features/widgets/sheet_scaffold.dart';

/// SheetScaffold has two layout modes (content-sized vs fill) and an optional
/// pinned footer. The fill:false + footer combination had no in-app caller, so
/// guard it (and its siblings) against a layout regression — the footer sits
/// after a Flexible scroll body, which is exactly the kind of arrangement that
/// can throw if the constraints are wrong.
void main() {
  Widget host({required bool fill, Widget? footer}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: SheetScaffold(
              title: 'Test',
              fill: fill,
              footer: footer,
              body: fill
                  ? ListView(children: const [Text('body')])
                  : const Text('body'),
            ),
          ),
        ),
      );

  testWidgets(
    'fill:false with a footer lays out (content-sized, footer pinned)',
    (tester) async {
      await tester.pumpWidget(
        host(
          fill: false,
          footer: FilledButton(onPressed: () {}, child: const Text('Action')),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('body'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
    },
  );

  testWidgets('fill:true with a footer lays out (body fills, footer pinned)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        fill: true,
        footer: FilledButton(onPressed: () {}, child: const Text('Action')),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Action'), findsOneWidget);
  });
}
