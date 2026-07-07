import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/core/theme.dart';
import 'package:sonority/features/widgets/app_scaffold.dart';

void main() {
  Color dividerColor(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(ScrolledUnderDivider),
        matching: find.byType(Container),
      ),
    );
    return container.color ?? (container.decoration as BoxDecoration).color!;
  }

  testWidgets('app-bar hairline is transparent at rest, outlineVariant on scroll',
      (tester) async {
    final theme = AppTheme.light();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: AppScaffold(
        title: 'Test',
        body: ListView(
          children:
              List.generate(50, (i) => SizedBox(height: 80, child: Text('$i'))),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(dividerColor(tester), Colors.transparent);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(dividerColor(tester), theme.colorScheme.outlineVariant);
  });
}
