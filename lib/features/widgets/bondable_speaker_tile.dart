import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';

/// A selectable speaker row used by the "pick speakers" lists (dedicated-fronts
/// and stereo-pair flows).
///
/// When the speaker is [SonosDevice.reachable] == false we couldn't read its
/// device_description.xml: it's shown (it exists in the topology) but disabled,
/// with a warning icon + subtitle, since we can't safely bond a player whose
/// model/capabilities we don't know.
///
/// Disabled, but drawn with its TRUE [selected] value. An unreachable speaker
/// is routinely already bonded — both the group edit flow and the HT configure
/// flow merge a bond's own members back into the picker — and drawing one of
/// those unticked claimed it was out of the bond while saving would have
/// re-asserted it right back in. Dropping such a speaker is done by dissolving
/// the bond, not by unticking it here.
class BondableSpeakerTile extends StatelessWidget {
  final SonosDevice device;
  final bool selected;

  /// Selection handler; pass null to disable (e.g. the two-speaker cap is hit).
  /// Ignored entirely when the device is unreachable.
  final ValueChanged<bool?>? onChanged;

  /// Normal subtitle (model name, or an Amp note). Replaced by the warning
  /// text when the device is unreachable.
  final String subtitle;

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
    required this.subtitle,
    this.secondary,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget tile = !device.reachable
        ? CheckboxListTile(
            value: selected,
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
            title: Text(device.roomName),
            subtitle: Text(subtitle),
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
