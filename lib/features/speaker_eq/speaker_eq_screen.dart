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
import '../widgets/diagram_labels.dart';
import '../widgets/pill_chip.dart';
import '../widgets/scroll_footer.dart';
import '../widgets/section_header.dart';
import '../widgets/settings_section.dart';
import '../widgets/trueplay_control.dart';
import 'eq_curve_view.dart';

/// Every native speaker an EQ would be written to for [uuid] — the entity's
/// coordinator plus whatever its channel map bonds to it. A standalone speaker
/// has an empty map, so this is just itself. Line-out boxes are excluded: they
/// have no drivers of their own to tune.
List<SonosDevice> eqMembers(SonosSystem system, String uuid) {
  final member = system.memberByUuid(uuid);
  if (member == null) return const [];
  return <String>{member.uuid, ...member.channelAssignments.values}
      .map(system.device)
      .whereType<SonosDevice>()
      .where((d) => !d.drivesExternalSpeakers)
      .toList();
}

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
  List<double> _shared = List<double>.filled(kEqBands.length, 0);
  final Map<String, List<double>> _perMember = {};
  bool _individual = false;
  String? _editing; // the member whose sliders are on screen, in individual mode

  bool _live = false;
  bool _overwriteConfirmed = false;
  bool _loaded = false;

  final _freqs = eqGrid();

  @override
  void dispose() {
    ref.read(speakerEqControllerProvider.notifier).cancelPending();
    super.dispose();
  }

  /// Seed the sliders from whatever was last applied to this entity.
  Future<void> _load(List<SonosDevice> members) async {
    final stored = await ref
        .read(speakerEqControllerProvider.notifier)
        .loadStored(widget.uuid);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      if (stored.isEmpty) return;
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
              ? (_perMember[d.uuid] ?? List<double>.filled(kEqBands.length, 0))
              : _shared,
      };

  List<double> get _current => _individual
      ? (_perMember[_editing!] ??= List<double>.filled(kEqBands.length, 0))
      : _shared;

  void _setBand(int i, double v, List<SonosDevice> members) {
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
    await ref.read(speakerEqControllerProvider.notifier).apply(
          entityId: widget.uuid,
          members: members,
          offsets: _offsetsFor(members),
        );
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
        _shared = List<double>.filled(kEqBands.length, 0);
        _perMember.clear();
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

    final status = ref.watch(speakerEqControllerProvider);
    final requested =
        composeCorrection(bandOffsetsDb: _current, freqs: _freqs);
    final achieved = achievedDb(
      sectionsForCorrection(requested, _freqs, fs: 44100, maxSections: 16),
      _freqs,
      44100,
    );
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      title: member.zoneName,
      subtitle: l10n.eqTitle,
      body: ScrollFooter(
        padding: const EdgeInsets.symmetric(vertical: 8),
        footer: _Footer(
          status: status,
          live: _live,
          onLive: (v) => _toggleLive(v, members),
          onApply: () => _apply(members),
          onRemove: () => _remove(members),
          devices: members,
        ),
        children: [
          const _Gutter(child: SizedBox(height: 4)),
          _Gutter(child: SectionHeader(l10n.eqStepMeasure)),
          const _MeasureStep(),
          Gap.m,
          _Gutter(child: SectionHeader(l10n.eqStepAdjust)),
          _Gutter(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EqCurveView(freqs: _freqs, curves: [
                      EqCurve(requested, scheme.primary),
                      EqCurve(achieved, scheme.tertiary, dashed: true),
                    ]),
                    Gap.s,
                    _Legend(
                      requested: scheme.primary,
                      achieved: scheme.tertiary,
                    ),
                    Gap.m,
                    _Bands(
                      gains: _current,
                      onChanged: (i, v) => _setBand(i, v, members),
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
                  ],
                ),
              ),
            ),
          ),
          Gap.s,
          _Gutter(
            child: _ModeRow(
              individual: _individual,
              onChanged: (v) => setState(() {
                // "All speakers" means every member IS the shared curve —
                // that is what an apply from this mode writes. So switching to
                // per-speaker seeds every member from it rather than reviving
                // stale per-member curves the user has since overridden.
                if (v) {
                  for (final d in members) {
                    _perMember[d.uuid] = List.of(_shared);
                  }
                }
                _individual = v;
              }),
              onReset: () => setState(() {
                _individual
                    ? _perMember[_editing!] =
                        List<double>.filled(kEqBands.length, 0)
                    : _shared = List<double>.filled(kEqBands.length, 0);
              }),
            ),
          ),
          if (_individual) ...[
            Gap.s,
            _MemberPicker(
              members: members,
              roles: {
                for (final e in member.channelAssignments.entries)
                  e.value: htChannelShort(e.key),
              },
              selected: _editing!,
              edited: {
                for (final e in _perMember.entries)
                  if (!isFlat(e.value)) e.key,
              },
              onSelected: (u) => setState(() => _editing = u),
            ),
          ],
          Gap.m,
        ],
      ),
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
class _MeasureStep extends StatelessWidget {
  const _MeasureStep();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return _Gutter(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mic_none, color: muted),
              Gap.m,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PillChip(
                      icon: Icons.schedule,
                      text: l10n.eqComingSoon,
                      color: muted,
                    ),
                    Gap.s,
                    Text(
                      l10n.eqStepMeasureBody,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color requested;
  final Color achieved;
  const _Legend({required this.requested, required this.achieved});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PillChip(
            icon: Icons.show_chart, text: l10n.eqLegendRequested, color: requested),
        Gap.s,
        PillChip(
            icon: Icons.graphic_eq, text: l10n.eqLegendAchieved, color: achieved),
      ],
    );
  }
}

