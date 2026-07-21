import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Lays [cards] out responsively: a single stretched column on a phone-width
/// window, a multi-column grid once the window reaches [kWideLayoutBreakpoint]
/// (the same breakpoint that swaps the bottom bar for the nav rail). Shared by
/// the System overview, Profiles, and the group / home-theater detail + setup
/// screens so every "grid of cards" behaves the same on desktop.
///
/// [runSpacing] is the vertical gap between rows (and between stacked cards when
/// narrow). Pass `0` when the cards already carry their own bottom margin (the
/// overview's entity cards do).
class CardGrid extends StatelessWidget {
  final List<Widget> cards;
  final double runSpacing;

  /// Target minimum column width — the grid fits as many columns as this allows
  /// (2–3), so cards never get narrower than roughly this.
  final double minColumnWidth;

  const CardGrid(
    this.cards, {
    super.key,
    this.runSpacing = kCardGap,
    this.minColumnWidth = 360,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    if (MediaQuery.sizeOf(context).width < kWideLayoutBreakpoint) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(height: runSpacing),
            cards[i],
          ],
        ],
      );
    }
    // Column count keys off the ACTUAL available width (LayoutBuilder), not the
    // window — so a card list inside a clamped wizard still picks a sane count.
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minColumnWidth).floor().clamp(2, 3);
        final w = (c.maxWidth - (cols - 1) * kCardGap) / cols;
        return Wrap(
          spacing: kCardGap,
          runSpacing: runSpacing,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }
}
