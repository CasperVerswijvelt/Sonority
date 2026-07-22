import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/identify_controls.dart';
import '../widgets/speaker_side_card.dart';

/// How the segmented control frames the bond. All three build a `ChannelMapSet`
/// and go through the same `AddBondedZones` engine path.
enum _Mode { stereo, zone, custom }

/// Unified "Group speakers" flow: bond 2–16 speakers as a **Stereo** pair, a
/// full-range **Zone**, or a **Custom** per-speaker L/R/Both layout — each with
/// an optional Sub. Stepped (speakers → sub → name → review) like the
/// home-theater setup.
class GroupFlow extends ConsumerStatefulWidget {
  const GroupFlow({super.key});

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

  int get _cap => _mode == _Mode.stereo ? 2 : _maxSpeakers;

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
    final candidates =
        system.zoneableSpeakers.where((d) => d.reachable).toList();
    final subs = system.bondableSubs.where((d) => d.reachable).toList();
    final scheme = Theme.of(context).colorScheme;
    // Candidates here are all standalone, so chime applies; gate per-device
    // anyway so the rule stays consistent with the HT flow.
    Widget idControls(SonosDevice d) =>
        identifyButtons(d, chime: system.isStandalone(d.uuid));

    return Scaffold(
      // No scroll-under elevation: the steps tuck behind the segmented-control
      // header (with its own divider), so a second line under the app bar would
      // double up.
      appBar: AppBar(
        title: Text(context.l10n.groupFlowTitle),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
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
                                label: Text(context.l10n.groupModeStereo)),
                            ButtonSegment(
                                value: _Mode.zone,
                                label: Text(context.l10n.groupModeZone)),
                            ButtonSegment(
                                value: _Mode.custom,
                                label: Text(context.l10n.groupModeCustom)),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => _onModeChanged(s.first),
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: Stepper(
                      currentStep: _step,
                      type: StepperType.vertical,
                      onStepTapped: (i) => setState(() => _step = i),
                      controlsBuilder: (context, _) => _controls(system),
                      steps: [
                        Step(
                          title: Text(context.l10n.groupStepSelect),
                          isActive: _step >= _stepSpeakers,
                          state: _selected.length >= 2
                              ? StepState.complete
                              : StepState.indexed,
                          content: _SelectStep(
                            mode: _mode,
                            system: system,
                            candidates: candidates,
                            selected: _selected,
                            channels: _channels,
                            onToggle: _toggle,
                            onChannel: (u, c) =>
                                setState(() => _channels[u] = c),
                            onSwap: () => setState(() => _selected
                                .setAll(0, [_selected[1], _selected[0]])),
                            identifyControls: idControls,
                          ),
                        ),
                        Step(
                          title: Text(context.l10n.groupStepAddSub),
                          subtitle: Text(context.l10n.groupOptional),
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
                              textCapitalization: TextCapitalization.sentences,
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
                ],
              ),
      ),
    );
  }

  Widget _controls(SonosSystem system) {
    final isLast = _step == _stepReview;
    final canAdvance = _step != _stepSpeakers || _selected.length >= 2;
    final label = isLast
        ? switch (_mode) {
            _Mode.stereo => context.l10n.groupCreateStereo,
            _Mode.zone => context.l10n.groupCreateZone,
            _Mode.custom => context.l10n.groupCreateCustom,
          }
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
                      ? () => _create(system)
                      : () => setState(() => _step++),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(SonosSystem system) async {
    final members = <({SonosDevice device, GroupChannel channel})>[];
    for (final r in _resolveChannels(_mode, _selected, _channels)) {
      final d = system.device(r.uuid);
      if (d == null) continue;
      members.add((device: d, channel: r.channel));
    }
    if (members.length < 2) return;
    final sub = _subUuid == null ? null : system.device(_subUuid!);
    final name = _nameController.text.trim();
    final controller = ref.read(sonosControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final l10n = context.l10n;
    final outcome = await showBondingProgress(
      context,
      title: l10n.groupFlowTitle,
      run: () => controller.createGroup(
          members: members, sub: sub, name: name.isEmpty ? null : name),
    );
    if (outcome == BondingOutcome.success) {
      router.pop();
    } else if (outcome == BondingOutcome.failed) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.groupCreateFailed),
        duration: const Duration(seconds: 6),
      ));
    }
  }
}

/// Each selected speaker's channel for [mode], in selection order. Stereo derives
/// L/R from order; zone is always full-range; custom reads the per-speaker map.
/// The single source of truth for both the review summary and the actual bond.
List<({String uuid, GroupChannel channel})> _resolveChannels(
        _Mode mode, List<String> selected, Map<String, GroupChannel> channels) =>
    [
      for (var i = 0; i < selected.length; i++)
        (
          uuid: selected[i],
          channel: switch (mode) {
            _Mode.stereo => i == 0 ? GroupChannel.left : GroupChannel.right,
            _Mode.zone => GroupChannel.both,
            _Mode.custom => channels[selected[i]] ?? GroupChannel.both,
          },
        ),
    ];

