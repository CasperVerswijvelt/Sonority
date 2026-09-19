import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../../state/trueplay_controller.dart';
import '../widgets/bondable_speaker_tile.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/identify_controls.dart';
import '../widgets/info_note.dart';
import '../widgets/max_width_body.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/selectable_speaker_card.dart';
import '../widgets/speaker_picker.dart';

/// How the segmented control frames the bond. All three build a `ChannelMapSet`
/// and go through the same `AddBondedZones` engine path. Public because the
/// review step is (see [GroupReviewStep]).
enum GroupMode { stereo, zone, custom }

/// Unified "Group speakers" flow: bond 2–16 speakers as a **Stereo** pair, a
/// full-range **Zone**, or a **Custom** per-speaker L/R/Both layout — each with
/// an optional Sub. Stepped (speakers → sub → name → review) like the
/// home-theater setup.
///
/// When [editUuid] is set the flow reconfigures that existing group instead of
/// creating one: it seeds its selection from the live group and applies via
/// `SonosController.editGroup` (in-place re-assert for adds/channel changes,
/// dissolve-then-recreate only when a member is dropped). Mirrors the HT
/// "Configure" flow (`FrontSurroundsFlow`).
class GroupFlow extends ConsumerStatefulWidget {
  /// When set, reconfigure this existing group instead of creating one.
  final String? editUuid;

  /// Optionally pre-selected when opened from a room / Sub detail shortcut, so
  /// the originating speaker (or Sub) is already picked in the flow. (Create
  /// mode only — ignored when [editUuid] is set.)
  final String? preselectSpeaker;
  final String? preselectSub;
  const GroupFlow(
      {super.key, this.editUuid, this.preselectSpeaker, this.preselectSub});

  @override
  ConsumerState<GroupFlow> createState() => _GroupFlowState();
}

class _GroupFlowState extends ConsumerState<GroupFlow> with IdentifyMixin {
  GroupMode _mode = GroupMode.stereo;
  int _step = 0;
  final List<String> _selected = []; // ordered; for stereo [left, right]
  final Map<String, GroupChannel> _channels = {}; // custom: uuid → channel
  String? _subUuid;
  final _nameController = TextEditingController();

  static const _maxSpeakers = 16;
  static const _stepSpeakers = 0;
  static const _stepSub = 1;
  static const _stepName = 2;
  static const _stepReview = 3;

  bool get _editing => widget.editUuid != null;
  int get _cap => _mode == GroupMode.stereo ? 2 : _maxSpeakers;

