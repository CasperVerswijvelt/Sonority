import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Column count + cell width for a responsive card grid, given the content
/// [width] already available to the grid (the caller subtracts its own
/// padding). Shared by [CardGrid] and `ReorderableCardGrid` so the two can't
/// drift. cellWidth is floored to avoid fractional-pixel wrap overflow.
({int columns, double cellWidth}) gridColumns(
  double width, {
  double minColumnWidth = 360,
  int maxColumns = 3,
  double spacing = kCardGap,
}) {
  final columns = (width / minColumnWidth).floor().clamp(1, maxColumns);
  final cellWidth = columns <= 1
      ? width
      : ((width - (columns - 1) * spacing) / columns).floorToDouble();
  return (columns: columns, cellWidth: cellWidth);
}

/// Lays [cards] out responsively: a single stretched column when the available
/// width only fits one, a multi-column grid (2–3) once it genuinely fits more.
/// Shared by the System overview, Profiles, and the group / home-theater detail
/// + setup screens so every "grid of cards" behaves the same on desktop.
///
/// [runSpacing] is the vertical gap between rows (and between stacked cards when
/// single-column). Pass `0` when the cards already carry their own bottom margin
/// (the overview's entity cards do).
class CardGrid extends StatelessWidget {
  final List<Widget> cards;
  final double runSpacing;

  /// Target minimum column width — the grid fits as many columns as this allows
  /// (up to 3), so cards never get narrower than roughly this.
  final double minColumnWidth;

  const CardGrid(
    this.cards, {
    super.key,
    this.runSpacing = kCardGap,
    this.minColumnWidth = 360,
  });

  Widget _column() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) SizedBox(height: runSpacing),
        cards[i],
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    // Below the wide breakpoint (phones) it's always one column.
    if (MediaQuery.sizeOf(context).width < kWideLayoutBreakpoint) {
      return _column();
    }
    // On a wide window, key the column count off the ACTUAL available width
    // (LayoutBuilder), not the window — a card list inside a clamped wizard, or a
    // wide window whose nav rail leaves a narrow content area, still picks a sane
    // count. Floor to 1 (not 2): forcing two columns into a too-narrow area
    // squeezes cards below [minColumnWidth] and overflows their chip rows. One
    // full-width column is the right answer there; 2–3 columns only once the
    // width genuinely fits them.
    return LayoutBuilder(
      builder: (context, c) {
        final (columns: cols, cellWidth: w) =
            gridColumns(c.maxWidth, minColumnWidth: minColumnWidth);
        if (cols == 1) return _column();
        return Wrap(
          spacing: kCardGap,
          runSpacing: runSpacing,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }
}
