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

  /// The op was aborted by the user. The aborted step still renders red (with
  /// its "Aborted" reason), but the header stays neutral — an abort isn't a
  /// "something went wrong".
  final bool aborted;

  const ApplyProgressView({super.key, required this.steps, this.aborted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (steps.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final failed = steps.any((s) => s.isFailed) && !aborted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: Text(
            failed
                ? 'Something went wrong — see the step below.'
                : 'Bonding can take ~15–20s per step while Sonos applies and '
                    're-reads the layout.',
            style: theme.mutedText,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.fromLTRB(kPageGutter, 28, kPageGutter, 16),
            child: Column(
              children: [
                for (var i = 0; i < steps.length; i++)
                  _TimelineRow(
                    step: steps[i],
                    isLast: i == steps.length - 1,
                    // Extra gap before the next entity groups its section.
                    nextIsParent:
                        i + 1 < steps.length && !steps[i + 1].isChild,
                    hasChildren: !steps[i].isChild &&
                        steps.any((s) => s.parentId == steps[i].id),
                    hasFailedChild: !steps[i].isChild &&
                        steps.any(
                            (s) => s.parentId == steps[i].id && s.isFailed),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One node + its connector + label/detail on a single shared spine: big
/// nodes (checkmark when done) for top-level entity steps, small plain dots
/// for phase sub-steps (blue while busy, green when done, red on failure).
/// A parent that has children shows label + node only (the verbose/error
/// text lives on its sub-steps).
class _TimelineRow extends StatelessWidget {
  final ApplyStep step;
  final bool isLast;
  final bool nextIsParent;
  final bool hasChildren;
  final bool hasFailedChild;
  const _TimelineRow(
      {required this.step,
      required this.isLast,
      required this.nextIsParent,
      required this.hasChildren,
      required this.hasFailedChild});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = step.status == ApplyStatus.active;
    final child = step.isChild;

    final labelColor = switch (step.status) {
      ApplyStatus.failed => scheme.error,
      ApplyStatus.pending || ApplyStatus.skipped => scheme.onSurfaceVariant,
      _ => scheme.onSurface,
    };

    // The connector stretches through the bottom padding, so a bigger gap
    // before the next entity visually groups each section.
    final gapAfter = isLast ? 0.0 : (nextIsParent ? 22.0 : 10.0);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Node + connector line column — one spine shared by all rows.
          SizedBox(
            width: 24,
            child: Column(
              children: [
                SizedBox(
                    height: 24,
                    child: Center(child: _Node(step: step, small: child))),
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
              padding: EdgeInsets.only(bottom: gapAfter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 24,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        step.label,
                        style: (child
                                ? theme.textTheme.bodyMedium?.copyWith(
                                    color: labelColor,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  )
                                : theme.textTheme.titleMedium?.copyWith(
                                    color: labelColor,
                                    fontWeight: FontWeight.w600,
                                  )),
                      ),
                    ),
                  ),
                  // Show the reason on the step itself unless a child already
                  // carries it (a mid-phase failure lives on the failing
                  // sub-step; an abort before any sub-step started stays here).
                  if (step.isFailed && !hasFailedChild)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(step.detail ?? 'Failed.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.error)),
                    )
                  else if (active && !hasChildren)
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
                    )
                  else if (child &&
                      (step.status == ApplyStatus.done ||
                          step.status == ApplyStatus.skipped) &&
                      step.detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(step.detail!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w300)),
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

/// The timeline node. A main (entity) step is always the SAME fixed-size
/// circle — filled green + check when done, filled red + X when failed, an
/// outlined ring with a pulsing dot while busy, a grey ring when to-do — so
/// milestones read consistently across states. Phase sub-steps ([small]) are
/// plain 6px dots in every state, only the color changes: green done, blue
/// pulsing busy, red failed, grey to-do.
class _Node extends StatelessWidget {
  final ApplyStep step;
  final bool small;
  const _Node({required this.step, this.small = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pendingColor = scheme.onSurfaceVariant.withValues(alpha: 0.5);
    final green = theme.brightness == Brightness.dark
        ? Colors.green.shade400
        : Colors.green.shade600;
    if (small) {
      return switch (step.status) {
        ApplyStatus.done => _dot(green, 6),
        ApplyStatus.active => const _PulsingDot(size: 6),
        ApplyStatus.failed => _dot(scheme.error, 6),
        ApplyStatus.pending || ApplyStatus.skipped => _dot(pendingColor, 6),
      };
    }
    return switch (step.status) {
      ApplyStatus.done => _circle(
          fill: green,
          child: const Icon(Icons.check, size: 14, color: Colors.white)),
      ApplyStatus.failed => _circle(
          fill: scheme.error,
          child: const Icon(Icons.close, size: 14, color: Colors.white)),
      ApplyStatus.active => _circle(
          border: scheme.primary, child: const _PulsingDot(size: 10)),
      ApplyStatus.pending => _circle(border: pendingColor),
      // Skipped only occurs on sub-steps; defensive rendering for parents.
      ApplyStatus.skipped => _circle(
          border: pendingColor,
          child:
              Icon(Icons.remove, size: 14, color: scheme.onSurfaceVariant)),
    };
  }

  static Widget _dot(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  static Widget _circle({Color? fill, Color? border, Widget? child}) =>
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: border == null ? null : Border.all(color: border, width: 2),
        ),
        child: child == null ? null : Center(child: child),
      );
}

/// A softly pulsating dot marking the active step.
class _PulsingDot extends StatefulWidget {
  final double size;
  const _PulsingDot({this.size = 12});

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
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
