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
    // Two slivers: the content scrolls normally, and the footer fills whatever
    // viewport is left (pinned to the bottom when content is short, scrolling
    // after it when content is tall).
    //
    // Why the split instead of one IntrinsicHeight/Spacer column: a child can be
    // a LayoutBuilder (CardGrid on wide layouts), and querying intrinsic
    // dimensions on a LayoutBuilder throws. Content goes under a
    // SliverToBoxAdapter (plain box layout, no intrinsic query); only the footer
    // — always a simple button/text — sits under SliverFillRemaining, whose
    // trial layout only ever measures the footer.
    return CustomScrollView(
      // Always overscrollable so a wrapping RefreshIndicator's pull-to-refresh
      // fires even when the content is shorter than the viewport (the footer's
      // SliverFillRemaining makes short content fill it exactly).
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
        // The footer's padding lives INSIDE the SliverFillRemaining child, not in
        // a wrapping SliverPadding: SliverFillRemaining(hasScrollBody: false) fills
        // the entire remaining viewport extent, so a wrapping SliverPadding would
        // add its bottom inset on top of that and overflow the viewport by ~that
        // padding (a few px of spurious scroll). Padding inside the fill keeps the
        // total exactly one viewport when content fits.
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: padding.copyWith(top: 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [footer],
            ),
          ),
        ),
      ],
    );
  }
}
