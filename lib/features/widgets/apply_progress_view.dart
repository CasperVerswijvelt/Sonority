import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/sonos/apply_progress.dart';

/// Renders the live [ApplyStep] list of a multi-step bonding operation as a
/// minimal vertical timeline: a bare checkmark for done steps, a colored
/// pulsing dot for the active step, a grey dot for to-do steps, and a thin
/// connector between them. The active step shows live what it's doing
/// (clearing, re-asserting, attempt N…); a failed step shows the error.
///
/// (This is deliberately NOT a Material [Stepper] — the bonding progress wants
/// the lighter dot/checkmark look. The setup wizards keep their numbered
/// `Stepper`.)
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
            child: Column(
              children: [
                for (var i = 0; i < steps.length; i++)
                  _TimelineRow(step: steps[i], isLast: i == steps.length - 1),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One node + its connector + label/detail.
class _TimelineRow extends StatelessWidget {
  final ApplyStep step;
  final bool isLast;
  const _TimelineRow({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = step.status == ApplyStatus.active;

    final labelColor = switch (step.status) {
      ApplyStatus.failed => scheme.error,
      ApplyStatus.pending => scheme.onSurfaceVariant,
      _ => scheme.onSurface,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Node + connector line column.
          SizedBox(
            width: 24,
            child: Column(
              children: [
                SizedBox(height: 24, child: Center(child: _Node(step: step))),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: scheme.outlineVariant),
                    ),
                  ),
              ],
            ),
          ),
          Gap.m,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 24,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        step.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: labelColor,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  if (step.isFailed)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(step.detail ?? 'Failed.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.error)),
                    )
                  else if (active)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          Gap.s,
                          Expanded(
                            child: Text(step.detail ?? 'Working…',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The timeline node: bare checkmark (done), pulsing dot (active), grey dot
/// (to-do), or a red dot (failed).
class _Node extends StatelessWidget {
  final ApplyStep step;
  const _Node({required this.step});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (step.status) {
      ApplyStatus.done => Icon(Icons.check, size: 18, color: scheme.primary),
      ApplyStatus.active => const _PulsingDot(),
      ApplyStatus.failed => Icon(Icons.close, size: 16, color: scheme.error),
      ApplyStatus.pending => _dot(scheme.onSurfaceVariant.withValues(alpha: 0.5)),
    };
  }

  static Widget _dot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

/// A softly pulsating dot marking the active step.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    // Fixed size; pulse opacity only.
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
