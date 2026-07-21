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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Clamp: a viewport shorter than the padding (or an unbounded parent)
        // must not yield a negative/infinite minHeight (BoxConstraints asserts).
        final minHeight =
            (constraints.maxHeight - padding.vertical).clamp(0.0, double.infinity);
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            // IntrinsicHeight lets the Spacer push the footer to the viewport
            // bottom when content is short, while the column still grows past
            // the viewport (and scrolls) when it's tall. Fine here — the
            // children are fixed-size cards/text, not nested scrollables.
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...children, const Spacer(), footer],
              ),
            ),
          ),
        );
      },
    );
  }
}
