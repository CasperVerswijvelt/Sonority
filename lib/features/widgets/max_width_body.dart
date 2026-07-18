import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Clamps [child] to a readable [maxWidth] and centers it once the available
/// width reaches the wide-layout breakpoint — so single-column pages don't
/// stretch edge-to-edge on a desktop window. Below the breakpoint (phones) the
/// child is returned untouched, so mobile layout is unchanged.
class MaxWidthBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const MaxWidthBody({super.key, required this.child, this.maxWidth = kContentMaxWidth});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kWideLayoutBreakpoint) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}
