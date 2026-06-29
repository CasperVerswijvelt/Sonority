import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/sonos/apply_progress.dart';

/// Renders the live [ApplyStep] list of a multi-step bonding operation as a
/// vertical timeline (the same `Stepper` look as the HT setup flow): each step
/// is a bullet; the active step is expanded and shows live what it's doing
/// (clearing, re-asserting, attempt N…). On failure the failing step shows the
/// error. Used by the HT setup flow and profile-apply.
class ApplyProgressView extends StatelessWidget {
  final List<ApplyStep> steps;

  const ApplyProgressView({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (steps.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final failed = steps.any((s) => s.isFailed);

    final activeIndex = steps.indexWhere((s) => s.status == ApplyStatus.active);
    final failedIndex = steps.indexWhere((s) => s.isFailed);
    final lastDone = steps.lastIndexWhere((s) => s.status == ApplyStatus.done);
    final current = (activeIndex >= 0
            ? activeIndex
            : failedIndex >= 0
                ? failedIndex
                : (lastDone >= 0 ? lastDone : 0))
        .clamp(0, steps.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            failed
                ? 'Something went wrong — see the step below.'
                : 'Bonding can take ~15–20s per step while Sonos applies and '
                    're-reads the layout.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Stepper(
              currentStep: current,
              physics: const NeverScrollableScrollPhysics(),
              controlsBuilder: (_, __) => const SizedBox.shrink(),
              steps: [
                for (final s in steps)
                  Step(
                    title: Text(s.label),
                    state: switch (s.status) {
                      ApplyStatus.done => StepState.complete,
                      ApplyStatus.failed => StepState.error,
                      _ => StepState.indexed,
                    },
                    isActive: s.status == ApplyStatus.active ||
                        s.status == ApplyStatus.done,
                    content: _StepContent(step: s),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The expanded body shown under the active (or failed) step — its live detail.
class _StepContent extends StatelessWidget {
  final ApplyStep step;
  const _StepContent({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (step.isFailed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(step.detail ?? 'Failed.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
      );
    }
    if (step.status == ApplyStatus.active) {
      return Row(
        children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          Gap.m,
          Expanded(
            child: Text(step.detail ?? 'Working…',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      );
    }
    // Pending/done steps stay collapsed — no body needed.
    return const SizedBox.shrink();
  }
}
