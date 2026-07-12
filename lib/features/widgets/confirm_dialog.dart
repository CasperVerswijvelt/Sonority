import 'package:flutter/material.dart';

/// Shared yes/no confirmation dialog. Returns true only if the user taps the
/// confirm action (false on cancel or dismiss). [destructive] tints the confirm
/// label with the error color; both actions are `TextButton`s so they stay
/// horizontal (the theme stretches `FilledButton` to full width, forcing a
/// stack). Replaces the six hand-rolled confirm dialogs across the features.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData? icon,
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: icon == null ? null : Icon(icon),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
