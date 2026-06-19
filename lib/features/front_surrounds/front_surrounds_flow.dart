import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/identify_service.dart';
import '../../state/sonos_controller.dart';
import '../widgets/busy_view.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/speaker_diagram.dart';

/// Guided 3-step flow to bond two speakers as dedicated front L/R.
class FrontSurroundsFlow extends ConsumerStatefulWidget {
  final String soundbarUuid;
  const FrontSurroundsFlow({super.key, required this.soundbarUuid});

  @override
  ConsumerState<FrontSurroundsFlow> createState() => _FrontSurroundsFlowState();
}

class _FrontSurroundsFlowState extends ConsumerState<FrontSurroundsFlow> {
  int _step = 0;
  final List<String> _selected = []; // uuids, order = [left, right]
  bool _applying = false;
  String? _identifying; // uuid currently chiming, for a spinner

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(sonosControllerProvider).value;
    final member = system?.allMembers
        .where((m) => m.uuid == widget.soundbarUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    final soundbar = system?.device(widget.soundbarUuid);
    final candidates = system?.bondableSpeakers ?? const <SonosDevice>[];

    if (system == null || member == null || soundbar == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_applying) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add front speakers')),
        body: const SafeArea(
          child: BusyView(
            title: 'Setting up your front speakers…',
            subtitle:
                'Bonding them to the soundbar and waiting for Sonos to apply '
                'the new layout. This can take up to ~20 seconds.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add front speakers')),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          type: StepperType.vertical,
          onStepTapped: _applying ? null : (i) => setState(() => _step = i),
          controlsBuilder: (context, details) => _controls(
            context,
            member: member,
            soundbar: soundbar,
            candidates: candidates,
          ),
          steps: [
            Step(
              title: const Text('Choose two speakers'),
              isActive: _step >= 0,
              state: _selected.length == 2 ? StepState.complete : StepState.indexed,
              content: _ChooseSpeakers(
                candidates: candidates,
                selected: _selected,
                onToggle: _toggle,
                onIdentify: _identify,
                identifying: _identifying,
              ),
            ),
            Step(
              title: const Text('Assign left & right'),
              isActive: _step >= 1,
              content: _AssignSides(
                system: system,
                selected: _selected,
                onSwap: () => setState(
                    () => _selected.setAll(0, [_selected[1], _selected[0]])),
                onIdentify: _identify,
                identifying: _identifying,
              ),
            ),
            Step(
              title: const Text('Review & apply'),
              isActive: _step >= 2,
              content: _Review(
                  system: system, member: member, selected: _selected),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String uuid) {
    setState(() {
      if (_selected.contains(uuid)) {
        _selected.remove(uuid);
      } else if (_selected.length < 2) {
        _selected.add(uuid);
      }
    });
  }

  /// Plays a chime on a speaker so the user can identify which box it is.
  Future<void> _identify(SonosDevice device) async {
    final messenger = ScaffoldMessenger.of(context);
    final ip = device.ip;
    if (ip == null) {
      messenger.showSnackBar(
          SnackBar(content: Text('No address for ${device.roomName}.')));
      return;
    }
    setState(() => _identifying = device.uuid);
    messenger.showSnackBar(SnackBar(
      content: Text('🔊 Playing a chime on ${device.roomName}…'),
      duration: const Duration(seconds: 2),
    ));
    try {
      await ref.read(identifyServiceProvider).chirp(ip);
    } on SpeakerUnreachable catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('$e'),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Couldn’t play on ${device.roomName}: $e')));
    } finally {
      if (mounted) setState(() => _identifying = null);
    }
  }

  Widget _controls(
    BuildContext context, {
    required ZoneGroupMember member,
    required SonosDevice soundbar,
    required List<SonosDevice> candidates,
  }) {
    final canNext = switch (_step) {
      0 => _selected.length == 2,
      1 => true,
      _ => true,
    };
    final isLast = _step == 2;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: _applying ? null : () => setState(() => _step--),
              child: const Text('Back'),
            ),
          Gap.s,
          Expanded(
            child: FilledButton(
              onPressed: !canNext || _applying
                  ? null
                  : isLast
                      ? () => _apply(member, soundbar)
                      : () => setState(() => _step++),
              child: _applying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isLast ? 'Apply' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(ZoneGroupMember member, SonosDevice soundbar) async {
    final system = ref.read(sonosControllerProvider).value;
    if (system == null) return;
    final left = system.device(_selected[0]);
    final right = system.device(_selected[1]);
    if (left == null || right == null) return;

    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(sonosControllerProvider.notifier).applyDedicatedFronts(
            soundbar: member,
            soundbarDevice: soundbar,
            leftSpeaker: left,
            rightSpeaker: right,
          );
      messenger.showSnackBar(
          const SnackBar(content: Text('Dedicated front speakers added!')));
      router.pop();
    } catch (e) {
      if (mounted) setState(() => _applying = false);
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class _ChooseSpeakers extends StatelessWidget {
  final List<SonosDevice> candidates;
  final List<String> selected;
  final void Function(String uuid) onToggle;
  final void Function(SonosDevice device) onIdentify;
  final String? identifying;

  const _ChooseSpeakers({
    required this.candidates,
    required this.selected,
    required this.onToggle,
    required this.onIdentify,
    required this.identifying,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const Text(
        'No free speakers found to use as fronts. They must be standalone '
        '(not already part of a home theater or stereo pair).',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick exactly two — ideally an identical pair.',
            style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        ...candidates.map((d) {
          final isSel = selected.contains(d.uuid);
          final disabled = !isSel && selected.length >= 2;
          return CheckboxListTile(
            value: isSel,
            onChanged: disabled ? null : (_) => onToggle(d.uuid),
            title: Text(d.roomName),
            subtitle: Text(d.modelName),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: _IdentifyButton(
              busy: identifying == d.uuid,
              onPressed: () => onIdentify(d),
            ),
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
  final void Function(SonosDevice device) onIdentify;
  final String? identifying;

  const _AssignSides({
    required this.system,
    required this.selected,
    required this.onSwap,
    required this.onIdentify,
    required this.identifying,
  });

  @override
  Widget build(BuildContext context) {
    if (selected.length != 2) {
      return const Text('Go back and choose two speakers first.');
    }
    final left = system.device(selected[0]);
    final right = system.device(selected[1]);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _sideCard(context, 'LEFT', left)),
            IconButton.filledTonal(
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Swap sides',
            ),
            Expanded(child: _sideCard(context, 'RIGHT', right)),
          ],
        ),
        Gap.s,
        Text('Tap swap if the sides are reversed.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _sideCard(BuildContext context, String side, SonosDevice? d) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(side,
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
            Gap.s,
            Icon(Icons.speaker, color: scheme.onSurfaceVariant),
            Gap.xs,
            Text(d?.roomName ?? '—',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge),
            if (d != null) ...[
              Gap.xs,
              TextButton.icon(
                onPressed: () => onIdentify(d),
                icon: identifying == d.uuid
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.volume_up_outlined, size: 18),
                label: const Text('Identify'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A speaker-icon button that plays a chime to identify a speaker.
class _IdentifyButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;
  const _IdentifyButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Play a test chime',
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.volume_up_outlined),
    );
  }
}

class _Review extends StatelessWidget {
  final SonosSystem system;
  final ZoneGroupMember member;
  final List<String> selected;
  const _Review(
      {required this.system, required this.member, required this.selected});

  @override
  Widget build(BuildContext context) {
    if (selected.length != 2) {
      return const Text('Selection incomplete.');
    }
    final left = system.device(selected[0]);
    final right = system.device(selected[1]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Shows the full resulting layout: the new fronts plus the existing
        // rears and sub that stay bonded.
        SpeakerDiagram(
          frontLeftLabel: left?.roomName,
          frontRightLabel: right?.roomName,
          rearLeftLabel: labelForChannel(system, member, SonosChannel.leftRear),
          rearRightLabel:
              labelForChannel(system, member, SonosChannel.rightRear),
          hasSub: hasChannel(member, SonosChannel.sub),
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
                    'The two speakers become hidden satellites of the soundbar, '
                    'which switches to the center channel. You can remove them '
                    'again anytime.',
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
