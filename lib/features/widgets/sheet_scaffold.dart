import 'package:flutter/material.dart';

import 'app_scaffold.dart' show ScrolledUnderDivider;

/// Opens [child] as the app's standard modal bottom sheet (drag handle, over the
/// tab shell). Pair with [SheetScaffold] for the header + divider + bottom
/// handling. Shared by every app sheet so they present identically.
Future<T?> showSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // Present over the tab shell's NavigationBar so the sheet is a full modal.
      useRootNavigator: true,
      builder: (_) => child,
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

/// The body of an app modal sheet: a header (icon/title/subtitle/trailing +
/// close), a scroll-under divider, the [body], and an optional pinned [footer].
///
/// Height stops one app-bar height below the top of the space available to it —
/// a meaningful, dismiss-friendly strip (you see the app bar of the screen
/// behind) rather than an arbitrary fraction. Measured with a [LayoutBuilder]
/// (the real available height, already minus the safe area / window chrome)
/// because `MediaQuery.size` on macOS includes the window title bar and overshot.
///
/// [fill] = true → the sheet FILLS that cap; [body] must be its own scroll view
/// (long lists: diagnostics, changelog). [fill] = false (default) → the sheet is
/// sized to its CONTENT up to the cap, and [body] is plain content this wraps in
/// a scroll view (detail sheets: speaker, group, profile entity).
///
/// Bottom safe-area + a small breathing gap are handled here, so callers (footer
/// or not) don't hand-roll bottom padding.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.icon,
    this.trailing,
    this.footer,
    this.fill = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget body;
  final Widget? footer;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = (constraints.maxHeight - kToolbarHeight - 1)
            .clamp(0.0, constraints.maxHeight);
        // A modal sheet lives in the overlay and doesn't see the home Scaffold's
        // ScrollNotificationObserver, so provide our own for ScrolledUnderDivider.
        final content = ScrollNotificationObserver(
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              children: [
                _SheetHeader(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    trailing: trailing),
                const ScrolledUnderDivider(),
                if (fill)
                  Expanded(child: body)
                else
                  Flexible(child: SingleChildScrollView(child: body)),
                if (footer != null) footer!,
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
        return fill
            ? SizedBox(height: maxHeight, child: content)
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: content);
      },
    );
  }
}
