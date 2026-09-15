import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/custom_eq.dart';
import '../../state/localized_error.dart';
import '../../state/sonos_controller.dart';
import '../../state/speaker_eq_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy_view.dart';
import '../widgets/destructive_button.dart';
import '../widgets/scroll_footer.dart';
import 'eq_curve_view.dart';
import 'eq_slider.dart';

/// Every native speaker an EQ would be written to for [uuid].
///
/// Reads [ZoneGroupMember.bondedUuids], which unions BOTH bond representations —
/// a home theater's `HTSatChanMapSet` and a group's `ChannelMapSet`. Using only
/// the HT map would silently reduce every stereo pair / zone / custom group to
/// its coordinator, and a spectral-tuning apply that omits a bonded member
/// stores nothing at all (with an HTTP 200 and no error).
///
/// Line-out boxes are excluded: they have no drivers of their own to tune.
List<SonosDevice> eqMembers(SonosSystem system, String uuid) {
  final member = system.memberByUuid(uuid);
  if (member == null) return const [];
  return member.bondedUuids
      .map(system.device)
      .whereType<SonosDevice>()
      .where((d) => !d.drivesExternalSpeakers)
      .toList();
}

/// UUID → the speaker's role in this bond, for labelling. Two dedicated fronts
/// are both "Era 100", so the type alone cannot identify a speaker. Covers both
/// bond kinds; empty for a standalone speaker, which needs no role.
Map<String, String> eqRoles(ZoneGroupMember member) => {
      for (final c in SonosChannel.values)
        for (final u in member.uuidsForChannel(c)) u: c.shortLabel,
      for (final e in member.groupChannels.entries)
        e.key: groupChannelShort(e.value),
      for (final u in member.channelMapUuids)
        if (member.groupChannels[u] == null) u: SonosChannel.sub.shortLabel,
    };

/// The tuning flow for one entity: measure (not built yet), adjust, apply.
///
/// The three steps are one screen on purpose. A room measurement produces a base
/// correction and the sliders are offsets on top of it; with no measurement the
/// base is simply flat and the sliders are the whole curve. That is why step 1
/// is shown but disabled rather than hidden — it is a stage of this flow, not a
/// separate feature.
class SpeakerEqScreen extends ConsumerStatefulWidget {
  final String uuid;
  const SpeakerEqScreen({super.key, required this.uuid});

  @override
  ConsumerState<SpeakerEqScreen> createState() => _SpeakerEqScreenState();
}

class _SpeakerEqScreenState extends ConsumerState<SpeakerEqScreen> {
  /// Band offsets per member UUID. In "all speakers" mode every member shares
  /// [_shared]; individual mode edits [_perMember].
  List<double> _shared = flatCurve();
  final Map<String, List<double>> _perMember = {};
  bool _individual = false;
  String? _editing; // the member whose sliders are on screen, in individual mode

  bool _live = false;
  bool _overwriteConfirmed = false;
  bool _loaded = false;

  /// Whether a tuning of ours is actually ON the speakers. Not "has the user
  /// moved a slider" — before an apply there is nothing to switch on or remove,
  /// and an on/off row reading "nothing applied yet" is just noise.
  bool _applied = false;

  final _freqs = eqGrid();

  @override
  void dispose() {
    ref.read(speakerEqControllerProvider.notifier).cancelPending();
    super.dispose();
  }

  /// Seed the sliders from whatever was last applied to this entity.
  Future<void> _load(List<SonosDevice> members) async {
    // Claim the load before awaiting: a rebuild while it is in flight would
    // otherwise schedule a second one, whose late addAll could stomp slider
    // moves the user has already made.
    _loaded = true;
    final stored = await ref
        .read(speakerEqControllerProvider.notifier)
        .loadStored(widget.uuid);
    if (!mounted) return;
    setState(() {
      if (stored.isEmpty) return;
      _applied = true;
      _perMember.addAll(stored);
      final distinct = stored.values.map((v) => v.join(',')).toSet();
      // One curve shared by everyone reopens as "all speakers"; anything else
      // must reopen in individual mode or it would silently flatten the user's
      // per-speaker work on the next apply.
      if (distinct.length == 1 && stored.length == members.length) {
        _shared = List.of(stored.values.first);
      } else {
        _individual = true;
      }
    });
  }

