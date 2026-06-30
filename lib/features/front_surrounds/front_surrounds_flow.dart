import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/bondable_speaker_tile.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/identify_controls.dart';
import '../widgets/speaker_diagram.dart';
import '../widgets/speaker_side_card.dart';

/// Guided flow to complete a home-theater layout in-app: dedicated front L/R
/// (two speakers or a single Amp), rear surrounds (L/R), and a sub — each step
/// optional. Applies in stages with live per-step progress (see
/// [SonosController.applyHomeTheaterLayout]).
class FrontSurroundsFlow extends ConsumerStatefulWidget {
  final String soundbarUuid;
  const FrontSurroundsFlow({super.key, required this.soundbarUuid});

  @override
  ConsumerState<FrontSurroundsFlow> createState() => _FrontSurroundsFlowState();
}

class _FrontSurroundsFlowState extends ConsumerState<FrontSurroundsFlow>
    with IdentifyMixin {
  int _step = 0;
  final List<String> _fronts = []; // uuids, order [left, right] (or [amp])
  final List<String> _surrounds = []; // uuids, order [rearLeft, rearRight]
  String? _sub; // uuid

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(sonosControllerProvider).value;
    final member = system?.allMembers
        .where((m) => m.uuid == widget.soundbarUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    final soundbar = system?.device(widget.soundbarUuid);

    if (system == null || member == null || soundbar == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Speakers free to assign, minus ones already chosen in another role here.
    final chosenElsewhere = <String>{..._fronts, ..._surrounds, if (_sub != null) _sub!};
    List<SonosDevice> avail(List<String> keepFor) => system.bondableSpeakers
        .where((d) => keepFor.contains(d.uuid) || !chosenElsewhere.contains(d.uuid))
        .toList();
    final freeSubs = system.bondableSubs;

    return Scaffold(
      appBar: AppBar(title: const Text('Set up home theater')),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          type: StepperType.vertical,
          onStepTapped: (i) => setState(() => _step = i),
          controlsBuilder: (context, _) => _controls(context, member, soundbar),
          steps: [
            Step(
              title: const Text('Front speakers'),
              subtitle: const Text('Optional'),
              isActive: _step >= 0,
              state: _frontsValid && _fronts.isNotEmpty
                  ? StepState.complete
                  : StepState.indexed,
              content: _ChooseSpeakers(
                candidates: avail(_fronts),
                selected: _fronts,
                onToggle: _toggleFront,
                identifyControls: identifyButtons,
              ),
            ),
            Step(
              title: Text(_ampMode ? 'Connect your speakers' : 'Assign left & right'),
              isActive: _step >= 1,
              content: _fronts.isEmpty
                  ? const Text('No front speakers selected — nothing to assign.')
                  : _ampMode
                      ? _AmpWiringNote(
                          amp: system.device(_fronts.first),
                          onIdentify: identify,
                          onChime: onChime,
                          identifying: identifyingUuid,
                        )
                      : _AssignSides(
                          system: system,
                          selected: _fronts,
                          leftLabel: 'LEFT',
                          rightLabel: 'RIGHT',
                          onSwap: () => setState(() =>
                              _fronts.setAll(0, [_fronts[1], _fronts[0]])),
                          identifyControls: identifyButtons,
                        ),
            ),
            Step(
              title: const Text('Rear surrounds'),
              subtitle: const Text('Optional'),
              isActive: _step >= 2,
              state: _surrounds.length == 2 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pick two speakers for the rear left & right surrounds.',
                      style: Theme.of(context).textTheme.bodySmall),
                  Gap.s,
                  _ChooseSpeakers(
                    candidates: avail(_surrounds),
                    selected: _surrounds,
                    onToggle: _toggleSurround,
                    identifyControls: identifyButtons,
                    allowAmp: false,
                  ),
                  if (_surrounds.length == 2) ...[
                    Gap.m,
                    _AssignSides(
                      system: system,
                      selected: _surrounds,
                      leftLabel: 'REAR LEFT',
                      rightLabel: 'REAR RIGHT',
                      onSwap: () => setState(() =>
                          _surrounds.setAll(0, [_surrounds[1], _surrounds[0]])),
                      identifyControls: identifyButtons,
                    ),
                  ],
                ],
              ),
            ),
            Step(
              title: const Text('Subwoofer'),
              subtitle: const Text('Optional'),
              isActive: _step >= 3,
              state: _sub != null ? StepState.complete : StepState.indexed,
              content: _ChooseSub(
                subs: freeSubs,
                selected: _sub,
                onToggle: (d) => setState(() => _sub = _sub == d.uuid ? null : d.uuid),
                identifyControls: identifyButtons,
              ),
            ),
            Step(
              title: const Text('Review & apply'),
              isActive: _step >= 4,
              content: _Review(system: system, member: member, additions: _additions(system)),
            ),
          ],
        ),
      ),
    );
  }

  bool _deviceIsAmp(String uuid) =>
      ref.read(sonosControllerProvider).value?.device(uuid)?.isAmp ?? false;

  bool get _ampMode => _fronts.length == 1 && _deviceIsAmp(_fronts.first);
  bool get _frontsValid => _fronts.isEmpty || _fronts.length == 2 || _ampMode;
  bool get _surroundsValid => _surrounds.isEmpty || _surrounds.length == 2;
  bool get _anyChosen =>
      (_fronts.length == 2 || _ampMode) || _surrounds.length == 2 || _sub != null;
  bool get _canApply => _anyChosen && _frontsValid && _surroundsValid;

  void _toggleFront(SonosDevice d) => setState(() {
        if (_fronts.contains(d.uuid)) {
          _fronts.remove(d.uuid);
          return;
        }
        if (d.isAmp) {
          _fronts
            ..clear()
            ..add(d.uuid);
          return;
        }
        if (_ampMode) _fronts.clear();
        if (_fronts.length < 2) _fronts.add(d.uuid);
      });

  void _toggleSurround(SonosDevice d) => setState(() {
        if (_surrounds.contains(d.uuid)) {
          _surrounds.remove(d.uuid);
        } else if (_surrounds.length < 2) {
          _surrounds.add(d.uuid);
        }
      });

  /// The role → speaker map this flow will bond.
  Map<SonosChannel, SonosDevice> _additions(SonosSystem system) {
    final out = <SonosChannel, SonosDevice>{};
    SonosDevice? dev(String uuid) => system.device(uuid);
    if (_ampMode) {
      final amp = dev(_fronts.first);
      if (amp != null) {
        out[SonosChannel.leftFront] = amp;
        out[SonosChannel.rightFront] = amp;
      }
    } else if (_fronts.length == 2) {
      final l = dev(_fronts[0]), r = dev(_fronts[1]);
      if (l != null && r != null) {
        out[SonosChannel.leftFront] = l;
        out[SonosChannel.rightFront] = r;
      }
    }
    if (_surrounds.length == 2) {
      final l = dev(_surrounds[0]), r = dev(_surrounds[1]);
      if (l != null && r != null) {
        out[SonosChannel.leftRear] = l;
        out[SonosChannel.rightRear] = r;
      }
    }
    final sub = _sub;
    if (sub != null) {
      final s = dev(sub);
      if (s != null) out[SonosChannel.sub] = s;
    }
    return out;
  }

  Widget _controls(
      BuildContext context, ZoneGroupMember member, SonosDevice soundbar) {
    final canNext = switch (_step) {
      0 => _frontsValid,
      2 => _surroundsValid,
      _ => true,
    };
    final isLast = _step == 4;
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
              onPressed: isLast
                  ? (_canApply ? () => _apply(member, soundbar) : null)
                  : (canNext ? () => setState(() => _step++) : null),
              child: Text(isLast ? 'Apply' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(ZoneGroupMember member, SonosDevice soundbar) async {
    final system = ref.read(sonosControllerProvider).value;
    if (system == null) return;
    final additions = _additions(system);
    if (additions.isEmpty) return;

    final controller = ref.read(sonosControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final outcome = await showBondingProgress(
      context,
      title: 'Set up home theater',
      run: () => controller.applyHomeTheaterLayout(
        soundbar: member,
        soundbarDevice: soundbar,
        additions: additions,
      ),
    );
    if (outcome == BondingOutcome.success) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Home theater updated!')));
      router.pop();
    }
  }
}

class _ChooseSpeakers extends StatelessWidget {
  final List<SonosDevice> candidates;
  final List<String> selected;
  final void Function(SonosDevice device) onToggle;
  final Widget Function(SonosDevice device) identifyControls;
  final bool allowAmp;

  const _ChooseSpeakers({
    required this.candidates,
    required this.selected,
    required this.onToggle,
    required this.identifyControls,
    this.allowAmp = true,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const Text(
        'No free speakers available. They must be standalone (not already part '
        'of a home theater or stereo pair).',
      );
    }
    final hasAmp = allowAmp && candidates.any((d) => d.isAmp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            hasAmp
                ? 'Pick two speakers (ideally identical), or a single Sonos Amp '
                    'that drives both front speakers.'
                : 'Pick exactly two — ideally an identical pair.',
            style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        ...candidates.map((d) {
          final isSel = selected.contains(d.uuid);
          final isAmp = allowAmp && d.isAmp;
          final disabled = !isSel && !isAmp && selected.length >= 2;
          return BondableSpeakerTile(
            device: d,
            selected: isSel,
            onChanged: disabled ? null : (_) => onToggle(d),
            subtitle: isAmp
                ? '${d.typeLabel} — drives both fronts (L + R)'
                : d.typeLabel,
            secondary: identifyControls(d),
          );
        }),
      ],
    );
  }
}

