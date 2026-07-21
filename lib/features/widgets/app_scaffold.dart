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
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ScrolledUnderDivider(),
        ),
        title:
            titleWidget ??
            (subtitle == null
                ? Text(title)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  )),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      // AppBar owns the top inset, so the body only needs the bottom safe area.
      // Content fills the full width (the desktop window is capped instead of
      // centering the content — see MainFlutterWindow.swift).
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

/// A 1px hairline for an [AppBar.bottom] that fades in only while content is
/// scrolled under the app bar — the flat, line-based equivalent of the M3
/// scroll-under shadow. Mirrors [AppBar]'s own detection
/// ([ScrollNotificationObserver] + `metrics.extentBefore`), so its timing
/// matches the shadow it replaces. Constant height ⇒ no layout jump; only the
/// colour animates.
class ScrolledUnderDivider extends StatefulWidget {
  const ScrolledUnderDivider({super.key});

  @override
  State<ScrolledUnderDivider> createState() => _ScrolledUnderDividerState();
}

class _ScrolledUnderDividerState extends State<ScrolledUnderDivider> {
  ScrollNotificationObserverState? _observer;
  bool _under = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    _observer = null;
    super.dispose();
  }

  void _onScroll(ScrollNotification notification) {
    if (!defaultScrollNotificationPredicate(notification)) return;
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollMetricsNotification) {
      return;
    }
    if (notification.metrics.axis != Axis.vertical) return;
    final under = notification.metrics.extentBefore > 0;
    if (under != _under) setState(() => _under = under);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 1,
      color: _under
          ? Theme.of(context).colorScheme.outlineVariant
          : Colors.transparent,
    );
  }
}
