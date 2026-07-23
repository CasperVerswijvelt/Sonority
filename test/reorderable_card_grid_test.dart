import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/widgets/reorderable_card_grid.dart';

/// The reorder index mapping is the one piece of real logic here: an in-mode
/// drag must call onReorder(from, to) with insert-style indices (from = index in
/// items, to = final index) — exactly what ProfilesController.reorder wants.
void main() {
  Widget host(
    List<String> items,
    void Function(int, int) onReorder, {
    bool reordering = false,
    void Function(String)? onTap,
  }) {
    // Wide enough for 2 columns (default minColumnWidth 360).
    return MaterialApp(
      home: Scaffold(
        body: ReorderableCardGrid<String>(
          items: items,
          idOf: (s) => s,
          reordering: reordering,
          onReorder: onReorder,
          itemBuilder: (context, s) => Card(
            child: InkWell(
              onTap: onTap == null ? null : () => onTap(s),
              child: SizedBox(height: 80, child: Center(child: Text(s))),
            ),
          ),
        ),
      ),
    );
  }

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders every item', (tester) async {
    wide(tester);
    await tester.pumpWidget(host(['a', 'b', 'c', 'd'], (_, __) {}));
    await tester.pumpAndSettle();
    // 'a' also appears in the invisible measurer probe → 2; b/c/d once each.
    expect(find.text('b'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
    expect(find.text('d'), findsOneWidget);
  });

  testWidgets('reorder mode: immediate drag reports insert-style (from, to)',
      (tester) async {
    wide(tester);
    final order = ['a', 'b', 'c', 'd']; // 2 cols: a b / c d
    int? gotFrom, gotTo;
    await tester.pumpWidget(host(order, (f, t) {
      gotFrom = f;
      gotTo = t;
    }, reordering: true));
    await tester.pumpAndSettle(); // let the height measure → grid mode

    // Drag 'd' (index 3) onto 'c' (index 2): same row → a horizontal drag the
    // pan wins outright (no scroll conflict). Non-first items, so the measurer's
    // duplicate of 'a' doesn't make the finder ambiguous. No long-press wait.
    final g = await tester.startGesture(tester.getCenter(find.text('d')));
    await g.moveTo(tester.getCenter(find.text('c')));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(gotFrom, 3);
    expect(gotTo, 2);
    // Applied the way ProfilesController.reorder does:
    order.insert(gotTo!, order.removeAt(gotFrom!));
    expect(order, ['a', 'b', 'd', 'c']);
  });

  testWidgets('not reordering: no drag, card stays interactive', (tester) async {
    wide(tester);
    var reorders = 0;
    String? tapped;
    await tester.pumpWidget(host(
      ['a', 'b', 'c', 'd'],
      (_, __) => reorders++,
      reordering: false,
      onTap: (s) => tapped = s,
    ));
    await tester.pumpAndSettle();

    // A drag does not reorder (no gesture when not in reorder mode).
    final g = await tester.startGesture(tester.getCenter(find.text('d')));
    await g.moveTo(tester.getCenter(find.text('c')));
    await g.up();
    await tester.pumpAndSettle();
    expect(reorders, 0);

    // ...and the card is still tappable.
    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect(tapped, 'b');
  });

  testWidgets('exposes screen-reader reorder actions (accessibility)',
      (tester) async {
    final handle = tester.ensureSemantics();
    wide(tester);
    await tester.pumpWidget(host(['a', 'b', 'c', 'd'], (_, __) {}));
    await tester.pumpAndSettle();

    // Collect every custom-action label present anywhere in the semantics tree.
    final labels = <String>{};
    void visit(SemanticsNode node) {
      for (final id in node.getSemanticsData().customSemanticsActionIds ??
          const <int>[]) {
        final label = CustomSemanticsAction.getAction(id)?.label;
        if (label != null) labels.add(label);
      }
      node.visitChildren((c) {
        visit(c);
        return true;
      });
    }

    visit(tester.getSemantics(find.byType(ReorderableCardGrid<String>)));

    // Same default WidgetsLocalizations labels ReorderableListView uses.
    const ml = DefaultWidgetsLocalizations();
    expect(
      labels,
      containsAll([
        ml.reorderItemToStart,
        ml.reorderItemUp,
        ml.reorderItemDown,
        ml.reorderItemToEnd,
      ]),
    );
    handle.dispose();
  });
}