class _ChooseSub extends StatelessWidget {
  final List<SonosDevice> subs;
  final String? selected;
  final void Function(SonosDevice device) onToggle;
  final Widget Function(SonosDevice device) identifyControls;

  const _ChooseSub({
    required this.subs,
    required this.selected,
    required this.onToggle,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    if (subs.isEmpty) {
      return const Text(
          'No free subwoofer found. A Sonos Sub must be standalone (not already '
          'bonded to another home theater).');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick a subwoofer to add as the low-frequency channel.',
            style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        ...subs.map((d) => BondableSpeakerTile(
              device: d,
              selected: selected == d.uuid,
              onChanged: (_) => onToggle(d),
              subtitle: d.typeLabel,
              secondary: identifyControls(d),
            )),
      ],
    );
  }
}

/// Amp mode: the Amp drives both fronts itself — nothing to assign in-app.
class _AmpWiringNote extends StatelessWidget {
  final SonosDevice? amp;
  final void Function(SonosDevice device) onIdentify;
  final Future<void> Function(SonosDevice device)? onChime;
  final String? identifying;

  const _AmpWiringNote({
    required this.amp,
    required this.onIdentify,
    required this.onChime,
    required this.identifying,
  });

  @override
  Widget build(BuildContext context) {
    final amp = this.amp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The ${amp?.modelName ?? 'Amp'} drives both front channels. Wire your '
          'left & right speakers to its L/R speaker outputs — there\'s nothing '
          'to assign here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (amp != null) ...[
          Gap.s,
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: identifying == amp.uuid ? null : () => onIdentify(amp),
                icon: identifying == amp.uuid
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.lightbulb_outline, size: 18),
                label: Text('Blink ${amp.roomName}'),
              ),
              if (onChime != null)
                TextButton.icon(
                  onPressed:
                      identifying == amp.uuid ? null : () => onChime!(amp),
                  icon: const Icon(Icons.volume_up_outlined, size: 18),
                  label: const Text('Chime'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AssignSides extends StatelessWidget {
  final SonosSystem system;
  final List<String> selected;
  final String leftLabel;
  final String rightLabel;
  final VoidCallback onSwap;
  final Widget Function(SonosDevice device) identifyControls;

  const _AssignSides({
    required this.system,
    required this.selected,
    required this.leftLabel,
    required this.rightLabel,
    required this.onSwap,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    if (selected.length != 2) {
      return const Text('Choose two speakers first.');
    }
    final left = system.device(selected[0]);
    final right = system.device(selected[1]);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: SpeakerSideCard(
                    side: leftLabel,
                    device: left,
                    controls: left == null ? null : identifyControls(left))),
            IconButton.filledTonal(
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Swap sides',
            ),
            Expanded(
                child: SpeakerSideCard(
                    side: rightLabel,
                    device: right,
                    controls: right == null ? null : identifyControls(right))),
          ],
        ),
        Gap.s,
        Text('Tap swap if the sides are reversed.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  final SonosSystem system;
  final ZoneGroupMember member;
  final Map<SonosChannel, SonosDevice> additions;
  const _Review(
      {required this.system, required this.member, required this.additions});

  @override
  Widget build(BuildContext context) {
    if (additions.isEmpty) {
      return const Text('Nothing selected yet — choose speakers above.');
    }
    // Final layout = what's already bonded, overlaid with the new picks.
    String? label(SonosChannel ch) =>
        additions[ch]?.roomName ?? labelForChannel(system, member, ch);
    final hasSub =
        additions.containsKey(SonosChannel.sub) || hasChannel(member, SonosChannel.sub);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpeakerDiagram(
          soundbarLabel: system.device(member.uuid)?.typeLabel,
          frontLeftLabel: label(SonosChannel.leftFront),
          frontRightLabel: label(SonosChannel.rightFront),
          rearLeftLabel: label(SonosChannel.leftRear),
          rearRightLabel: label(SonosChannel.rightRear),
          hasSub: hasSub,
        ),
        Gap.m,
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary),
                Gap.m,
                Expanded(
                  child: Text(
                    'The chosen speakers become hidden satellites of the '
                    'soundbar (which stays the center channel). Bonding runs in '
                    'steps and can take a little while; Trueplay may need '
                    're-tuning afterward. You can change this anytime.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
