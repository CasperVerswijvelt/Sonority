import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bondable_speaker_tile.dart';
import '../widgets/busy_view.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/identify_controls.dart';
import '../widgets/speaker_diagram.dart';
import '../widgets/speaker_side_card.dart';

/// Guided 3-step flow to bond two speakers as dedicated front L/R.
class FrontSurroundsFlow extends ConsumerStatefulWidget {
  final String soundbarUuid;
  const FrontSurroundsFlow({super.key, required this.soundbarUuid});

  @override
  ConsumerState<FrontSurroundsFlow> createState() => _FrontSurroundsFlowState();
}

class _FrontSurroundsFlowState extends ConsumerState<FrontSurroundsFlow>
    with IdentifyMixin {
  int _step = 0;
  final List<String> _selected = []; // uuids, order = [left, right]
  bool _applying = false;

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
              title: const Text('Choose front speakers'),
              isActive: _step >= 0,
              state: _frontsChosen ? StepState.complete : StepState.indexed,
              content: _ChooseSpeakers(
                candidates: candidates,
                selected: _selected,
                onToggle: _toggle,
                identifyControls: identifyButtons,
              ),
            ),
            Step(
              title: Text(_ampMode ? 'Connect your speakers' : 'Assign left & right'),
              isActive: _step >= 1,
              content: _ampMode
                  ? _AmpWiringNote(
                      amp: system.device(_selected.first),
                      onIdentify: identify,
                      onChime: onChime,
                      identifying: identifyingUuid,
                    )
                  : _AssignSides(
                      system: system,
                      selected: _selected,
                      onSwap: () => setState(
                          () => _selected.setAll(0, [_selected[1], _selected[0]])),
                      identifyControls: identifyButtons,
                    ),
            ),
            Step(
              title: const Text('Review & apply'),
              isActive: _step >= 2,
              content: _Review(
                  system: system,
                  member: member,
                  selected: _selected,
                  ampMode: _ampMode),
            ),
          ],
        ),
      ),
    );
  }

  bool _deviceIsAmp(String uuid) =>
      ref.read(sonosControllerProvider).value?.device(uuid)?.isAmp ?? false;

  /// A single Amp was chosen — it drives both front channels on its own.
  bool get _ampMode => _selected.length == 1 && _deviceIsAmp(_selected.first);

  /// Step 0 is satisfied by two regular speakers OR a single Amp.
  bool get _frontsChosen => _selected.length == 2 || _ampMode;

  void _toggle(SonosDevice d) {
    setState(() {
      if (_selected.contains(d.uuid)) {
        _selected.remove(d.uuid);
        return;
      }
      if (d.isAmp) {
        // An Amp drives both fronts — exclusive, single selection.
        _selected
          ..clear()
          ..add(d.uuid);
        return;
      }
      // Picking a regular speaker clears a previously selected Amp.
      if (_ampMode) _selected.clear();
      if (_selected.length < 2) _selected.add(d.uuid);
    });
  }

  Widget _controls(
    BuildContext context, {
    required ZoneGroupMember member,
    required SonosDevice soundbar,
    required List<SonosDevice> candidates,
  }) {
    final canNext = switch (_step) {
      0 => _frontsChosen,
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
    final controller = ref.read(sonosControllerProvider.notifier);
    final ampMode = _ampMode;

    final SonosDevice? amp = ampMode ? system.device(_selected.first) : null;
    final SonosDevice? left = ampMode ? null : system.device(_selected[0]);
    final SonosDevice? right = ampMode ? null : system.device(_selected[1]);
    if (ampMode ? amp == null : (left == null || right == null)) return;

    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      if (ampMode) {
        await controller.applyAmpFronts(
          soundbar: member,
          soundbarDevice: soundbar,
          ampDevice: amp!,
        );
      } else {
        await controller.applyDedicatedFronts(
          soundbar: member,
          soundbarDevice: soundbar,
          leftSpeaker: left!,
          rightSpeaker: right!,
        );
      }
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
  final void Function(SonosDevice device) onToggle;
  final Widget Function(SonosDevice device) identifyControls;

  const _ChooseSpeakers({
    required this.candidates,
    required this.selected,
    required this.onToggle,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const Text(
        'No free speakers found to use as fronts. They must be standalone '
        '(not already part of a home theater or stereo pair).',
      );
    }
    final hasAmp = candidates.any((d) => d.isAmp);
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
          // An Amp is always selectable (it switches to single-box mode);
          // regular speakers are capped at two.
          final disabled = !isSel && !d.isAmp && selected.length >= 2;
          return BondableSpeakerTile(
            device: d,
            selected: isSel,
            onChanged: disabled ? null : (_) => onToggle(d),
            subtitle: d.isAmp
                ? '${d.modelName} — drives both fronts (L + R)'
                : d.modelName,
            secondary: identifyControls(d),
          );
        }),
      ],
    );
  }
}

/// Shown in amp mode in place of the L/R assignment step: the Amp handles both
/// front channels itself, so there are no sides to assign in the app — the user
/// wires their passive speakers to the Amp's left/right outputs.
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
    if (selected.length != 2) {
      return const Text('Go back and choose two speakers first.');
    }
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
  final ZoneGroupMember member;
  final List<String> selected;
  final bool ampMode;
  const _Review(
      {required this.system,
      required this.member,
      required this.selected,
      required this.ampMode});

  @override
  Widget build(BuildContext context) {
    if (ampMode ? selected.length != 1 : selected.length != 2) {
      return const Text('Selection incomplete.');
    }
    // In amp mode a single device drives both fronts.
    final left = system.device(selected[0]);
    final right = ampMode ? left : system.device(selected[1]);
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
                    ampMode
                        ? 'The Amp becomes a hidden satellite driving both front '
                            'channels, and the soundbar switches to the center '
                            'channel. You can remove it again anytime.'
                        : 'The two speakers become hidden satellites of the '
                            'soundbar, which switches to the center channel. You '
                            'can remove them again anytime.',
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