  @override
  void initState() {
    super.initState();
    final sys = ref.read(sonosControllerProvider).value;
    // Before the seeding branches below, which each return early.
    loadTrueplayForPickers(ref);
    // Edit mode: seed the whole selection from the live group (mirrors
    // FrontSurroundsFlow). Preselects are create-only and ignored here.
    final uuid = widget.editUuid;
    if (uuid != null) {
      final g = sys?.memberByUuid(uuid);
      if (g == null || !g.isGroup) return;
      _mode = switch (g.groupKind) {
        GroupKind.stereoPair => GroupMode.stereo,
        GroupKind.zone => GroupMode.zone,
        _ => GroupMode.custom,
      };
      final gc = g.groupChannels; // coordinator-first, Sub excluded
      _selected.addAll(gc.keys);
      _channels.addAll(gc);
      _subUuid = g.subUuid;
      _nameController.text = g.zoneName;
      return;
    }
    // Create mode: adopt a preselect that's still a real candidate — guards a
    // stale uuid or a hand-crafted deep link (the shortcuts always pass valid).
    final sp = widget.preselectSpeaker;
    if (sp != null && (sys?.zoneableSpeakers.any((d) => d.uuid == sp) ?? false)) {
      _selected.add(sp);
      _channels[sp] = GroupChannel.both;
    }
    final sub = widget.preselectSub;
    if (sub != null && (sys?.bondableSubs.any((d) => d.uuid == sub) ?? false)) {
      _subUuid = sub;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggle(String uuid) => setState(() {
    if (_selected.remove(uuid)) {
      _channels.remove(uuid);
    } else if (_selected.length < _cap) {
      _selected.add(uuid);
      _channels[uuid] = GroupChannel.both;
    }
  });

  void _onModeChanged(GroupMode m) => setState(() {
    _mode = m;
    if (m == GroupMode.stereo && _selected.length > 2) {
      for (final u in _selected.sublist(2)) {
        _channels.remove(u);
      }
      _selected.removeRange(2, _selected.length);
    }
  });

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(sonosControllerProvider).value;
    if (system == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // When editing, the group's own members (incl. the coordinator) and its Sub
    // are already bonded, so they're absent from zoneable/bondable lists — merge
    // them back in so they show selected and deselecting is reversible (mirrors
    // the HT flow's `avail`/`freeSubs`).
    final existing = _editing ? system.memberByUuid(widget.editUuid!) : null;
    // Free speakers plus those bonded into ANOTHER entity, so a user need not
    // unbond by hand first. ⚠️ Unlike a home theater, every group write costs
    // the calibration of the whole source bond (EXP-23: `AddBondedZones`
    // rebuilds a bond even on an unchanged map), which is what the note under
    // the list spells out. The shortcuts that gate this flow count the same
    // list, so they can't offer a flow with one candidate in it.
    final candidates = system.groupCandidates(exceptPrimary: widget.editUuid);
    final subs = system.bondableSubs.toList();
    if (existing != null) {
      for (final u in existing.groupChannels.keys) {
        final d = system.device(u);
        if (d != null && !candidates.any((x) => x.uuid == u)) candidates.add(d);
      }
      final subU = existing.subUuid;
      final subD = subU == null ? null : system.device(subU);
      if (subD != null && !subs.any((x) => x.uuid == subU)) subs.add(subD);
    }
    // Trueplay per candidate, so a speaker holding a tuning is tagged before it
    // is moved out of whatever it is bonded into.
    final picker = PickerContext(
      system: system,
      calibration: ref.watch(trueplayControllerProvider).byUuid,
      // A speaker still being READ is not one known to be untuned. Without
      // this the flow opens claiming every bond loses its tuning, then
      // retracts when the reads land.
      busy: ref.watch(trueplayControllerProvider).busy,
      exceptPrimary: widget.editUuid,
      // Editing a group REBUILDS it, clearing its own members' Trueplay too,
      // but only if the bond actually changes. Gating on that is what keeps
      // the flow from warning the moment it opens on an untouched group. A
      // CREATE always writes, and costs the speakers it bonds together.
      writes: _bondDiffers(system, existing),
    );

    final scheme = Theme.of(context).colorScheme;
    // Candidates here are all standalone, so chime applies; gate per-device
    // anyway so the rule stays consistent with the HT flow.
    Widget idControls(SonosDevice d) =>
        identifyButtons(d, chime: system.isStandalone(d.uuid));

    // A step's subtitle: the picked speaker types when it has a selection (so a
    // collapsed step summarizes itself), else "Optional".
    Widget stepSubtitle(List<String> uuids) => uuids.isEmpty
        ? Text(context.l10n.groupOptional)
        : Text(
            uuids
                .map((u) => system.device(u)?.typeLabel ?? context.l10n.widgetsSpeaker)
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    return Scaffold(
      // No scroll-under elevation: the steps tuck behind the segmented-control
      // header (with its own divider), so a second line under the app bar would
      // double up.
      appBar: AppBar(
        title: Text(
            _editing ? context.l10n.groupEditTitle : context.l10n.groupFlowTitle),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        // The segmented-mode header + its divider stay full-width; only the
        // scrolling Stepper below is clamped/centered on a wide window.
        child: candidates.length < 2
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.l10n.groupNeedTwoSpeakers,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  // Opaque, pinned header so scrolling steps tuck cleanly behind it.
                  Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<GroupMode>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: Theme.of(context).textTheme.titleSmall,
                          ),
                          segments: [
                            ButtonSegment(
                              value: GroupMode.stereo,
                              label: Text(context.l10n.groupModeStereo),
                            ),
                            ButtonSegment(
                              value: GroupMode.zone,
                              label: Text(context.l10n.groupModeZone),
                            ),
                            ButtonSegment(
                              value: GroupMode.custom,
                              label: Text(context.l10n.groupModeCustom),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => _onModeChanged(s.first),
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: MaxWidthBody(
                      child: Stepper(
                        currentStep: _step,
                        type: StepperType.vertical,
                        onStepTapped: (i) => setState(() => _step = i),
                        controlsBuilder: (context, _) => _controls(system),
                        steps: [
                          Step(
                            title: Text(context.l10n.groupStepSelect),
                            subtitle: _selected.isEmpty
                                ? null
                                : stepSubtitle(_selected),
                            isActive: _step >= _stepSpeakers,
                            state: _selected.length >= 2
                                ? StepState.complete
                                : StepState.indexed,
                            content: _SelectStep(
                              mode: _mode,
                              candidates: candidates,
                              selected: _selected,
                              picker: picker,
                              channels: _channels,
                              onToggle: _toggle,
                              onChannel: (u, c) =>
                                  setState(() => _channels[u] = c),
                              onSwap: () => setState(
                                () => _selected.setAll(0, [
                                  _selected[1],
                                  _selected[0],
                                ]),
                              ),
                              identifyControls: idControls,
                            ),
                          ),
                          Step(
                            title: Text(context.l10n.groupStepAddSub),
                            subtitle: stepSubtitle([
                              if (_subUuid != null) _subUuid!,
                            ]),
                            isActive: _step >= _stepSub,
                            state: _subUuid != null
                                ? StepState.complete
                                : StepState.indexed,
                            content: _SubStep(
                              subs: subs,
                              selected: _subUuid,
                              onChanged: (u) => setState(() => _subUuid = u),
                              identifyControls: idControls,
                            ),
                          ),
                          Step(
                            title: Text(context.l10n.groupStepName),
                            subtitle: Text(context.l10n.groupOptional),
                            isActive: _step >= _stepName,
                            content: Padding(
                              // Top room for the floating label (else it clips).
                              padding: const EdgeInsets.only(top: 8),
                              child: TextField(
                                controller: _nameController,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: context.l10n.groupNameLabel,
                                  hintText: context.l10n.groupNameHint,
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          Step(
                            title: Text(context.l10n.groupStepReview),
                            isActive: _step >= _stepReview,
                            content: GroupReviewStep(
                              mode: _mode,
                              system: system,
                              picker: picker,
                              selected: _selected,
                              channels: _channels,
                              subUuid: _subUuid,
                              name: _nameController.text.trim(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// The target members (uuid + channel), ordered — coordinator first, and for
  /// stereo [left, right]. Shared by the Apply gate and the apply call.
  List<({SonosDevice device, GroupChannel channel})> _members(
      SonosSystem system) {
    final members = <({SonosDevice device, GroupChannel channel})>[];
    for (var i = 0; i < _selected.length; i++) {
      final d = system.device(_selected[i]);
      if (d == null) continue;
      final channel = switch (_mode) {
        GroupMode.stereo => i == 0 ? GroupChannel.left : GroupChannel.right,
        GroupMode.zone => GroupChannel.both,
        GroupMode.custom => _channels[_selected[i]] ?? GroupChannel.both,
      };
      members.add((device: d, channel: channel));
    }
    return members;
  }

  /// True when the current selection would rewrite [existing]'s BOND: the
  /// part that costs Trueplay, since `AddBondedZones` rebuilds the bond even on
  /// an unchanged map. A rename alone doesn't, which is why it isn't in here.
  /// Delegates to the shared [groupApplyWrites] so the Apply gate and the cost
  /// card can't drift apart, and so a test can reach the real rule.
  bool _bondDiffers(SonosSystem system, ZoneGroupMember? existing) {
    final members = _members(system);
    return groupApplyWrites(
      existing: existing,
      channels: {for (final m in members) m.device.uuid: m.channel},
      subUuid: _subUuid,
      coordUuid: members.firstOrNull?.device.uuid,
    );
  }

  /// True when the current selection would actually change [existing] — so an
  /// unchanged edit disables Apply (no needless re-assert / dissolve).
  bool _differs(SonosSystem system, ZoneGroupMember existing) =>
      _bondDiffers(system, existing) ||
      _nameController.text.trim() != existing.zoneName;

  Widget _controls(SonosSystem system) {
    final isLast = _step == _stepReview;
    final canAdvance = _step != _stepSpeakers || _selected.length >= 2;
    final existing = _editing ? system.memberByUuid(widget.editUuid!) : null;
    // When editing, the final Apply is gated on an actual change.
    final canApply = !_editing || (existing != null && _differs(system, existing));
    final label = isLast
        ? (_editing
            ? context.l10n.groupSaveChanges
            : switch (_mode) {
                GroupMode.stereo => context.l10n.groupCreateStereo,
                GroupMode.zone => context.l10n.groupCreateZone,
                GroupMode.custom => context.l10n.groupCreateCustom,
              })
        : context.l10n.actionContinue;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: () => setState(() => _step--),
              child: Text(context.l10n.actionBack),
            ),
          Gap.s,
          Expanded(
            child: FilledButton(
              onPressed: !canAdvance
                  ? null
                  : isLast
                  ? (canApply ? () => _apply(system) : null)
                  : () => setState(() => _step++),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(SonosSystem system) async {
    final members = _members(system);
    if (members.length < 2) return;
    final existing =
        _editing ? system.memberByUuid(widget.editUuid!) : null;
    if (_editing && existing == null) return;
    final sub = _subUuid == null ? null : system.device(_subUuid!);
    final name = _nameController.text.trim();
    final controller = ref.read(sonosControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final l10n = context.l10n;
    final outcome = await showBondingProgress(
      context,
      title: _editing ? l10n.groupEditTitle : l10n.groupFlowTitle,
      run: () => _editing
          ? controller.editGroup(
              existing: existing!,
              members: members,
              sub: sub,
              name: name.isEmpty ? null : name,
            )
          : controller.createGroup(
              members: members,
              sub: sub,
              name: name.isEmpty ? null : name,
            ),
    );
    if (outcome == BondingOutcome.success) {
      router.pop();
    } else if (outcome == BondingOutcome.failed) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.groupCreateFailed),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }
}

/// Step 1 — pick speakers, with per-mode assignment.
class _SelectStep extends StatelessWidget {
  final GroupMode mode;
  final List<SonosDevice> candidates;
  final List<String> selected;
  final Map<String, GroupChannel> channels;
  final void Function(String uuid) onToggle;
  final void Function(String uuid, GroupChannel channel) onChannel;
  final VoidCallback onSwap;
  final Widget Function(SonosDevice device) identifyControls;

  final PickerContext picker;

  const _SelectStep({
    required this.mode,
    required this.candidates,
    required this.selected,
    required this.channels,
    required this.onToggle,
    required this.onChannel,
    required this.onSwap,
    required this.identifyControls,
    required this.picker,
  });

  String _hint(BuildContext context) => switch (mode) {
    GroupMode.stereo => context.l10n.groupHintStereo,
    GroupMode.zone => context.l10n.groupHintZone,
    GroupMode.custom => context.l10n.groupHintCustom,
  };

  @override
  Widget build(BuildContext context) {
    final cap = mode == GroupMode.stereo ? 2 : 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_hint(context), style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        SpeakerPickerSections(
          ctx: picker,
          candidates: candidates,
          selected: selected.toSet(),
          card: (d) => _card(context, d, cap),
        ),
      ],
    );
  }

  /// One selectable speaker, with an in-card channel selector revealed once
  /// selected: custom → per-speaker Left/Both/Right; stereo → a Left/Right that
  /// swaps the pair (only once both are chosen, since there's nothing to swap
  /// with before that). Zone has no per-speaker choice.
  Widget _card(BuildContext context, SonosDevice d, int cap) {
    final isSel = selected.contains(d.uuid);
    final disabled = !isSel && selected.length >= cap;
    Widget? control;
    var showControl = false;
    if (mode == GroupMode.custom && isSel) {
      showControl = true;
      control = SegmentedButton<GroupChannel>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
              value: GroupChannel.left,
              label: Text(context.l10n.groupChannelLeft)),
          ButtonSegment(
              value: GroupChannel.both,
              label: Text(context.l10n.groupChannelBoth)),
          ButtonSegment(
              value: GroupChannel.right,
              label: Text(context.l10n.groupChannelRight)),
        ],
        selected: {channels[d.uuid] ?? GroupChannel.both},
        onSelectionChanged: (s) => onChannel(d.uuid, s.first),
      );
    } else if (mode == GroupMode.stereo && isSel && selected.length == 2) {
      showControl = true;
      control = SideSelector(
        isRight: selected.indexOf(d.uuid) == 1,
        onSwap: onSwap,
      );
    }
    return SelectableSpeakerCard(
      device: d,
      selected: isSel,
      enabled: !disabled,
      onToggle: () => onToggle(d.uuid),
      titleOverride: picker.titleOverride(context, d),
      identify: identifyControls(d),
      badges: [?trueplayBadge(context, picker.calibration[d.uuid])],
      showControl: showControl,
      control: control,
    );
  }
}

/// Step 2 — optionally add a standalone Sub.
class _SubStep extends StatelessWidget {
  final List<SonosDevice> subs;
  final String? selected;
  final void Function(String? uuid) onChanged;
  final Widget Function(SonosDevice device) identifyControls;

  const _SubStep({
    required this.subs,
    required this.selected,
    required this.onChanged,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).mutedText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subs.isEmpty)
          Text(context.l10n.groupNoSub, style: muted)
        else ...[
          Text(context.l10n.groupAddSubHint, style: muted),
          Gap.s,
          // The shared tile, as every other speaker picker uses (CLAUDE.md's
          // selection grammar) — this was the one that rolled its own, so an
          // unreachable Sub rendered as a normal enabled row with no warning.
          ...subs.map(
            (s) => BondableSpeakerTile(
              device: s,
              selected: selected == s.uuid,
              onChanged: (v) => onChanged((v ?? false) ? s.uuid : null),
              subtitle: s.typeLabel,
              secondary: identifyControls(s),
              outlined: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// Step 4. Summary, the destructive-write gate, and the "large groups can be
/// flaky" nudge. Public only so the gate can be widget-tested.
///
/// The cost has to be restated HERE and not only under the speaker list: a
/// group write is the more destructive of the two flows (`AddBondedZones`
/// absorbs nothing, so every source bond is genuinely dissolved) and the
/// speaker step is three taps behind the button that writes.
@visibleForTesting
class GroupReviewStep extends StatelessWidget {
  final GroupMode mode;
  final SonosSystem system;

  /// The same context the picker used, so the note under the speaker list and
  /// this card can't price one selection two ways.
  final PickerContext picker;

  final List<String> selected;
  final Map<String, GroupChannel> channels;
  final String? subUuid;
  final String name;

  const GroupReviewStep({
    super.key,
    required this.mode,
    required this.system,
    required this.picker,
    required this.selected,
    required this.channels,
    required this.subUuid,
    required this.name,
  });

  String _type(BuildContext context, String uuid) =>
      system.device(uuid)?.typeLabel ?? context.l10n.widgetsSpeaker;

  GroupChannel _channelFor(int i) => switch (mode) {
    GroupMode.stereo => i == 0 ? GroupChannel.left : GroupChannel.right,
    GroupMode.zone => GroupChannel.both,
    GroupMode.custom => channels[selected[i]] ?? GroupChannel.both,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.mutedText;
    final l10n = context.l10n;
    final kind = switch (mode) {
      GroupMode.stereo => l10n.groupKindStereo,
      GroupMode.zone => l10n.groupKindZone(selected.length),
      GroupMode.custom => l10n.groupKindCustom(selected.length),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(kind, style: theme.textTheme.titleMedium),
        if (name.isNotEmpty) ...[
          Gap.s,
          Text(l10n.groupReviewName(name), style: muted),
        ],
        Gap.s,
        // The bonded layout, shown the same way as a group's detail view: one
        // card per member with its channel role.
        for (var i = 0; i < selected.length; i++) ...[
          MemberChannelCard(
            icon: Icons.speaker,
            type: _type(context, selected[i]),
            channel: groupChannelShort(_channelFor(i)),
          ),
          Gap.s,
        ],
        if (subUuid != null) ...[
          MemberChannelCard(
            icon: Icons.graphic_eq,
            type: system.device(subUuid!)?.typeLabel ?? l10n.groupSubwoofer,
            channel: l10n.widgetsSub,
          ),
          Gap.s,
        ],
        Gap.s,
        // Same renderer as the picker note and the HT review card: one cost
        // model, three screens. The dissolve is stated even when nothing tuned
        // is at stake: it is destructive on its own, and this card replaced the
        // confirm dialog.
        if ([
          if (picker.dissolveNote(l10n, selected.toSet()) case final n?) n,
          if (picker.warning(l10n, selected.toSet()) case final w?) w,
        ] case final lines when lines.isNotEmpty) ...[
          InfoNote(lines.join('\n')),
          Gap.s,
        ],
        Text(l10n.groupReviewNote, style: muted),
      ],
    );
  }
}
