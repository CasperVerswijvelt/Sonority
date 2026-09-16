import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/room_calibration.dart';
import '../../state/trueplay_controller.dart';
import 'confirm_dialog.dart';
import 'label_value_row.dart';

/// What one speaker contributes to the aggregate Trueplay counter.
enum TrueplayRowState {
  /// Tuned and switched on — the only state that is audibly doing anything.
  active,

  /// A tuning is stored but switched off. Normal right after a bonding change.
  tunedOff,

  /// No tuning stored. This is the state that makes the set incomplete, and so
  /// the state the enable warning is about.
  notTuned,

  /// Not read: no IP, the speaker never answered discovery, or the read faulted.
  unknown,
}

/// Breaks an aggregate like "5/6 tuned · 0/6 active" down per speaker.
///
/// The counter says how many, never which — and a user looking at a home
/// theater has no way to tell which speaker is the one holding the set short.
/// Pure so the state mapping is testable without a widget.
///
/// Rows are labelled by speaker TYPE, not room name: inside a bonded entity
/// Sonos absorbs the individual name into the entity's, so the type is what
/// identifies it. [label] overrides that per device — a bonded caller passes
/// `bondedCardTitle`, which appends the channel ("One SL · Surround L") so two
/// speakers of the SAME model are told apart. Without it the type alone is the
/// label, which is all a standalone room has and all it needs.
///
/// Every device is kept, including ones with no reading at all — and those are
/// the whole point. A speaker whose calibration could not be read stays in the
/// counter's denominator (which is simply every device passed in) while
/// dropping out of its numerator: that, not omission, is what turns six
/// speakers into "5/6". Before this it had no row, so the missing sixth was
/// unattributable.
///
// ponytail: the channel is the only qualifier threaded in, and it separates
// every shape this renders for bar one — a home theater is one bar, an L/R pair
// of fronts, an L/R pair of surrounds and a sub, all distinct. DUAL SUBS are the
// exception: both hold `SW`, so both rows read "Sub". Numbering them would
// re-encode position, which is the thing this change exists to stop; Identify
// already answers "which physical speaker" and costs nothing to reach.
List<({String label, TrueplayRowState state})> trueplayRows(
  List<SonosDevice> devices,
  Map<String, RoomCalibration> byUuid, {
  String Function(SonosDevice)? label,
}) =>
    [
      for (final d in devices)
        (
          label: label?.call(d) ?? d.typeLabel,
          state: switch (byUuid[d.uuid]) {
            null => TrueplayRowState.unknown,
            final c when c.active => TrueplayRowState.active,
            final c when c.available => TrueplayRowState.tunedOff,
            _ => TrueplayRowState.notTuned,
          },
        ),
    ];

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

  /// How to name a speaker in the per-speaker breakdown; defaults to its type.
  /// A bonded caller passes `bondedCardTitle` so same-model speakers are told
  /// apart by channel — see [trueplayRows]. The widget doesn't reach for the
  /// topology itself: what a speaker is called depends on the bond it sits in,
  /// which only the caller knows.
  final String Function(SonosDevice)? label;

  /// Set when Trueplay can't apply at all (e.g. Amp-driven fronts — Sonos only
  /// tunes native speakers). Shows an explanation instead of a toggle.
  final String? unsupportedReason;

  const TrueplayControl({
    super.key,
    required this.devices,
    this.label,
    this.unsupportedReason,
  });

  @override
  ConsumerState<TrueplayControl> createState() => _TrueplayControlState();
}