/// The eight band sliders. Vertical, so they read as an equaliser rather than a
/// settings list.
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
      height: 200,
      child: Row(
        children: [
          for (var i = 0; i < kEqBands.length; i++)
            Expanded(
              child: Column(
                children: [
                  Text(
                    gains[i] == 0 ? '—' : l10n.eqGainDb(_fmt(gains[i])),
                    style: theme.textTheme.labelSmall,
                  ),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: gains[i],
                        min: -kEqMaxCutDb,
                        max: kEqMaxBoostDb,
                        divisions: (kEqMaxCutDb + kEqMaxBoostDb).round() * 2,
                        label: l10n.eqGainDb(_fmt(gains[i])),
                        semanticFormatterCallback: (v) =>
                            '${l10n.eqBandSemantics(_hz(kEqBands[i]))}, '
                            '${l10n.eqGainDb(_fmt(v))}',
                        // Writes go on release, never on drag: a live apply is N
                        // network writes to real speakers.
                        onChanged: (v) => onChanged(i, v),
                        onChangeEnd: (_) => onChangeEnd(),
                      ),
                    ),
                  ),
                  Text(_hz(kEqBands[i]), style: theme.textTheme.labelSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      '${v > 0 ? '+' : ''}${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}';

  static String _hz(double f) =>
      f >= 1000 ? '${(f / 1000).toStringAsFixed(0)}k' : f.toStringAsFixed(0);
}

class _ModeRow extends StatelessWidget {
  final bool individual;
  final ValueChanged<bool> onChanged;
  final VoidCallback onReset;
  const _ModeRow({
    required this.individual,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l10n.eqModeAll)),
              ButtonSegment(value: true, label: Text(l10n.eqModeIndividual)),
            ],
            selected: {individual},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
        Gap.s,
        TextButton(onPressed: onReset, child: Text(l10n.eqReset)),
      ],
    );
  }
}

/// Which speaker's curve is being edited, in individual mode.
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
  final List<SonosDevice> devices;
  const _Footer({
    required this.status,
    required this.live,
    required this.onLive,
    required this.onApply,
    required this.onRemove,
    required this.devices,
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
                _StatusLine(status: status, onRetry: onApply),
              ],
            ],
          ),
        ),
        // The Trueplay switch doubles as this EQ's on/off: storing a tuning and
        // enabling it are separate calls, so it is an instant A/B.
        SettingsSection(children: [TrueplayControl(devices: devices)]),
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
  final VoidCallback onRetry;
  const _StatusLine({required this.status, required this.onRetry});

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
      return Row(
        children: [
          Expanded(
            child: Text(
              localizedError(l10n, error),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.eqRetry)),
        ],
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
