import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sonos_models.dart';
import '../../data/sonos/room_calibration.dart';
import '../../state/trueplay_controller.dart';

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

  /// Compact = a dense tile for lists; otherwise a full card for detail screens.
  final bool compact;

  const TrueplayControl({
    super.key,
    required this.devices,
    this.unsupportedReason,
    this.compact = false,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reason = widget.unsupportedReason;
    if (reason != null) {
      return _frame(
        context,
        icon: Icons.tune,
        iconColor: scheme.onSurfaceVariant,
        title: 'Trueplay',
        subtitle: reason,
        trailing: null,
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

    final String subtitle;
    if (busy && known.isEmpty) {
      subtitle = 'Checking…';
    } else if (tunedCount == 0) {
      subtitle = 'Not tuned — run Trueplay once in the Sonos app (iOS).';
    } else {
      // Always surface the active counter; add tuned coverage when some bonded
      // speakers have no stored tuning at all.
      final parts = <String>['$enabledCount/${withIp.length} active'];
      if (tunedCount < withIp.length) {
        parts.add('$tunedCount/${withIp.length} tuned');
      }
      subtitle = parts.join(' · ');
    }

    final canToggle = tunedCount > 0 && !busy;
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
          onChanged: canToggle
              ? (v) => ref
                  .read(trueplayControllerProvider.notifier)
                  .setEnabled(widget.devices, v)
              : null,
        ),
      ],
    );

    return _frame(
      context,
      icon: Icons.tune,
      iconColor: isOn ? scheme.primary : scheme.onSurfaceVariant,
      title: 'Trueplay',
      subtitle: subtitle,
      trailing: trailing,
    );
  }

  Widget _frame(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget? trailing,
  }) {
    final tile = ListTile(
      contentPadding: widget.compact
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      dense: widget.compact,
      leading: Icon(icon, color: iconColor),
      title: const Text('Trueplay'),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
    if (widget.compact) return tile;
    return Card(child: tile);
  }
}
