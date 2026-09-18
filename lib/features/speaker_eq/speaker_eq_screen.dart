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
import '../widgets/confirm_dialog.dart';
import '../widgets/destructive_button.dart';
import '../widgets/info_note.dart';
import '../widgets/max_width_body.dart';
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

/// The EQ page for one entity: adjust, then apply.
///
/// A room measurement, when it ships, produces a base correction and these
/// sliders become offsets on top of it. With no measurement the base is simply
/// flat and the sliders are the whole curve — which is why the measure stage is
/// absent rather than stubbed: nothing here has to change to add it.
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
  String?
  _editing; // the member whose sliders are on screen, in individual mode

  bool _overwriteConfirmed = false;

  /// Whether a tuning of ours is actually ON the speakers. Not "has the user
  /// moved a slider" — before an apply there is nothing to switch on or remove,
  /// and an on/off row reading "nothing applied yet" is just noise.
  bool _applied = false;

  final _freqs = eqGrid();

  @override
  void initState() {
    super.initState();
    // Loaded once here rather than from build(): scheduling it per build needed
    // a latch, and a second load landing after the user had already moved a
    // slider would stomp it.
    final system = ref.read(sonosControllerProvider).value;
    if (system != null) _load(eqMembers(system, widget.uuid));
  }

  /// Seed the sliders from whatever was last applied to this entity.
  Future<void> _load(List<SonosDevice> members) async {
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
      d.uuid: _individual ? (_perMember[d.uuid] ?? flatCurve()) : _shared,
  };

  List<double> get _current =>
      _individual ? (_perMember[_editing!] ??= flatCurve()) : _shared;

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
    final wouldOverwrite = await ref
        .read(speakerEqControllerProvider.notifier)
        .wouldOverwrite(members: members);
    if (!mounted) return false;
    if (wouldOverwrite) {
      final ok = await confirmDialog(
        context,
        title: l10n.eqOverwriteTitle,
        message: l10n.eqOverwriteBody,
        confirmLabel: l10n.eqOverwriteConfirm,
      );
      if (!ok) return false;
    }
    _overwriteConfirmed = true;
    return true;
  }

  Future<void> _apply(List<SonosDevice> members) async {
    if (!await _ensureConfirmed(members)) return;
    final ok = await ref
        .read(speakerEqControllerProvider.notifier)
        .apply(
          entityId: widget.uuid,
          members: members,
          offsets: _offsetsFor(members),
        );
    if (ok && mounted) setState(() => _applied = true);
  }

  Future<void> _remove(List<SonosDevice> members) async {
    final l10n = context.l10n;
    final ok = await confirmDialog(
      context,
      title: l10n.eqRemoveTitle,
      message: l10n.eqRemoveBody,
      confirmLabel: l10n.eqRemoveConfirm,
    );
    if (!ok || !mounted) return;
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
    final members = system == null
        ? const <SonosDevice>[]
        : eqMembers(system, widget.uuid);

    if (member == null || members.isEmpty) {
      return AppScaffold(
        title: l10n.eqTitle,
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: MissingRoomView(),
        ),
      );
    }
    _editing ??= members.first.uuid;

    var status = ref.watch(speakerEqControllerProvider);
    // The provider is global; ignore a result that belongs to another entity.
    if (status.entityId != widget.uuid) status = const SpeakerEqStatus();
    final curve = composeCorrection(bandOffsetsDb: _current, freqs: _freqs);
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      title: member.zoneName,
      subtitle: l10n.eqTitle,
      // No step header until the room-measurement stage actually ships: an
      // always-disabled step advertises a feature that doesn't exist yet. When
      // it lands, this becomes the second of two steps — the data model already
      // treats the sliders as offsets on a (currently null) measured base.
      // Clamped rather than full-bleed, unlike the other detail pages: this one
      // is a form, and ten sliders spread across a landscape tablet are unusable.
      // MaxWidthBody owns the breakpoint, so a phone is untouched.
      body: MaxWidthBody(
        child: ScrollFooter(
          padding: const EdgeInsets.symmetric(vertical: 16),
          footer: _Footer(
            status: status,
            onApply: () => _apply(members),
            onRemove: () => _remove(members),
            hasTuning: _applied || status.applied,
          ),
          children: [
            // Leads the page: the EQ shares Trueplay's single storage slot,
            // which is the one thing a user cannot discover from the UI and
            // cannot undo once they hit Apply.
            _Gutter(child: InfoNote(l10n.eqTrueplayNote)),
            Gap.m,
            // Scope first: what you are editing, before what it looks like.
            _Gutter(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.eqModeAll)),
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.eqModeIndividual),
                  ),
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
                      EqCurveView(
                        freqs: _freqs,
                        curves: [EqCurve(curve, scheme.primary)],
                      ),
                      Gap.m,
                      _Bands(gains: _current, onChanged: _setBand),
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
    );
  }
}

class _Gutter extends StatelessWidget {
  final Widget child;
  const _Gutter({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
    child: child,
  );
}

class _Bands extends StatelessWidget {
  final List<double> gains;
  final void Function(int index, double value) onChanged;
  const _Bands({required this.gains, required this.onChanged});

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
                  // Ten columns is narrow enough that "-5.5 dB" wraps and
                  // shoves its slider down; shrink to fit instead.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.eqGainDb(_fmt(gains[i])),
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: gains[i] == 0
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
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
                    ),
                  ),
                  Text(
                    eqBandLabel(kEqBands[i]),
                    style: theme.textTheme.labelSmall,
                  ),
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
              label: Text(
                roles[d.uuid] == null
                    ? d.typeLabel
                    : '${d.typeLabel} · ${roles[d.uuid]}',
              ),
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
  final VoidCallback onApply;
  final VoidCallback onRemove;

  /// Whether a tuning of ours is on the speakers yet — before the first apply
  /// there is nothing to remove.
  final bool hasTuning;
  const _Footer({
    required this.status,
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
        Padding(
          // Top gutter as well as the sides: the button is a separate thing
          // from the card above it and was reading as attached to it.
          padding: const EdgeInsets.fromLTRB(
              kPageGutter, kPageGutter, kPageGutter, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Above the button, not below it: an error under a full-width
              // button sat below the fold until you scrolled.
              if (!status.busy && (status.error != null || status.applied)) ...[
                _StatusLine(status: status),
                Gap.m,
              ],
              // Progress lives IN the button: the thing you pressed is the
              // thing that should say it is working, and a separate line below
              // it was off-screen until you scrolled.
              FilledButton.icon(
                // Applying stays on this page — no progress route, no pop — so
                // the sliders you just moved are still in front of you.
                onPressed: status.busy ? null : onApply,
                icon: status.busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.equalizer),
                label: Text(status.busy ? l10n.eqApplying : l10n.eqApply),
              ),
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
    final error = status.error;
    if (error != null) {
      // No retry affordance: Apply sits directly below and is exactly that.
      return Text(
        localizedError(l10n, error),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
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
