import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import 'bondable_speaker_tile.dart';

/// The in-card Left/Right toggle for a two-speaker pair (home-theater fronts /
/// surrounds, and a stereo group). There are only two speakers, so choosing the
/// opposite side swaps the pair — [onSwap] fires whenever the shown side is
/// toggled, and both cards re-derive their side from the new order. Meant to
/// live in a [SelectableSpeakerCard.control] slot, shown once both are chosen.
class SideSelector extends StatelessWidget {
  final bool isRight;
  final VoidCallback onSwap;
  const SideSelector({super.key, required this.isRight, required this.onSwap});

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: false, label: Text(context.l10n.groupChannelLeft)),
      ButtonSegment(value: true, label: Text(context.l10n.groupChannelRight)),
    ],
    selected: {isRight},
    onSelectionChanged: (s) {
      if (s.first != isRight) onSwap();
    },
  );
}

/// A selectable speaker in the setup flows: an outlined card wrapping the
/// [BondableSpeakerTile] checkbox row, with an optional [control] (a channel
/// selector — L/R for home-theater fronts/surrounds, L/Both/R for a custom
/// group) that animates into view beneath the row once the speaker is selected.
/// Shared by the group and home-theater flows so the picker looks identical.
class SelectableSpeakerCard extends StatelessWidget {
  final SonosDevice device;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;
  final String? subtitle;
  final Widget? identify;

  /// The in-card channel selector to reveal when [showControl]. Kept null when
  /// this speaker has no side to assign (unselected, or an Amp on both fronts).
  final Widget? control;
  final bool showControl;

  const SelectableSpeakerCard({
    super.key,
    required this.device,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
    this.subtitle,
    this.identify,
    this.control,
    this.showControl = false,
  });

  @override
  Widget build(BuildContext context) {
    // Card margin comes from the theme (zero) — the CardGrid / caller owns the
    // spacing between cards.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BondableSpeakerTile(
            device: device,
            selected: selected,
            onChanged: enabled ? (_) => onToggle() : null,
            subtitle: subtitle ?? device.typeLabel,
            secondary: identify,
          ),
          // CrossFade (not just AnimatedSize) so the control fades out WHILE the
          // height collapses on deselect, instead of vanishing instantly.
          AnimatedCrossFade(
            duration: kShortAnim,
            sizeCurve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            crossFadeState: showControl && control != null
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: control ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
