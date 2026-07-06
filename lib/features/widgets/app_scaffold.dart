import 'package:flutter/material.dart';

/// A Scaffold with a fixed (standard-height) Material 3 app bar over a body
/// that fills the screen. Pass a plain widget as [body] — a scroll view
/// (`ListView`/`SingleChildScrollView`) for long content, or a centered
/// placeholder for short content. The app bar picks up its scroll-under
/// elevation from the theme.
///
/// Used by the main screens so the app bar is consistent app-wide.
class AppScaffold extends StatelessWidget {
  final String title;

  /// Optional custom title widget (e.g. the brand wordmark) shown instead of
  /// `Text(title)`.
  final Widget? titleWidget;

  /// Optional small line shown under [title] (e.g. the entity type).
  final String? subtitle;

  final List<Widget> actions;
  final Widget body;
  final Future<void> Function()? onRefresh;
  final Widget? floatingActionButton;

  /// Optional widget pinned over the bottom of the body (e.g. a Create button
  /// that the list scrolls behind). Callers add their own bottom padding so
  /// content stays reachable above it.
  final Widget? bottomOverlay;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.titleWidget,
    this.subtitle,
    this.actions = const [],
    this.onRefresh,
    this.floatingActionButton,
    this.bottomOverlay,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = body;
    if (onRefresh != null) {
      content = RefreshIndicator(onRefresh: onRefresh!, child: content);
    }
    return Scaffold(
      appBar: AppBar(
        title: titleWidget ??
            (subtitle == null
                ? Text(title)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  )),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      // AppBar owns the top inset, so the body only needs the bottom safe area.
      body: SafeArea(
        top: false,
        child: bottomOverlay == null
            ? content
            : Stack(
                children: [
                  Positioned.fill(child: content),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: bottomOverlay!,
                  ),
                ],
              ),
      ),
    );
  }
}
