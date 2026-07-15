import 'package:flutter/material.dart';

import 'app_scaffold.dart' show ScrolledUnderDivider;

/// Opens [child] as the app's standard tall modal bottom sheet (drag handle,
/// ~92% height, safe-area aware). Pair with [SheetScaffold] for the header +
/// scroll-under divider chrome. Shared by the diagnostics + version/changelog
/// sheets so they present identically.
Future<T?> showAppSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // Present over the tab shell's NavigationBar so the sheet is a full modal.
      useRootNavigator: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: child),
    );

/// A modal-sheet body: a header row (optional leading [icon], [title], optional
/// [trailing]) over a [ScrolledUnderDivider] that fades in as [body] scrolls
/// under it, then the scrollable [body] filling the rest, and an optional
/// pinned [footer]. The [body] should be its own scroll view.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.trailing,
    this.footer,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A modal sheet lives in the overlay and doesn't see the home Scaffold's
    // ScrollNotificationObserver, so provide our own for ScrolledUnderDivider.
    return ScrollNotificationObserver(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const ScrolledUnderDivider(),
          Expanded(child: body),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
