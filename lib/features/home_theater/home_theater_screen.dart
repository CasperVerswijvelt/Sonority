import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/busy_view.dart';
import '../widgets/diagram_labels.dart';
import '../widgets/speaker_diagram.dart';
import '../widgets/trueplay_control.dart';

/// Shows one home theater's current layout and the add/remove-fronts actions.
class HomeTheaterScreen extends ConsumerWidget {
  final String soundbarUuid;
  const HomeTheaterScreen({super.key, required this.soundbarUuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sonosControllerProvider);
    final controller = ref.read(sonosControllerProvider.notifier);
    final system = state.value;

    final member = system?.allMembers
        .where((m) => m.uuid == soundbarUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    final device = system?.device(soundbarUuid);

    return Scaffold(
      appBar: AppBar(
        title: Text(member?.zoneName ?? 'Home theater'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isLoading ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: state.isLoading
            ? const BusyView(
                title: 'Updating your home theater…',
                subtitle:
                    'This can take up to ~20 seconds while Sonos reconfigures '
                    'and re-reads the layout.',
              )
            : (member == null || device == null)
                ? _missing(context)
                : _Content(
                    system: system!,
                    member: member,
                    device: device,
                    onRemove: () => _confirmRemove(context, ref, member, device),
                    onAdd: () => context.push('/theater/$soundbarUuid/fronts'),
                    onRefresh: controller.refresh,
                  ),
      ),
    );
  }

  Widget _missing(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline, size: 56),
              Gap.m,
              const Text('This room is no longer available. Rescan to refresh.'),
              Gap.l,
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to scan'),
              ),
            ],
          ),
        ),
      );

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ZoneGroupMember member,
    SonosDevice device,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.link_off),
        title: const Text('Remove front speakers?'),
        content: const Text(
          'Your front speakers will be un-bonded and become standalone rooms '
          'again. Your soundbar, rear surrounds and sub stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sonosControllerProvider.notifier).removeDedicatedFronts(
            soundbar: member,
            soundbarDevice: device,
          );
      messenger.showSnackBar(
          const SnackBar(content: Text('Front speakers removed.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class _Content extends StatelessWidget {
  final SonosSystem system;
  final ZoneGroupMember member;
  final SonosDevice device;
  final VoidCallback onRemove;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;

  const _Content({
    required this.system,
    required this.member,
    required this.device,
    required this.onRemove,
    required this.onAdd,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final hasFronts = member.hasDedicatedFronts;
    // Every bonded native member (bar + fronts + rears + sub); an Amp used as
    // fronts is excluded — Sonos can't Trueplay it. Toggling all of them is what
    // engages the separately-tuned fronts (see CLAUDE.md / docs).
    final bonded = <String>{member.uuid, ...member.channelAssignments.values}
        .map((u) => system.device(u))
        .whereType<SonosDevice>()
        .where((d) => !d.isAmp)
        .toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SpeakerDiagram(
            frontLeftLabel: labelForChannel(system, member, SonosChannel.leftFront),
            frontRightLabel:
                labelForChannel(system, member, SonosChannel.rightFront),
            rearLeftLabel: labelForChannel(system, member, SonosChannel.leftRear),
            rearRightLabel:
                labelForChannel(system, member, SonosChannel.rightRear),
            hasSub: hasChannel(member, SonosChannel.sub),
          ),
          Gap.l,
          Text(device.modelName, style: Theme.of(context).textTheme.titleMedium),
          Text(
            hasFronts
                ? 'Dedicated front left & right speakers are active.'
                : 'No dedicated front speakers yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Gap.l,
          if (hasFronts)
            FilledButton.tonalIcon(
              onPressed: onRemove,
              icon: const Icon(Icons.link_off),
              label: const Text('Remove front speakers'),
            )
          else
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_link),
              label: const Text('Add dedicated front speakers'),
            ),
          Gap.l,
          TrueplayControl(devices: bonded),
          if (hasFronts) ...[
            Gap.s,
            Text(
              'Trueplay is set up once in the Sonos app (iOS): tune this home '
              'theater, and tune the front speakers separately as a stereo pair '
              '(their tuning isn’t included when fronts are bonded this way). '
              'Sonority only switches the stored result on/off.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          Gap.m,
          Text(
            'Tip: tap the refresh icon after Sonos finishes reconfiguring.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