  Map<String, List<double>> _offsetsFor(List<SonosDevice> members) => {
        for (final d in members)
          d.uuid: _individual
              ? (_perMember[d.uuid] ?? flatCurve())
              : _shared,
      };

  List<double> get _current => _individual
      ? (_perMember[_editing!] ??= flatCurve())
      : _shared;

  void _setBand(int i, double v) {
    setState(() {
      final next = List<double>.of(_current)..[i] = v;
      _individual ? _perMember[_editing!] = next : _shared = next;
    });
  }

  /// Runs the destructive-overwrite check once per visit, whichever control
  /// triggers it first. Returns false when the user backs out.
  Future<bool> _ensureConfirmed(List<SonosDevice> members) async {
    if (_overwriteConfirmed) return true;
    final l10n = context.l10n;
    final result = await ref
        .read(speakerEqControllerProvider.notifier)
        .preflight(entityId: widget.uuid, members: members);
    if (!mounted) return false;
    if (result == EqPreflight.wouldOverwrite) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.eqOverwriteTitle),
          content: Text(l10n.eqOverwriteBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.actionCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.eqOverwriteConfirm)),
          ],
        ),
      );
      if (ok != true) return false;
    }
    _overwriteConfirmed = true;
    return true;
  }

  Future<void> _apply(List<SonosDevice> members) async {
    if (!await _ensureConfirmed(members)) return;
    final ok = await ref.read(speakerEqControllerProvider.notifier).apply(
          entityId: widget.uuid,
          members: members,
          offsets: _offsetsFor(members),
        );
    if (ok && mounted) setState(() => _applied = true);
  }

  Future<void> _toggleLive(bool on, List<SonosDevice> members) async {
    if (!on) {
      ref.read(speakerEqControllerProvider.notifier).cancelPending();
      setState(() => _live = false);
      return;
    }
    // Confirm before arming, not after the first drag — the user should know
    // what they are about to overwrite before they start moving sliders. Arming
    // itself writes nothing.
    if (!await _ensureConfirmed(members)) return;
    if (mounted) setState(() => _live = true);
  }

  Future<void> _remove(List<SonosDevice> members) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.eqRemoveTitle),
        content: Text(l10n.eqRemoveBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.actionCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.eqRemoveConfirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await ref
        .read(speakerEqControllerProvider.notifier)
        .remove(entityId: widget.uuid, members: members);
    if (done && mounted) {
      setState(() {
        _shared = flatCurve();
        _perMember.clear();
        _applied = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final system = ref.watch(sonosControllerProvider).value;
    final member = system?.memberByUuid(widget.uuid);
    final members = system == null ? const <SonosDevice>[] : eqMembers(system, widget.uuid);

    if (member == null || members.isEmpty) {
      return AppScaffold(
        title: l10n.eqTitle,
        body: const Padding(
            padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }
    if (!_loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(members));
    }
    _editing ??= members.first.uuid;

    var status = ref.watch(speakerEqControllerProvider);
    // The provider is global; ignore a result that belongs to another entity.
    if (status.isIdleFor(widget.uuid)) status = const SpeakerEqStatus();
    final curve = composeCorrection(bandOffsetsDb: _current, freqs: _freqs);
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      title: member.zoneName,
      subtitle: l10n.eqTitle,
      body: Column(
        children: [
          // The two stages of one flow. Hand-rolled rather than Flutter's
          // Stepper: that one puts the label beside the number and separates its
          // header with elevation, and it owns a ListView that would fight the
          // pinned footer below.
          const _StepHeader(),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: ScrollFooter(
              padding: const EdgeInsets.symmetric(vertical: 16),
              footer: _Footer(
                status: status,
                live: _live,
                onLive: (v) => _toggleLive(v, members),
                onApply: () => _apply(members),
                onRemove: () => _remove(members),
                hasTuning: _applied || status.applied,
              ),
              children: [
                // Scope first: what you are editing, before what it looks like.
                _Gutter(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(l10n.eqModeAll)),
                      ButtonSegment(
                          value: true, label: Text(l10n.eqModeIndividual)),
                    ],
                    selected: {_individual},
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) => setState(() {
                      // "Combined" means every member IS the shared curve —
                      // that is what an apply from it writes. So switching to
                      // per-speaker seeds every member from it rather than
                      // reviving stale curves the user has since overridden.
                      if (sel.first) {
                        for (final d in members) {
                          _perMember[d.uuid] = List.of(_shared);
                        }
                      }
                      _individual = sel.first;
                    }),
                  ),
                ),
                if (_individual) ...[
                  Gap.s,
                  _MemberPicker(
                    members: members,
                    roles: eqRoles(member),
                    selected: _editing!,
                    edited: {
                      for (final e in _perMember.entries)
                        if (!isFlat(e.value)) e.key,
                    },
                    onSelected: (u) => setState(() => _editing = u),
                  ),
                ],
                Gap.m,
                _Gutter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          EqCurveView(freqs: _freqs, curves: [
                            EqCurve(curve, scheme.primary),
                          ]),
                          Gap.m,
                          _Bands(
                            gains: _current,
                            onChanged: _setBand,
                            onChangeEnd: () {
                              if (_live) {
                                ref
                                    .read(speakerEqControllerProvider.notifier)
                                    .requestLiveApply(
                                      entityId: widget.uuid,
                                      members: members,
                                      offsets: _offsetsFor(members),
                                    );
                              }
                            },
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => setState(() {
                                _individual
                                    ? _perMember[_editing!] = flatCurve()
                                    : _shared = flatCurve();
                              }),
                              child: Text(l10n.eqReset),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The flow's two stages: a numbered marker with its label underneath, joined by
/// a connector. Measure is disabled and subtitled — it is a stage of this flow
/// that isn't built, not a separate feature, and showing it is how a user learns
/// the flow has a second half.
class _StepHeader extends StatelessWidget {
  const _StepHeader();

  static const _markerSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageGutter, 12, kPageGutter, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Step(
            number: 1,
            title: l10n.eqStepMeasure,
            subtitle: l10n.eqComingSoon,
            active: false,
          ),
          // Spans the gap between the markers, on their centre line rather than
          // the row's — the steps size to their labels, the connector takes the
          // rest.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12)
                  .add(const EdgeInsets.only(top: _markerSize / 2)),
              child: SizedBox(
                height: 1,
                child: ColoredBox(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
          ),
          _Step(number: 2, title: l10n.eqStepAdjust, active: true),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String? subtitle;
  final bool active;
  const _Step({
    required this.number,
    required this.title,
    required this.active,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = active ? scheme.onSurface : scheme.onSurfaceVariant;
    return Column(
      children: [
        Container(
          width: _StepHeader._markerSize,
          height: _StepHeader._markerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? scheme.primary : Colors.transparent,
            border: active ? null : Border.all(color: scheme.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: theme.textTheme.labelMedium?.copyWith(
              color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(title,
            style: theme.textTheme.titleSmall?.copyWith(color: fg),
            textAlign: TextAlign.center),
        if (subtitle != null)
          Text(
            subtitle!,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

class _Gutter extends StatelessWidget {
  final Widget child;
  const _Gutter({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
      child: child);
}

/// Step 1, present but not yet built. Shown rather than hidden so the capability
/// is discoverable; deliberately says nothing about how it will work or when.
class _Bands extends StatelessWidget {
  final List<double> gains;
  final void Function(int index, double value) onChanged;
  final VoidCallback onChangeEnd;
  const _Bands({
    required this.gains,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SizedBox(
      height: 210,
      child: Row(
        children: [
          for (var i = 0; i < kEqBands.length; i++)
            Expanded(
              child: Column(
                children: [
                  Text(
                    l10n.eqGainDb(_fmt(gains[i])),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: gains[i] == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: EqSlider(
                      value: gains[i],
                      min: -kEqMaxCutDb,
                      max: kEqMaxBoostDb,
                      divisions: (kEqMaxCutDb + kEqMaxBoostDb).round() * 2,
                      label: l10n.eqGainDb(_fmt(gains[i])),
                      semanticFormatter: (v) =>
                          '${l10n.eqBandSemantics(eqBandLabel(kEqBands[i]))}, '
                          '${l10n.eqGainDb(_fmt(v))}',
                      onChanged: (v) => onChanged(i, v),
                      onChangeEnd: onChangeEnd,
                    ),
                  ),
                  Text(eqBandLabel(kEqBands[i]),
                      style: theme.textTheme.labelSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      '${v > 0 ? '+' : ''}${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}';
}

class _MemberPicker extends StatelessWidget {
  final List<SonosDevice> members;

  /// UUID → its channel role in this bond, when it has one. Two dedicated
  /// fronts are both "Era 100", so the type alone cannot identify a speaker.
  final Map<String, String> roles;
  final String selected;
  final Set<String> edited;
  final ValueChanged<String> onSelected;
  const _MemberPicker({
    required this.members,
    required this.roles,
    required this.selected,
    required this.edited,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
      child: Row(
        children: [
          for (final d in members) ...[
            ChoiceChip(
              selected: d.uuid == selected,
              // The filled background already says "selected"; the default
              // checkmark would collide with the edited pencil.
              showCheckmark: false,
              onSelected: (_) => onSelected(d.uuid),
              avatar: edited.contains(d.uuid)
                  ? const Icon(Icons.edit, size: 16)
                  : null,
              label: Text(roles[d.uuid] == null
                  ? d.typeLabel
                  : '${d.typeLabel} · ${roles[d.uuid]}'),
              tooltip: edited.contains(d.uuid) ? l10n.eqEdited : null,
            ),
            Gap.s,
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final SpeakerEqStatus status;
  final bool live;
  final ValueChanged<bool> onLive;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  /// Whether a tuning of ours is on the speakers yet — before the first apply
  /// there is nothing to remove.
  final bool hasTuning;
  const _Footer({
    required this.status,
    required this.live,
    required this.onLive,
    required this.onApply,
    required this.onRemove,
    required this.hasTuning,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          shape: kFlatTileShape,
          contentPadding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          secondary: const Icon(Icons.bolt_outlined),
          title: Text(l10n.eqLiveApply),
          subtitle: Text(l10n.eqLiveApplySubtitle),
          value: live,
          onChanged: status.busy ? null : onLive,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 0, kPageGutter, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                // Applying stays on this page — no progress route, no pop — so
                // the sliders you just moved are still in front of you.
                onPressed: (live || status.busy) ? null : onApply,
                icon: const Icon(Icons.equalizer),
                label: Text(l10n.eqApply),
              ),
              if (status.busy || status.error != null || status.applied) ...[
                Gap.s,
                _StatusLine(status: status),
              ],
            ],
          ),
        ),
        // No on/off switch here: it is the same Trueplay toggle that already
        // sits on the entity's detail page one level up, and a second copy under
        // a second name is just confusing. This page authors the tuning; the
        // detail page switches it.
        if (hasTuning)
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 8),
            child: DestructiveButton(
              icon: Icons.delete_outline,
              label: l10n.eqRemove,
              onPressed: status.busy ? null : onRemove,
            ),
          ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final SpeakerEqStatus status;
  const _StatusLine({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (status.busy) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          Gap.s,
          Text(l10n.eqApplying, style: theme.textTheme.bodySmall),
        ],
      );
    }
    final error = status.error;
    if (error != null) {
      // No retry affordance: Apply sits directly above and is exactly that.
      return Text(
        localizedError(l10n, error),
        style:
            theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
        Gap.s,
        Text(l10n.eqApplied, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
