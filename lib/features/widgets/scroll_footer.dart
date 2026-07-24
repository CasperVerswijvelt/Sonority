import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A scroll view whose [footer] sits at the bottom of the viewport when the
/// content is short, and scrolls to the end when the content overflows — so a
/// commit/destructive action (Separate) is always at the bottom without being
/// pinned over scrollable content. Children carry their own horizontal padding;
/// [padding] adds the outer vertical/edge insets.
class ScrollFooter extends StatelessWidget {
  final List<Widget> children;
  final Widget footer;
  final EdgeInsets padding;

  const ScrollFooter({
    super.key,
    required this.children,
    required this.footer,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    // Two slivers: the content scrolls normally, and the footer takes whatever
    // viewport is left (floated to the bottom when content is short, scrolling
    // after it when content is tall).
    //
    // Why the split instead of one IntrinsicHeight/Spacer column: a child can be
    // a LayoutBuilder (CardGrid on wide layouts), and querying intrinsic
    // dimensions on a LayoutBuilder throws. Content goes under a plain
    // SliverToBoxAdapter (box layout, no intrinsic query).
    return CustomScrollView(
      // Always overscrollable so a wrapping RefreshIndicator's pull-to-refresh
      // fires even when the content is shorter than the viewport (the footer's
      // min-height makes short content fill the viewport exactly).
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: padding.copyWith(bottom: 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
        // NOT SliverFillRemaining: it sizes its child via getMaxIntrinsicHeight,
        // and a ListTile/SwitchListTile mis-reports its intrinsic height when its
        // subtitle wraps (it ignores the wrap), so the footer gets a too-short
        // tight box and overflows by the wrapped lines instead of scrolling.
        // Instead measure the leftover viewport ourselves and lay the footer out
        // as a real box: a min-height of the leftover floats it to the bottom when
        // content is short; when the footer is taller than the leftover it takes
        // its true (wrapped) height and the view scrolls. Padding lives inside so
        // short content totals exactly one viewport (no spurious overscroll).
        SliverLayoutBuilder(
          builder: (context, sc) {
            final leftover = math.max(
              0.0,
              sc.viewportMainAxisExtent - sc.precedingScrollExtent,
            );
            return SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: leftover),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: sc.crossAxisExtent,
                    child: Padding(
                      padding: padding.copyWith(top: 0),
                      child: footer,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
