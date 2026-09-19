import 'package:flutter/material.dart';

/// A [FilledButton] whose enable/disable is a fade rather than a snap.
///
/// Flutter animates *some* of that transition already — the Material's
/// background and the label's text style — but an icon takes its colour from
/// `IconTheme`, which is not animated, so the icon jumps while everything
/// around it fades. Rather than animate the odd one out, this drives every
/// colour from one tween and hands the button the same value for its enabled
/// and disabled states, so nothing is left to Material's own switch.
class FadingFilledButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;

  /// Defaults to the filled-button pair (`primary` on `onPrimary`).
  final Color? background;
  final Color? foreground;

  static const _duration = Duration(milliseconds: 200);

  const FadingFilledButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = onPressed != null;
    final enabledBg = background ?? scheme.primary;
    final enabledFg = foreground ?? scheme.onPrimary;
    // The Material 3 disabled pair, which is what the button would resolve to
    // on its own.
    final disabledBg = scheme.onSurface.withValues(alpha: 0.12);
    final disabledFg = scheme.onSurface.withValues(alpha: 0.38);

    return TweenAnimationBuilder<double>(
      duration: _duration,
      curve: Curves.easeOut,
      tween: Tween(end: on ? 1 : 0),
      builder: (context, t, child) {
        final bg = Color.lerp(disabledBg, enabledBg, t)!;
        final fg = Color.lerp(disabledFg, enabledFg, t)!;
        return FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            disabledBackgroundColor: bg,
            foregroundColor: fg,
            disabledForegroundColor: fg,
          ),
          child: child!,
        );
      },
      child: child,
    );
  }
}