class _TrueplayControlState extends ConsumerState<TrueplayControl> {
  /// Whether the first read has finished. The reads are scheduled post-frame,
  /// so without this the first build has nothing loaded and nothing busy, and
  /// would paint "Couldn't read" for a frame before "Checking…" replaces it.
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    if (widget.unsupportedReason == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(trueplayControllerProvider.notifier).load(widget.devices);
        if (mounted) setState(() => _attempted = true);
      });
    }
  }

  /// Applies the toggle, asking first while the bonded set is short.
  ///
  /// BOTH directions ask, for different reasons. Switching ON can destroy the
  /// tunings that are left. Switching OFF is not known to destroy anything, but
  /// the only way back is the ON write, so it is a one-way door — and being
  /// told that afterwards is no use.
  Future<void> _set(bool on, bool warn, List<RoomCalibration> tuned) async {
    if (warn) {
      final l10n = context.l10n;
      final ok = await confirmDialog(
        context,
        title: on
            ? l10n.widgetsTrueplayConfirmTitle
            : l10n.widgetsTrueplayConfirmOffTitle,
        message: on
            ? l10n.widgetsTrueplayConfirmBody(tuned.length)
            : l10n.widgetsTrueplayConfirmOffBody,
        confirmLabel: on
            ? l10n.widgetsTrueplayConfirmAction
            : l10n.widgetsTrueplayConfirmOffAction,
        icon: Icons.tune,
      );
      if (!ok || !mounted) return;
    }
    ref.read(trueplayControllerProvider.notifier).setEnabled(widget.devices, on);
  }

  @override
  void didUpdateWidget(TrueplayControl old) {
    super.didUpdateWidget(old);
    // The HT page's State survives the nested fronts route, so returning from
    // an apply rebuilds this with a DIFFERENT bonded set and no read of its
    // own — the new member would render from whatever the pre-bond cache said
    // (or nothing) until the user pulled to refresh. Re-read on a set change
    // only; an identical list must not re-fetch on every rebuild.
    final before = old.devices.map((d) => d.uuid).toSet();
    final now = widget.devices.map((d) => d.uuid).toSet();
    if (widget.unsupportedReason == null && !setEquals(before, now)) {
      // Post-frame, like `initState` above and for the same reason: `load`
      // marks its targets busy BEFORE its first await, and Riverpod forbids
      // touching provider state during the build phase — `didUpdateWidget` is
      // in it, so calling straight through threw in every debug build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(trueplayControllerProvider.notifier).load(widget.devices);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to report on, and every message below would be about zero
    // speakers — the room page renders this whenever the topology has a member
    // it never resolved to a device, which used to read "Couldn't read
    // Trueplay from these speakers."
    if (widget.devices.isEmpty) return const SizedBox.shrink();

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
    // ONE set drives the counter, the breakdown rows and the warning gate:
    // every speaker passed in. A device with no IP is never read (the
    // controller only fetches `_withIp`), so it lands here exactly like a read
    // that FAILED — in the denominator, out of both numerators, rendered
    // "Couldn't read" and keeping the set incomplete so the destructive-enable
    // warning stays on. Splitting the no-IP case out of the counter while
    // still giving it a row made the two disagree, and let `incomplete` read a
    // set as complete that had a member nobody ever asked — including a
    // fall-through that printed "Tuned · off" for a speaker with no tuning.
    // Whether a null IP is even reachable in production is unknown; treating
    // "we could not ask" as one state makes the question moot.
    final known = widget.devices
        .map((d) => tp.byUuid[d.uuid])
        .whereType<RoomCalibration>()
        .toList();
    final total = widget.devices.length;
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
    if (known.isEmpty && (busy || !_attempted)) {
      subtitle = l10n.widgetsTrueplayChecking;
    } else if (known.isEmpty) {
      // Nothing answered. "Not tuned" would be a claim about speakers we never
      // managed to ask — the same over-reach the breakdown below exists to stop.
      // Plural-keyed on the speakers the message covers — the ones the
      // breakdown lists — because a standalone room passes exactly one.
      subtitle = l10n.widgetsTrueplayUnreadable(total);
    } else if (tunedCount == 0 && known.length == total) {
      // Flat "not tuned" only when EVERY speaker shown answered. With one
      // missing from the reads this would assert a tuning fact about one we
      // never asked — including a speaker with no IP, which is never read yet
      // still gets a row; the counter below says "0/6 tuned" instead, and the
      // breakdown names the one that didn't answer.
      subtitle = l10n.widgetsTrueplayNotTuned;
    } else if (total == 1) {
      // Single speaker — the x/y counter adds nothing.
      subtitle = isOn ? l10n.widgetsTrueplayActive : l10n.widgetsTrueplayTunedOff;
    } else {
      // Multi-speaker (HT / pair): tuned coverage first, then the active
      // counter. The tuned half is dropped only when it would say nothing the
      // active half doesn't — a complete set with something switched on.
      //
      // Tuned BEFORE active, because a stored tuning is the precondition for an
      // active one and the breakdown rows below read the same way ("Tuned ·
      // off"). Leading with the active count put the consequence before its
      // cause: a set with two stored tunings, none switched on, opened with
      // "0/6 active" and read as though nothing were tuned at all. It also puts
      // the tuned count next to the warning, which is about being short one.
      //
      // "0/6 active" alone is the same bug for a COMPLETE set that is switched
      // off: every speaker holds a tuning, the breakdown stays hidden because
      // they all agree, and nothing on screen says the tunings exist.
      final parts = <String>[
        if (tunedCount < total || enabledCount == 0)
          l10n.widgetsTrueplayTunedCount(tunedCount, total),
        l10n.widgetsTrueplayActiveCount(enabledCount, total),
      ];
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
    // doing what the official app refuses. The copy hedges to "could" for the
    // same reason — the certainty isn't earned.
    //
    // What the evidence DOES justify is not letting it happen by accident: the
    // loss is silent and there is no undo, so the enable asks first and names
    // what it costs.
    //
    // ⚠️ Turning it OFF asks too, while the set is short — not because the (0)
    // write is known to destroy anything (it isn't; every destructive cell we
    // have is the (1) write, and (0) on an incomplete set is simply UNTESTED)
    // but because it is a TRAP DOOR: the only way back is the (1) write, which
    // is the destructive one. So switching off here is effectively
    // irreversible, and that is worth knowing before rather than after.
    final incomplete = tunedCount < total;
    final canToggle = tunedCount > 0 && !busy;
    // Only warn about a write the user can actually issue. `incomplete` is also
    // true with NOTHING tuned (and while the reads are still in flight), where
    // the switch is disabled — so warning there told every untuned speaker, and
    // every set mid-read, that it could destroy tunings that do not exist.
    final warn = incomplete && canToggle;
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
          onChanged: canToggle ? (v) => _set(v, warn, tuned) : null,
        ),
      ],
    );

    // Per-speaker breakdown, shown ONLY when the speakers disagree — which is
    // exactly when the "5/6" counter raises a question it can't answer. A
    // uniform set (all active, none tuned, nothing read yet) says everything in
    // the subtitle already, so it stays a single row and never flashes a list
    // in while the reads land.
    final rows = trueplayRows(widget.devices, tp.byUuid, label: widget.label);
    final showRows =
        rows.length > 1 && rows.map((r) => r.state).toSet().length > 1;

    final tile = _frame(
      context,
      icon: Icons.tune,
      iconColor: isOn ? scheme.primary : scheme.onSurfaceVariant,
      subtitle: !warn
          ? subtitle
          : '$subtitle · '
              '${isOn ? l10n.widgetsTrueplayOneWay : l10n.widgetsTrueplayIncompleteSet}',
      trailing: trailing,
      // Tapping anywhere on the row toggles it, same as the switch.
      onTap: canToggle ? () => _set(!isOn, warn, tuned) : null,
    );
    if (!showRows) return tile;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        Padding(
          // Indented to the tile's title (gutter + a 24pt icon + the ListTile's
          // 16pt title gap) so the breakdown reads as belonging to the row above
          // rather than as more settings.
          padding:
              const EdgeInsets.fromLTRB(kPageGutter + 40, 0, kPageGutter, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rows)
                LabelValueRow(
                    label: r.label, value: _stateLabel(l10n, r.state)),
            ],
          ),
        ),
      ],
    );
  }

  String _stateLabel(AppLocalizations l10n, TrueplayRowState state) =>
      switch (state) {
        TrueplayRowState.active => l10n.widgetsTrueplayActive,
        TrueplayRowState.tunedOff => l10n.widgetsTrueplayTunedOff,
        TrueplayRowState.notTuned => l10n.widgetsTrueplayRowNotTuned,
        TrueplayRowState.unknown => l10n.widgetsTrueplayRowUnread,
      };

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
