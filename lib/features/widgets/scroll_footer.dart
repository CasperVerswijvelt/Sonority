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
    // a LayoutBuilder (CardGrid on wide layouts), and anything that queries
    // intrinsic dimensions on a LayoutBuilder throws. Content goes under a
    // SliverToBoxAdapter (plain box layout, no intrinsic query); only the footer
    // — always a simple button/text — sits under SliverFillRemaining, which
    // does query intrinsics but only ever sees the footer.
    return CustomScrollView(
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
        SliverPadding(
          padding: padding.copyWith(top: 0),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
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
