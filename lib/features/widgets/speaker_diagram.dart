import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

/// A simple top-down room diagram showing the soundbar and the currently
/// assigned channels around it. Purely illustrative — communicates layout at a
/// glance rather than the dense settings lists of other tools.
class SpeakerDiagram extends StatelessWidget {
  final String? frontLeftLabel;
  final String? frontRightLabel;
  final String? rearLeftLabel;
  final String? rearRightLabel;

  /// Number of bonded Subs (0, 1, or 2 for a dual-sub HT). Renders "SUB" or
  /// "SUB ×N".
  final int subCount;

  /// The soundbar's type (e.g. "Beam", "Arc") shown under the screen bar.
  /// Falls back to a generic label when unknown.
  final String? soundbarLabel;

  const SpeakerDiagram({
    super.key,
    this.frontLeftLabel,
    this.frontRightLabel,
    this.rearLeftLabel,
    this.rearRightLabel,
    this.subCount = 0,
    this.soundbarLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1.3,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Screen + soundbar
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Text(soundbarLabel ?? context.l10n.widgetsTvSoundbar,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _dot(context, 'L', frontLeftLabel, scheme.primary),
                  _dot(context, 'R', frontRightLabel, scheme.primary),
                ],
              ),
            ),
            if (subCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _chip(context, subCount > 1 ? 'SUB ×$subCount' : 'SUB',
                    scheme.tertiary),
              ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _dot(context, 'LS', rearLeftLabel, scheme.secondary),
                  Icon(Icons.weekend_outlined,
                      color: scheme.onSurfaceVariant, size: 28),
                  _dot(context, 'RS', rearRightLabel, scheme.secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(BuildContext context, String pos, String? label, Color color) {
    final scheme = Theme.of(context).colorScheme;
    final active = label != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : scheme.surfaceContainerHighest,
            border: Border.all(
              color: active ? color : scheme.outlineVariant,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(pos,
              style: TextStyle(
                color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              )),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            label ?? '—',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}
