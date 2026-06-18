import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';

/// Entry screen: scan the LAN and present the system, leading with anything
/// that can host dedicated front speakers (soundbars).
class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sonosControllerProvider);
    final controller = ref.read(sonosControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sonority'),
        actions: [
          // Only when there's a discovered system to refresh; the intro/error
          // states use their own CTA buttons to scan.
          if (state.value != null)
            IconButton(
              tooltip: 'Rescan',
              onPressed: state.isLoading ? null : controller.scan,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: state.when(
          loading: () => const _Centered(child: _Scanning()),
          error: (e, _) => _ErrorView(message: '$e', onRetry: controller.scan),
          data: (system) => system == null
              ? _Intro(onScan: controller.scan)
              : _SystemView(system: system, onRescan: controller.scan),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final VoidCallback onScan;
  const _Intro({required this.onScan});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Icon(Icons.speaker_group_outlined, size: 88, color: scheme.primary),
          Gap.l,
          Text('Unlock dedicated front speakers',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          Gap.s,
          Text(
            'Add discrete front left & right speakers to your Sonos home '
            'theater — a setup the official app won’t let you create.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.wifi_find),
            label: const Text('Find my Sonos system'),
          ),
          Gap.s,
          Text(
            'Make sure your phone is on the same Wi‑Fi as your speakers.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Gap.m,
        ],
      ),
    );
  }
}

class _SystemView extends StatelessWidget {
  final SonosSystem system;
  final VoidCallback onRescan;
  const _SystemView({required this.system, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    // Soundbars (whether or not they already have surrounds) are the targets.
    final theaters = system.allMembers
        .where((m) => m.isHomeTheater || (system.device(m.uuid)?.isSoundbar ?? false))
        .toList();
    final otherRooms = system.allMembers
        .where((m) => !theaters.contains(m))
        .toList();

    return RefreshIndicator(
      onRefresh: () async => onRescan(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Home theaters', Icons.theaters_outlined),
          if (theaters.isEmpty)
            const _EmptyHint(
              'No soundbar found. Dedicated fronts need an Arc, Beam, Ray, '
              'Playbar or Playbase.',
            ),
          ...theaters.map((m) => _TheaterCard(system: system, member: m)),
          Gap.l,
          _SectionHeader('Other rooms', Icons.meeting_room_outlined),
          ...otherRooms.map((m) => ListTile(
                leading: const Icon(Icons.speaker_outlined),
                title: Text(m.zoneName),
                subtitle: Text(system.device(m.uuid)?.modelName ?? ''),
              )),
        ],
      ),
    );
  }
}

class _TheaterCard extends StatelessWidget {
  final SonosSystem system;
  final ZoneGroupMember member;
  const _TheaterCard({required this.system, required this.member});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = system.device(member.uuid);
    final hasFronts = member.hasDedicatedFronts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/theater/${member.uuid}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.surround_sound,
                      color: scheme.onPrimaryContainer),
                ),
                Gap.m,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.zoneName,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(device?.modelName ?? 'Soundbar',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant)),
                      Gap.xs,
                      _StatusPill(hasFronts: hasFronts),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool hasFronts;
  const _StatusPill({required this.hasFronts});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hasFronts ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        hasFronts ? 'Dedicated fronts active' : 'No dedicated fronts',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          Gap.s,
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Scanning extends StatelessWidget {
  const _Scanning();
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          Gap.l,
          Text('Scanning your network…',
              style: Theme.of(context).textTheme.titleMedium),
        ],
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 64, color: scheme.error),
          Gap.m,
          Text('Couldn’t find your system',
              style: Theme.of(context).textTheme.titleLarge),
          Gap.s,
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          Gap.l,
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});
  @override
  Widget build(BuildContext context) => Center(child: child);
}
