import 'package:flutter/material.dart';

/// A Scaffold whose app bar is a Material 3 large title that collapses to a
/// regular app bar on scroll (`SliverAppBar.large`). Callers pass their content
/// as slivers (wrap plain widgets in `SliverList`/`SliverToBoxAdapter`).
///
/// Used by the main scrollable screens so the large-title behaviour is
/// consistent app-wide.
class CollapsingScaffold extends StatelessWidget {
  final String title;
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
    this.actions = const [],
    this.onRefresh,
    this.floatingActionButton,
    this.bottomOverlay,
  });

  @override
  Widget build(BuildContext context) {
    Widget scroll = CustomScrollView(
      slivers: [
        SliverAppBar.large(
          pinned: true,
          title: Text(title),
          actions: actions,
        ),
        ...slivers,
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: onRefresh!, child: scroll);
    }
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
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
