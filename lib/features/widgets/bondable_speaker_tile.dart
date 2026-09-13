import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';

/// A selectable speaker row used by the "pick speakers" lists (dedicated-fronts
/// and stereo-pair flows).
///
/// When the speaker is [SonosDevice.reachable] == false we couldn't read its
/// device_description.xml: it's still shown (it exists in the topology) but
/// disabled, with a warning icon + subtitle, since we can't safely bond a
/// player whose model/capabilities we don't know.
class BondableSpeakerTile extends StatelessWidget {
  final SonosDevice device;
  final bool selected;

  /// Selection handler; pass null to disable (e.g. the two-speaker cap is hit).
  /// Ignored entirely when the device is unreachable.
  final ValueChanged<bool?>? onChanged;

  /// Normal subtitle (model name, or an Amp note). Replaced by the warning text
  /// when the device is unreachable, and omitted entirely when null — which is
  /// what a card titled by [titleOverride] does, since its title is already the
  /// speaker type and repeating it below would say the same thing twice.
  final String? subtitle;

  /// Replaces [SonosDevice.roomName] as the title — see
  /// [SelectableSpeakerCard.titleOverride].
  final String? titleOverride;

  /// Trailing controls (identify buttons). Hidden when unreachable.
  final Widget? secondary;

  /// Wrap the row in an outlined [Card] so each selectable speaker reads as its
  /// own tappable panel (used by the pick-speakers lists).
  final bool outlined;

  const BondableSpeakerTile({
    super.key,
    required this.device,
    required this.selected,
    required this.onChanged,
    this.subtitle,
    this.titleOverride,
    this.secondary,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget tile = !device.reachable
        ? CheckboxListTile(
            value: false,
            onChanged: null,
            title: Text(device.roomName),
            subtitle: Text(
              context.l10n.widgetsUnreachableSpeakerHint,
              style: TextStyle(color: scheme.error),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Icon(Icons.warning_amber_rounded, color: scheme.error),
          )
        : CheckboxListTile(
            value: selected,
            onChanged: onChanged,
            title: Text(titleOverride ?? device.roomName),
            subtitle: subtitle == null ? null : Text(subtitle!),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: secondary,
          );
    if (!outlined) return tile;
    return Card(
      margin: const EdgeInsets.only(bottom: kCardGap),
      clipBehavior: Clip.antiAlias,
      child: tile,
    );
  }
}
