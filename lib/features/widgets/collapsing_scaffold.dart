import 'package:flutter/material.dart';

/// A Scaffold with a fixed (standard-height) Material 3 app bar over a sliver
/// scroll body. Callers pass their content as slivers (wrap plain widgets in
/// `SliverList`/`SliverToBoxAdapter`). The app bar picks up its scroll-under
/// elevation from the theme.
///
/// Used by the main scrollable screens so the app bar is consistent app-wide.
class CollapsingScaffold extends StatelessWidget {
  final String title;

  /// Optional custom title widget (e.g. the brand wordmark) shown instead of
  /// `Text(title)`.
  final Widget? titleWidget;

  final List<Widget> actions;
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final Widget? floatingActionButton;

  /// Optional widget pinned over the bottom of the scroll area (e.g. a Create
  /// button that the list scrolls behind). Callers must add their own bottom
  /// padding sliver so content stays reachable above it.
  final Widget? bottomOverlay;

  const CollapsingScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.titleWidget,
    this.actions = const [],
    this.onRefresh,
    this.floatingActionButton,
    this.bottomOverlay,
  });

  @override
  Widget build(BuildContext context) {
    Widget scroll = CustomScrollView(slivers: slivers);
    if (onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: onRefresh!, child: scroll);
    }
    return Scaffold(
      appBar: AppBar(
        title: titleWidget ?? Text(title),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      // AppBar owns the top inset, so the body only needs the bottom safe area.
      body: SafeArea(
        top: false,
        child: bottomOverlay == null
            ? scroll
            : Stack(
                children: [
                  Positioned.fill(child: scroll),
                  Positioned(left: 0, right: 0, bottom: 0, child: bottomOverlay!),
                ],
              ),
      ),
    );
  }
}
