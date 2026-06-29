import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/sonos/apply_progress.dart';

/// Renders the live [ApplyStep] list of a multi-step bonding operation so the
/// user sees which step is active, which finished, and — on failure — exactly
/// where and why it stopped. Used by the HT setup flow and profile-apply.
class ApplyProgressView extends StatelessWidget {
  final List<ApplyStep> steps;
  final String title;

  const ApplyProgressView({
    super.key,
    required this.steps,
    this.title = 'Setting up your home theater…',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = steps.any((s) => s.isFailed);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          Gap.s,
          Text(
            failed
                ? 'Something went wrong — see the step below.'
                : 'Bonding can take ~15–20s per step while Sonos applies and '
                    're-reads the layout.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          Gap.l,
          ...steps.map((s) => _StepRow(step: s)),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final ApplyStep step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Widget leading, Color color) = switch (step.status) {
      ApplyStatus.pending => (
          Icon(Icons.circle_outlined, color: scheme.onSurfaceVariant, size: 22),
          scheme.onSurfaceVariant,
        ),
      ApplyStatus.active => (
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          scheme.primary,
        ),
      ApplyStatus.done => (
          Icon(Icons.check_circle, color: scheme.primary, size: 22),
          scheme.onSurface,
        ),
      ApplyStatus.failed => (
          Icon(Icons.error, color: scheme.error, size: 22),
          scheme.error,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          Gap.m,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: color,
                      fontWeight: step.status == ApplyStatus.active
                          ? FontWeight.w600
                          : FontWeight.normal,
                    )),
                if (step.detail != null)
                  Text(step.detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: step.isFailed
                              ? scheme.error
                              : scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
