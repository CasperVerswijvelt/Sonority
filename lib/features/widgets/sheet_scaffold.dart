import 'package:flutter/material.dart';

import 'app_scaffold.dart' show ScrolledUnderDivider;

/// Caps a sheet's height so it stops one app-bar height below the top of the
/// space available to it — a meaningful, dismiss-friendly strip (you see the app
/// bar of the screen behind) rather than an arbitrary fraction. Measured with a
/// [LayoutBuilder] (the real available height, already minus the safe area /
/// window chrome) rather than `MediaQuery.size`, which on macOS includes the
/// window title bar and overshot. [fill] makes the sheet occupy the whole cap
/// (long scroll views); otherwise it's a max the content grows into.
Widget _capped(Widget child, {required bool fill}) => LayoutBuilder(
      builder: (context, constraints) {
        final max = (constraints.maxHeight - kToolbarHeight - 1)
            .clamp(0.0, constraints.maxHeight);
        return fill
            ? SizedBox(height: max, child: child)
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: max), child: child);
      },
    );

/// A tall modal sheet that FILLS up to the cap — for inherently long, scrollable
/// content (diagnostics, the changelog). Pair with [SheetScaffold]; its [body]
/// should be its own scroll view.
Future<T?> showAppSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // Present over the tab shell's NavigationBar so the sheet is a full modal.
      useRootNavigator: true,
      builder: (_) => _capped(child, fill: true),
    );

/// A modal sheet sized to its CONTENT, capped just below the app bar (scrolls
/// past that) — for detail views (a speaker, a group, a profile entity). Pair
/// with [ContentSheetScaffold]; its `body` is plain (non-scrolling) content.
Future<T?> showContentSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => _capped(child, fill: false),
    );

/// The shared sheet header: optional leading [icon], a [title] (+ optional
/// [subtitle]), an optional [trailing] action, and always an explicit close
/// button on the right.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader(
      {required this.title, this.subtitle, this.icon, this.trailing});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (subtitle != null)
                  Text(subtitle!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// A [showAppSheet] body: header + scroll-under divider + a [body] that fills the
/// rest (its own scroll view), and an optional pinned [footer].
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.icon,
    this.trailing,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    // A modal sheet lives in the overlay and doesn't see the home Scaffold's
    // ScrollNotificationObserver, so provide our own for ScrolledUnderDivider.
    return ScrollNotificationObserver(
      child: Column(
        children: [
          _SheetHeader(
              title: title, subtitle: subtitle, icon: icon, trailing: trailing),
          const ScrolledUnderDivider(),
          Expanded(child: body),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

/// A [showContentSheet] body: the same header + divider, then a content-sized
/// [body] (plain content — wrapped here in a scroll view so it scrolls only once
/// it hits the sheet's height cap), and an optional pinned [footer].
class ContentSheetScaffold extends StatelessWidget {
  const ContentSheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.icon,
    this.trailing,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ScrollNotificationObserver(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(
              title: title, subtitle: subtitle, icon: icon, trailing: trailing),
          const ScrolledUnderDivider(),
          Flexible(child: SingleChildScrollView(child: body)),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