/// Step 1 — pick speakers, with per-mode assignment.
class _SelectStep extends StatelessWidget {
  final _Mode mode;
  final SonosSystem system;
  final List<SonosDevice> candidates;
  final List<String> selected;
  final Map<String, GroupChannel> channels;
  final void Function(String uuid) onToggle;
  final void Function(String uuid, GroupChannel channel) onChannel;
  final VoidCallback onSwap;
  final Widget Function(SonosDevice device) identifyControls;

  const _SelectStep({
    required this.mode,
    required this.system,
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
        Gap.m,
        ...candidates.map((d) {
          final isSel = selected.contains(d.uuid);
          final disabled = !isSel && selected.length >= cap;
          return _CandidateCard(
            device: d,
            selected: isSel,
            enabled: !disabled,
            showChannel: mode == _Mode.custom && isSel,
            channel: channels[d.uuid] ?? GroupChannel.both,
            onToggle: () => onToggle(d.uuid),
            onChannel: (c) => onChannel(d.uuid, c),
            identify: identifyControls(d),
          );
        }),
        if (mode == _Mode.stereo && selected.length == 2) ...[
          Gap.m,
          Row(
            children: [
              Expanded(
                  child: SpeakerSideCard(
                      side: context.l10n.groupSideLeft,
                      device: system.device(selected[0]),
                      controls: identifyControls(system.device(selected[0])!))),
              IconButton.filledTonal(
                onPressed: onSwap,
                icon: const Icon(Icons.swap_horiz),
                tooltip: context.l10n.groupSwapSides,
              ),
              Expanded(
                  child: SpeakerSideCard(
                      side: context.l10n.groupSideRight,
                      device: system.device(selected[1]),
                      controls: identifyControls(system.device(selected[1])!))),
            ],
          ),
        ],
      ],
    );
  }
}

/// A selectable speaker card. The whole card is the tap target (so hover/press
/// highlights all of it); in custom mode a selected card reveals an animated
/// Left/Both/Right control inside it.
class _CandidateCard extends StatelessWidget {
  final SonosDevice device;
  final bool selected;
  final bool enabled;
  final bool showChannel;
  final GroupChannel channel;
  final VoidCallback onToggle;
  final void Function(GroupChannel) onChannel;
  final Widget identify;

  const _CandidateCard({
    required this.device,
    required this.selected,
    required this.enabled,
    required this.showChannel,
    required this.channel,
    required this.onToggle,
    required this.onChannel,
    required this.identify,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: kCardGap),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onToggle : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No onTap: taps fall through to the whole-card InkWell above; the
            // Checkbox + identify button still handle their own taps.
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: Checkbox(
                value: selected,
                onChanged: enabled ? (_) => onToggle() : null,
              ),
              title: Text(device.roomName),
              subtitle: Text(device.typeLabel),
              trailing: identify,
            ),
            // CrossFade (not just AnimatedSize) so the control fades out WHILE
            // the height collapses on deselect, instead of vanishing instantly.
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              crossFadeState: showChannel
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<GroupChannel>(
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
                    selected: {channel},
                    onSelectionChanged: (s) => onChannel(s.first),
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
          Text(
            context.l10n.groupNoSub,
            style: muted,
          )
        else ...[
          Text(context.l10n.groupAddSubHint, style: muted),
          Gap.s,
          ...subs.map((s) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: CheckboxListTile(
                  value: selected == s.uuid,
                  onChanged: (v) => onChanged((v ?? false) ? s.uuid : null),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(context.l10n.groupSubwoofer),
                  subtitle: Text(s.typeLabel),
                  secondary: const Icon(Icons.graphic_eq),
                ),
              )),
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

  String _room(String uuid) => system.device(uuid)?.roomName ?? uuid;

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
    final lines = [
      for (final r in _resolveChannels(mode, selected, channels))
        l10n.groupReviewMemberLine(
          _room(r.uuid),
          switch (r.channel) {
            GroupChannel.left => l10n.groupChannelLeft,
            GroupChannel.right => l10n.groupChannelRight,
            GroupChannel.both => l10n.groupChannelBoth,
          },
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kind, style: theme.textTheme.titleMedium),
        if (name.isNotEmpty) ...[
          Gap.s,
          Text(l10n.groupReviewName(name), style: muted),
        ],
        Gap.s,
        ...lines.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(l, style: muted),
            )),
        if (subUuid != null)
          Text(
              l10n.groupReviewSub(
                  system.device(subUuid!)?.typeLabel ?? l10n.groupSubwoofer),
              style: muted),
        Gap.m,
        Text(
          l10n.groupReviewNote,
          style: muted,
        ),
      ],
    );
  }
}
