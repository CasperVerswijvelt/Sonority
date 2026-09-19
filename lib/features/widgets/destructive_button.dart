import 'package:flutter/material.dart';

import 'fading_filled_button.dart';

/// A full-width, error-colored filled button for a detail page's destructive
/// action (separate a group, remove all HT extras). Same shape as the primary
/// `FilledButton.icon` actions but in the error color; the caller wires the
/// confirm dialog + `showBondingProgress` so every destructive path looks and
/// behaves the same.
class DestructiveButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const DestructiveButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FadingFilledButton(
        onPressed: onPressed,
        background: scheme.error,
        foreground: scheme.onError,
        // Laid out by hand rather than via `FilledButton.icon`, which would
        // take the icon's colour from a theme that does not animate.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
