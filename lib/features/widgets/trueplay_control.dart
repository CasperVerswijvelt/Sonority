import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/room_calibration.dart';
import '../../state/trueplay_controller.dart';
import 'confirm_dialog.dart';

/// Trueplay (room calibration) status + on/off toggle for a set of speakers.
///
/// Tuning itself is done once in the official Sonos app on iOS (the measurement
/// can't run on Android); this only reads and toggles the stored calibration —
/// which is the part the Sonos app won't expose for unofficial front setups.
///
/// Pass every speaker the toggle should act on: for a home theater that's all
/// bonded members (so the separately-tuned fronts engage too); for a stereo pair
/// both speakers; for a standalone room just the one.
class TrueplayControl extends ConsumerStatefulWidget {
  final List<SonosDevice> devices;

  /// Set when Trueplay can't apply at all (e.g. Amp-driven fronts — Sonos only
  /// tunes native speakers). Shows an explanation instead of a toggle.
  final String? unsupportedReason;

  const TrueplayControl({
    super.key,
    required this.devices,
    this.unsupportedReason,
  });

  @override
  ConsumerState<TrueplayControl> createState() => _TrueplayControlState();
}

class _TrueplayControlState extends ConsumerState<TrueplayControl> {
  @override
  void initState() {
    super.initState();
    if (widget.unsupportedReason == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(trueplayControllerProvider.notifier).load(widget.devices);
        }
      });
    }
  }

  /// Applies the toggle, asking first when switching ON would cost the
  /// speakers that still hold a tuning.
  ///
  /// Only the ON direction asks, and only while the set is short: turning it
  /// off has never been measured as destructive, and making someone confirm
  /// their way out of a state they are already in would be noise.
  Future<void> _set(bool on, bool warn, List<RoomCalibration> tuned) async {
    if (on && warn) {
      final l10n = context.l10n;
      final ok = await confirmDialog(
        context,
        title: l10n.widgetsTrueplayConfirmTitle,
        message: l10n.widgetsTrueplayConfirmBody(tuned.length),
        confirmLabel: l10n.widgetsTrueplayConfirmAction,
        icon: Icons.tune,
      );
      if (!ok || !mounted) return;
    }
    ref.read(trueplayControllerProvider.notifier).setEnabled(widget.devices, on);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reason = widget.unsupportedReason;
    if (reason != null) {
      return _frame(
        context,
        icon: Icons.tune,
        iconColor: scheme.onSurfaceVariant,
        subtitle: reason,
        trailing: null,
        onTap: null,
      );
    }

    final tp = ref.watch(trueplayControllerProvider);
    final withIp = widget.devices.where((d) => d.ip != null).toList();
    final known =
        withIp.map((d) => tp.byUuid[d.uuid]).whereType<RoomCalibration>().toList();
    final busy = widget.devices.any((d) => tp.busy.contains(d.uuid));

    final tuned = known.where((c) => c.available).toList();
    final tunedCount = tuned.length;
    final enabledCount = tuned.where((c) => c.enabled).length;
    // On if ANY bonded speaker has its calibration enabled. An HT whose fronts
    // were never tuned separately can still read/toggle via the members that ARE
    // tuned, instead of getting stuck looking "partially on / 3/5".
    final isOn = enabledCount > 0;

    final l10n = context.l10n;
    final String subtitle;
    if (busy && known.isEmpty) {
      subtitle = l10n.widgetsTrueplayChecking;
    } else if (tunedCount == 0) {
      subtitle = l10n.widgetsTrueplayNotTuned;
    } else if (withIp.length == 1) {
      // Single speaker — the x/y counter adds nothing.
      subtitle = isOn ? l10n.widgetsTrueplayActive : l10n.widgetsTrueplayTunedOff;
    } else {
      // Multi-speaker (HT / pair): always show the active counter, plus tuned
      // coverage when some bonded speakers have no stored tuning at all.
      final parts = <String>[
        l10n.widgetsTrueplayActiveCount(enabledCount, withIp.length)
      ];
      if (tunedCount < withIp.length) {
        parts.add(l10n.widgetsTrueplayTunedCount(tunedCount, withIp.length));
      }
      subtitle = parts.join(' · ');
    }
    // ☠️ Switching a calibration ON while ANY bonded speaker holds no stored
    // tuning clears the tunings that ARE there, unrecoverably (EXP-23: four
    // cells destroyed on an incomplete set; Q19's changed-but-COMPLETE set
    // survived the same write). This is the normal state right after bonding a
    // speaker that was never tuned, which is exactly when a user reaches for
    // this switch.
    //
    // It is NOT blocked. Three reasons, and they outweigh the tidiness of a
    // guard: the measurement is four cells on one household; the MECHANISM is
    // undetermined, so "the write destroyed it" and "it was already dead and
    // the write cleared a stale flag" are indistinguishable and under the
    // second there is nothing to prevent; and users on other hardware sit in
    // this exact state and toggle deliberately. Removing a control on
    // one-household evidence is the wrong trade in an app whose whole point is
    // doing what the official app refuses.
    //
    // What the evidence DOES justify is not letting it happen by accident: the
    // loss is silent and there is no undo, so the enable asks first and names
    // what it will cost. Turning it OFF is never destructive and never asks.
    final incomplete = tunedCount < withIp.length;
    final canToggle = tunedCount > 0 && !busy;
    final warnOnEnable = incomplete && !isOn;
    // Keep the Switch mounted so it never jumps; a fixed-width slot holds the
    // spinner (left of the switch) only while busy, so the layout is stable.
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: busy
              ? const CircularProgressIndicator(strokeWidth: 2)
              : null,
        ),
        const SizedBox(width: 12),
        Switch(
          value: isOn,
          onChanged: canToggle ? (v) => _set(v, warnOnEnable, tuned) : null,
        ),
      ],
    );

    return _frame(
      context,
      icon: Icons.tune,
      iconColor: isOn ? scheme.primary : scheme.onSurfaceVariant,
      subtitle: warnOnEnable
          ? '$subtitle · ${l10n.widgetsTrueplayIncompleteSet}'
          : subtitle,
      trailing: trailing,
      // Tapping anywhere on the row toggles it, same as the switch.
      onTap: canToggle ? () => _set(!isOn, warnOnEnable, tuned) : null,
    );
  }

  // A flat, full-width tile (no card) — it's a setting, so it reads distinctly
  // from the content cards above it (paired with a SettingsSection divider).
  Widget _frame(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String subtitle,
    required Widget? trailing,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: kPageGutter, vertical: 4),
      leading: Icon(icon, color: iconColor),
      title: const Text('Trueplay'),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
