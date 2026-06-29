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

/// Guided flow to bond two standalone speakers into a stereo pair — including
/// mismatched models the official app won't pair (Sonos still validates real
/// hardware compatibility server-side and will reject truly incompatible ones).
class StereoPairFlow extends ConsumerStatefulWidget {
  const StereoPairFlow({super.key});

  @override
  ConsumerState<StereoPairFlow> createState() => _StereoPairFlowState();
}

class _StereoPairFlowState extends ConsumerState<StereoPairFlow>
    with IdentifyMixin {
  final List<String> _selected = []; // [left, right]
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(sonosControllerProvider).value;
    final candidates = system?.bondableSpeakers ?? const <SonosDevice>[];

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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Pick two speakers, then set which is Left/Right.',
                style: Theme.of(context).textTheme.bodyMedium),
            Gap.s,
            ...candidates.map((d) {
              final isSel = _selected.contains(d.uuid);
              final disabled = !isSel && _selected.length >= 2;
              return BondableSpeakerTile(
                device: d,
                selected: isSel,
                onChanged: disabled ? null : (_) => _toggle(d.uuid),
                subtitle: d.modelName,
                secondary: identifyButtons(d),
              );
            }),
            if (candidates.length < 2)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Need at least two standalone speakers (not soundbars, subs, '
                  'or already bonded).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Gap.l,
            if (_selected.length == 2) _assignAndCreate(system!),
          ],
        ),
      ),
    );
  }

  Widget _assignAndCreate(SonosSystem system) {
    final left = system.device(_selected[0]);
    final right = system.device(_selected[1]);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: SpeakerSideCard(
                    side: 'LEFT',
                    device: left,
                    controls: left == null ? null : identifyButtons(left))),
            IconButton.filledTonal(
              onPressed: () =>
                  setState(() => _selected.setAll(0, [_selected[1], _selected[0]])),
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Swap sides',
            ),
            Expanded(
                child: SpeakerSideCard(
                    side: 'RIGHT',
                    device: right,
                    controls: right == null ? null : identifyButtons(right))),
          ],
        ),
        Gap.s,
        if (left != null && right != null && left.modelName != right.modelName)
          Text('Mismatched models — Sonos may reject incompatible hardware.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.tertiary)),
        Gap.m,
        FilledButton.icon(
          onPressed: () => _create(system),
          icon: const Icon(Icons.link),
          label: const Text('Create stereo pair'),
        ),
        Gap.s,
        Text('We’ll save both room names so you can restore them when you unpair.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  void _toggle(String uuid) => setState(() {
        if (_selected.contains(uuid)) {
          _selected.remove(uuid);
        } else if (_selected.length < 2) {
          _selected.add(uuid);
        }
      });

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
