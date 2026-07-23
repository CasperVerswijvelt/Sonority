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
    double Function(String)? cardHeight,
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
            key: ValueKey('card-$s'),
            child: InkWell(
              onTap: onTap == null ? null : () => onTap(s),
              child: SizedBox(
                  height: cardHeight?.call(s) ?? 80,
                  child: Center(child: Text(s))),
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

  testWidgets('adopts an in-place edit (same id, new content) while idle',
      (tester) async {
    // Regression: an edit produces a new item with the SAME id in the SAME slot.
    // Comparing order by id alone would keep the stale item and show old content.
    wide(tester);
    // id ($1) is stable; label ($2) is what changes on an "edit".
    Widget grid(List<(String, String)> items) => MaterialApp(
          home: Scaffold(
            body: ReorderableCardGrid<(String, String)>(
              items: items,
              idOf: (it) => it.$1,
              onReorder: (_, __) {},
              itemBuilder: (context, it) =>
                  SizedBox(height: 80, child: Text(it.$2)),
            ),
          ),
        );

    await tester.pumpWidget(grid([('p1', 'Old name'), ('p2', 'Other')]));
    await tester.pumpAndSettle();
    expect(find.text('Old name'), findsOneWidget);

    await tester.pumpWidget(grid([('p1', 'New name'), ('p2', 'Other')]));
    await tester.pumpAndSettle();
    expect(find.text('New name'), findsOneWidget);
    expect(find.text('Old name'), findsNothing);
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

  testWidgets('rows use the tallest card height — cards never overlap',
      (tester) async {
    // Narrow → single column; 'b' is much taller (a long name / wrapped chips
    // would do this in the real card). Naively measuring only the first item
    // would under-space the rows and overlap 'b' onto 'c'.
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      ['a', 'b', 'c'],
      (_, __) {},
      cardHeight: (s) => s == 'b' ? 180 : 70,
    ));
    await tester.pumpAndSettle();

    Rect card(String s) => tester.getRect(find.byKey(ValueKey('card-$s')));
    expect(card('b').top, greaterThanOrEqualTo(card('a').bottom));
    expect(card('c').top, greaterThanOrEqualTo(card('b').bottom));
  });

  // ponytail: no auto-scroll widget test. Edge auto-scroll is Flutter's own
  // EdgeDraggingAutoScroller (ticker-driven); it won't quiesce under the test
  // clock (pumpAndSettle hangs), and the reorder logic worth testing is covered
  // above. Verified by hand on device with a long list.

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
