import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        title: const Text('Group speakers'),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: candidates.length < 2
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Need at least two standalone speakers (not soundbars, subs, '
                    'amps, or already bonded).',
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
                          segments: const [
                            ButtonSegment(
                                value: _Mode.stereo, label: Text('Stereo')),
                            ButtonSegment(
                                value: _Mode.zone, label: Text('Zone')),
                            ButtonSegment(
                                value: _Mode.custom, label: Text('Custom')),
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
                          title: const Text('Select speakers'),
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
                          title: const Text('Add a Sub'),
                          subtitle: const Text('Optional'),
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
                          title: const Text('Name'),
                          subtitle: const Text('Optional'),
                          isActive: _step >= _stepName,
                          content: Padding(
                            // Top room for the floating label (else it clips).
                            padding: const EdgeInsets.only(top: 8),
                            child: TextField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Group name (optional)',
                                hintText: 'e.g. Downstairs',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        Step(
                          title: const Text('Review & create'),
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
            _Mode.stereo => 'Create stereo pair',
            _Mode.zone => 'Create zone',
            _Mode.custom => 'Create custom group',
          }
        : 'Continue';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: () => setState(() => _step--),
              child: const Text('Back'),
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
    if (members.length < 2) return;
    final sub = _subUuid == null ? null : system.device(_subUuid!);
    final name = _nameController.text.trim();
    final controller = ref.read(sonosControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final outcome = await showBondingProgress(
      context,
      title: 'Group speakers',
      run: () => controller.createGroup(
          members: members, sub: sub, name: name.isEmpty ? null : name),
    );
    if (outcome == BondingOutcome.success) {
      router.pop();
    } else if (outcome == BondingOutcome.failed) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Couldn’t create the group — Sonos may not allow one of '
            'these speakers. See the log for details.'),
        duration: Duration(seconds: 6),
      ));
    }
  }
}

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

  String get _hint => switch (mode) {
        _Mode.stereo =>
          'Pick two speakers — one plays left, the other right (swap below). '
              'Mismatched models are fine.',
        _Mode.zone =>
          'Pick 2–16 speakers. They all play full stereo (L+R) as one room.',
        _Mode.custom =>
          'Pick 2–16 speakers and set each to Left, Right, or Both.',
      };

  @override
  Widget build(BuildContext context) {
    final cap = mode == _Mode.stereo ? 2 : 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_hint, style: Theme.of(context).textTheme.bodySmall),
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
                      side: 'LEFT',
                      device: system.device(selected[0]),
                      controls: identifyControls(system.device(selected[0])!))),
              IconButton.filledTonal(
                onPressed: onSwap,
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Swap sides',
              ),
              Expanded(
                  child: SpeakerSideCard(
                      side: 'RIGHT',
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
                    segments: const [
                      ButtonSegment(
                          value: GroupChannel.left, label: Text('Left')),
                      ButtonSegment(
                          value: GroupChannel.both, label: Text('Both')),
                      ButtonSegment(
                          value: GroupChannel.right, label: Text('Right')),
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
            'No standalone Sub available. A Sub bonded to a home theater must be '
            'removed there first.',
            style: muted,
          )
        else ...[
          Text('Optionally add a Sub to the group.', style: muted),
          Gap.s,
          ...subs.map((s) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: CheckboxListTile(
                  value: selected == s.uuid,
                  onChanged: (v) => onChanged((v ?? false) ? s.uuid : null),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Subwoofer'),
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
    final kind = switch (mode) {
      _Mode.stereo => 'Stereo pair',
      _Mode.zone => 'Zone (${selected.length} speakers)',
      _Mode.custom => 'Custom group (${selected.length} speakers)',
    };
    final lines = <String>[];
    for (var i = 0; i < selected.length; i++) {
      final ch = switch (mode) {
        _Mode.stereo => i == 0 ? 'Left' : 'Right',
        _Mode.zone => 'Both',
        _Mode.custom => switch (channels[selected[i]] ?? GroupChannel.both) {
            GroupChannel.left => 'Left',
            GroupChannel.right => 'Right',
            GroupChannel.both => 'Both',
          },
      };
      lines.add('${_room(selected[i])} — $ch');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kind, style: theme.textTheme.titleMedium),
        if (name.isNotEmpty) ...[
          Gap.s,
          Text('Name: $name', style: muted),
        ],
        Gap.s,
        ...lines.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(l, style: muted),
            )),
        if (subUuid != null)
          Text('Sub: ${system.device(subUuid!)?.typeLabel ?? 'Subwoofer'}',
              style: muted),
        Gap.m,
        Text(
          'Bonded speakers play as one room. Larger or mixed-model groups can '
          'drop out briefly — play something to confirm it works for you. '
          'Original room names are restored when you separate the group.',
          style: muted,
        ),
      ],
    );
  }
}
