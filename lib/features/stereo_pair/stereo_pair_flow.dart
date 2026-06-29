import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bondable_speaker_tile.dart';
import '../widgets/busy_view.dart';
import '../widgets/identify_controls.dart';
import '../widgets/speaker_side_card.dart';

/// Guided, stepped flow to bond two standalone speakers into a stereo pair —
/// including mismatched models the official app won't pair. Mirrors the
/// home-theater setup flow: choose speakers → assign left/right → review & create.
class StereoPairFlow extends ConsumerStatefulWidget {
  const StereoPairFlow({super.key});

  @override
  ConsumerState<StereoPairFlow> createState() => _StereoPairFlowState();
}

class _StereoPairFlowState extends ConsumerState<StereoPairFlow>
    with IdentifyMixin {
  int _step = 0;
  final List<String> _selected = []; // [left, right]
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(sonosControllerProvider).value;
    final candidates = system?.bondableSpeakers ?? const <SonosDevice>[];

    if (system == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_applying) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create stereo pair')),
        body: const SafeArea(
          child: BusyView(
            title: 'Pairing your speakers…',
            subtitle: 'Bonding them and waiting for Sonos to apply the change. '
                'This can take up to ~20 seconds.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create stereo pair')),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          type: StepperType.vertical,
          onStepTapped: (i) => setState(() => _step = i),
          controlsBuilder: (context, _) => _controls(system),
          steps: [
            Step(
              title: const Text('Choose speakers'),
              isActive: _step >= 0,
              state: _selected.length == 2
                  ? StepState.complete
                  : StepState.indexed,
              content: _ChooseSpeakers(
                candidates: candidates,
                selected: _selected,
                onToggle: _toggle,
                identifyControls: identifyButtons,
              ),
            ),
            Step(
              title: const Text('Assign left & right'),
              isActive: _step >= 1,
              content: _selected.length == 2
                  ? _AssignSides(
                      system: system,
                      selected: _selected,
                      onSwap: () => setState(() =>
                          _selected.setAll(0, [_selected[1], _selected[0]])),
                      identifyControls: identifyButtons,
                    )
                  : const Text('Choose two speakers first.'),
            ),
            Step(
              title: const Text('Review & create'),
              isActive: _step >= 2,
              content: _Review(system: system, selected: _selected),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String uuid) => setState(() {
        if (_selected.contains(uuid)) {
          _selected.remove(uuid);
        } else if (_selected.length < 2) {
          _selected.add(uuid);
        }
      });

  Widget _controls(SonosSystem system) {
    final canNext = _step != 0 || _selected.length == 2;
    final isLast = _step == 2;
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
                  ? (_selected.length == 2 ? () => _create(system) : null)
                  : (canNext ? () => setState(() => _step++) : null),
              child: Text(isLast ? 'Create stereo pair' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(SonosSystem system) async {
    final left = system.device(_selected[0]);
    final right = system.device(_selected[1]);
    if (left == null || right == null) return;
    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(sonosControllerProvider.notifier)
          .createStereoPair(left: left, right: right);
      messenger.showSnackBar(SnackBar(
          content: Text('Paired ${left.roomName} + ${right.roomName}.')));
      router.pop();
    } catch (e) {
      if (mounted) setState(() => _applying = false);
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Couldn’t create the pair — Sonos may not allow these two speakers '
            'together. ($e)'),
        duration: const Duration(seconds: 6),
      ));
    }
  }
}

class _ChooseSpeakers extends StatelessWidget {
  final List<SonosDevice> candidates;
  final List<String> selected;
  final void Function(String uuid) onToggle;
  final Widget Function(SonosDevice device) identifyControls;

  const _ChooseSpeakers({
    required this.candidates,
    required this.selected,
    required this.onToggle,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.length < 2) {
      return const Text(
        'Need at least two standalone speakers (not soundbars, subs, or already '
        'bonded).',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick exactly two — mismatched models are allowed.',
            style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        ...candidates.map((d) {
          final isSel = selected.contains(d.uuid);
          final disabled = !isSel && selected.length >= 2;
          return BondableSpeakerTile(
            device: d,
            selected: isSel,
            onChanged: disabled ? null : (_) => onToggle(d.uuid),
            subtitle: d.modelName,
            secondary: identifyControls(d),
          );
        }),
      ],
    );
  }
}

class _AssignSides extends StatelessWidget {
  final SonosSystem system;
  final List<String> selected;
  final VoidCallback onSwap;
  final Widget Function(SonosDevice device) identifyControls;

  const _AssignSides({
    required this.system,
    required this.selected,
    required this.onSwap,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    final left = system.device(selected[0]);
    final right = system.device(selected[1]);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: SpeakerSideCard(
                    side: 'LEFT',
                    device: left,
                    controls: left == null ? null : identifyControls(left))),
            IconButton.filledTonal(
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Swap sides',
            ),
            Expanded(
                child: SpeakerSideCard(
                    side: 'RIGHT',
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
  final List<String> selected;
  const _Review({required this.system, required this.selected});

  @override
  Widget build(BuildContext context) {
    if (selected.length != 2) {
      return const Text('Choose two speakers first.');
    }
    final theme = Theme.of(context);
    final left = system.device(selected[0]);
    final right = system.device(selected[1]);
    final mismatched =
        left != null && right != null && left.modelName != right.modelName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${left?.roomName ?? '?'} (L)  +  ${right?.roomName ?? '?'} (R)',
            style: theme.textTheme.titleMedium),
        Gap.s,
        if (mismatched)
          Text(
            'Mismatched models (${left.modelName} + ${right.modelName}) — '
            'Sonos may reject genuinely incompatible hardware.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
          ),
        Gap.s,
        Text(
          'The right speaker becomes hidden and both rooms merge into the pair. '
          'We save both room names so they’re restored when you unpair.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
