import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/card_grid.dart';
import '../widgets/identify_controls.dart';
import '../widgets/max_width_body.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/selectable_speaker_card.dart';

/// How the segmented control frames the bond. All three build a `ChannelMapSet`
/// and go through the same `AddBondedZones` engine path.
enum _Mode { stereo, zone, custom }

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
  final String? editUuid;
  const GroupFlow({super.key, this.editUuid});

  @override
  ConsumerState<GroupFlow> createState() => _GroupFlowState();
}

class _GroupFlowState extends ConsumerState<GroupFlow> with IdentifyMixin {
  _Mode _mode = _Mode.stereo;
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
  int get _cap => _mode == _Mode.stereo ? 2 : _maxSpeakers;

  @override
  void initState() {
    super.initState();
    // Seed from the live group when editing (mirrors FrontSurroundsFlow).
    final uuid = widget.editUuid;
    if (uuid == null) return;
    final g = ref.read(sonosControllerProvider).value?.memberByUuid(uuid);
    if (g == null || !g.isGroup) return;
    _mode = switch (g.groupKind) {
      GroupKind.stereoPair => _Mode.stereo,
      GroupKind.zone => _Mode.zone,
      _ => _Mode.custom,
    };
    final gc = g.groupChannels; // coordinator-first, Sub excluded
    _selected.addAll(gc.keys);
    _channels.addAll(gc);
    _subUuid = g.subUuid;
    _nameController.text = g.zoneName;
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

  void _onModeChanged(_Mode m) => setState(() {
    _mode = m;
    if (m == _Mode.stereo && _selected.length > 2) {
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
    final candidates = system.zoneableSpeakers
        .where((d) => d.reachable)
        .toList();
    final subs = system.bondableSubs.where((d) => d.reachable).toList();
    if (existing != null) {
      for (final u in existing.groupChannels.keys) {
        final d = system.device(u);
        if (d != null && !candidates.any((x) => x.uuid == u)) candidates.add(d);
      }
      final subU = existing.subUuid;
      final subD = subU == null ? null : system.device(subU);
      if (subD != null && !subs.any((x) => x.uuid == subU)) subs.add(subD);
    }
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
                        child: SegmentedButton<_Mode>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: Theme.of(context).textTheme.titleSmall,
                          ),
                          segments: [
                            ButtonSegment(
                              value: _Mode.stereo,
                              label: Text(context.l10n.groupModeStereo),
                            ),
                            ButtonSegment(
                              value: _Mode.zone,
                              label: Text(context.l10n.groupModeZone),
                            ),
                            ButtonSegment(
                              value: _Mode.custom,
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
                            content: _ReviewStep(
                              mode: _mode,
                              system: system,
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
        _Mode.stereo => i == 0 ? GroupChannel.left : GroupChannel.right,
        _Mode.zone => GroupChannel.both,
        _Mode.custom => _channels[_selected[i]] ?? GroupChannel.both,
      };
      members.add((device: d, channel: channel));
    }
    return members;
  }

  /// True when the current selection would actually change [existing] — so an
  /// unchanged edit disables Apply (no needless re-assert / dissolve).
  bool _differs(SonosSystem system, ZoneGroupMember existing) {
    // Ordered uuid:channel signature captures membership, channels, and (for
    // stereo) the L/R order in one compare.
    final want = [
      for (final m in _members(system)) '${m.device.uuid}:${m.channel.name}',
    ].join(';');
    final have = [
      for (final e in existing.groupChannels.entries) '${e.key}:${e.value.name}',
    ].join(';');
    return want != have ||
        _subUuid != existing.subUuid ||
        _nameController.text.trim() != existing.zoneName;
  }

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
                _Mode.stereo => context.l10n.groupCreateStereo,
                _Mode.zone => context.l10n.groupCreateZone,
                _Mode.custom => context.l10n.groupCreateCustom,
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
  final _Mode mode;
  final List<SonosDevice> candidates;
  final List<String> selected;
  final Map<String, GroupChannel> channels;
  final void Function(String uuid) onToggle;
  final void Function(String uuid, GroupChannel channel) onChannel;
  final VoidCallback onSwap;
  final Widget Function(SonosDevice device) identifyControls;

  const _SelectStep({
    required this.mode,
    required this.candidates,
    required this.selected,
    required this.channels,
    required this.onToggle,
    required this.onChannel,
    required this.onSwap,
    required this.identifyControls,
  });

  String _hint(BuildContext context) => switch (mode) {
    _Mode.stereo => context.l10n.groupHintStereo,
    _Mode.zone => context.l10n.groupHintZone,
    _Mode.custom => context.l10n.groupHintCustom,
  };

  @override
  Widget build(BuildContext context) {
    final cap = mode == _Mode.stereo ? 2 : 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_hint(context), style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        CardGrid([for (final d in candidates) _card(context, d, cap)]),
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
    if (mode == _Mode.custom && isSel) {
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
    } else if (mode == _Mode.stereo && isSel && selected.length == 2) {
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
      subtitle: d.typeLabel,
      identify: identifyControls(d),
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

  const _SubStep({
    required this.subs,
    required this.selected,
    required this.onChanged,
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
          ...subs.map(
            (s) => Card(
              margin: const EdgeInsets.only(bottom: kCardGap),
              clipBehavior: Clip.antiAlias,
              child: CheckboxListTile(
                value: selected == s.uuid,
                onChanged: (v) => onChanged((v ?? false) ? s.uuid : null),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(context.l10n.groupSubwoofer),
                subtitle: Text(s.typeLabel),
                secondary: const Icon(Icons.graphic_eq),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Step 4 — summary + the "large groups can be flaky" nudge.
class _ReviewStep extends StatelessWidget {
  final _Mode mode;
  final SonosSystem system;
  final List<String> selected;
  final Map<String, GroupChannel> channels;
  final String? subUuid;
  final String name;

  const _ReviewStep({
    required this.mode,
    required this.system,
    required this.selected,
    required this.channels,
    required this.subUuid,
    required this.name,
  });

  String _type(BuildContext context, String uuid) =>
      system.device(uuid)?.typeLabel ?? context.l10n.widgetsSpeaker;

  GroupChannel _channelFor(int i) => switch (mode) {
    _Mode.stereo => i == 0 ? GroupChannel.left : GroupChannel.right,
    _Mode.zone => GroupChannel.both,
    _Mode.custom => channels[selected[i]] ?? GroupChannel.both,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.mutedText;
    final l10n = context.l10n;
    final kind = switch (mode) {
      _Mode.stereo => l10n.groupKindStereo,
      _Mode.zone => l10n.groupKindZone(selected.length),
      _Mode.custom => l10n.groupKindCustom(selected.length),
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
        Text(l10n.groupReviewNote, style: muted),
      ],
    );
  }
}
