import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bondable_speaker_tile.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/collapsing_scaffold.dart';
import '../widgets/diagram_labels.dart';

/// Entry screen: auto-scans the LAN on launch and presents the system, leading
/// with anything that can host dedicated front speakers (soundbars).
class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sonosControllerProvider);
    final controller = ref.read(sonosControllerProvider.notifier);

    final branch = state.isLoading
        ? 'scanning'
        : state.hasError
            ? 'error'
            : 'system';
    final content = state.when(
      loading: () => const Center(child: _Scanning()),
      error: (e, _) => _ErrorView(message: '$e', onRetry: controller.scan),
      // discover() throws on an empty network, so data is never null here;
      // fall back to the spinner defensively rather than crash.
      data: (system) => system == null
          ? const Center(child: _Scanning())
          : _SystemView(system: system),
    );

    return CollapsingScaffold(
      title: 'Sonority',
      titleWidget: Image.asset(
        'assets/brand/sonority_wordmark.png',
        height: 18,
        // White glyphs on alpha → default srcIn tint recolors them to the
        // theme text colour, so the one asset works in light and dark.
        color: Theme.of(context).colorScheme.onSurface,
      ),
      onRefresh: state.value != null ? () => controller.scan() : null,
      actions: [
        // Only when there's a discovered system to refresh; the error state
        // uses its own CTA button to scan.
        if (state.value != null)
          IconButton(
            tooltip: 'Rescan',
            onPressed: state.isLoading ? null : controller.scan,
            icon: const Icon(Icons.refresh),
          ),
      ],
      // One CustomScrollView: the collapsing app bar (in the scaffold) and this
      // body scroll together. hasScrollBody:false sizes the body by its
      // intrinsic height — short content fills + centers (and re-centers as the
      // title collapses), a long list reports a tall height and scrolls via the
      // outer view (no nested scroll). The depth (shared-axis Z) transition
      // wraps only the body, so the app bar itself never animates.
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: PageTransitionSwitcher(
            duration: const Duration(milliseconds: 250),
            reverse: state.isLoading,
            transitionBuilder: (child, anim, secondaryAnim) =>
                SharedAxisTransition(
              animation: anim,
              secondaryAnimation: secondaryAnim,
              transitionType: SharedAxisTransitionType.scaled,
              fillColor: Colors.transparent,
              child: child,
            ),
            child: KeyedSubtree(key: ValueKey(branch), child: content),
          ),
        ),
      ],
    );
  }
}

class _SystemView extends ConsumerWidget {
  final SonosSystem system;
  const _SystemView({required this.system});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs = system.stereoPairs;
    // Soundbars (whether or not they already have surrounds) are the HT targets.
    final theaters = system.allMembers
        .where((m) => m.isHomeTheater || (system.device(m.uuid)?.isSoundbar ?? false))
        .toList();
    final otherRooms = system.allMembers
        .where((m) => !theaters.contains(m) && !pairs.contains(m))
        .toList();
    final canPair =
        system.bondableSpeakers.where((d) => d.reachable).length >= 2;

    // A plain (non-scrolling) box so it can ride inside the body's
    // PageTransitionSwitcher; SliverFillRemaining sizes it by intrinsic height
    // and the OUTER CustomScrollView does the scrolling (no nested scroll).
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader('Home theaters', Icons.theaters_outlined),
          if (theaters.isEmpty)
            const _EmptyHint(
              'No soundbar found. Dedicated fronts need an Arc, Beam, Ray, '
              'Playbar or Playbase.',
            ),
          ...theaters.map((m) => _TheaterCard(system: system, member: m)),
          Gap.l,
          _SectionHeader('Stereo pairs', Icons.speaker_group_outlined),
          ...pairs.map((m) => _PairCard(system: system, pair: m)),
          if (canPair)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: FilledButton.tonalIcon(
                onPressed: () => context.push('/stereo-pair'),
                icon: const Icon(Icons.add_link, size: 24),
                label: const Text('Create stereo pair'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Gap.l,
          _SectionHeader('Other rooms', Icons.meeting_room_outlined),
          ...otherRooms.map((m) {
            final device = system.device(m.uuid);
            final unreachable = device != null && !device.reachable;
            final scheme = Theme.of(context).colorScheme;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                onTap: unreachable ? null : () => context.push('/room/${m.uuid}'),
                leading: Icon(
                  unreachable ? Icons.warning_amber_rounded : Icons.speaker_outlined,
                  color: unreachable ? scheme.error : null,
                ),
                title: Text(m.zoneName),
                subtitle: Text(
                  unreachable ? unreachableSpeakerHint : (device?.typeLabel ?? ''),
                  style: unreachable ? TextStyle(color: scheme.error) : null,
                ),
                trailing: unreachable ? null : const Icon(Icons.chevron_right),
              ),
            );
          }),
          // Unbonded Subs: shown so they're visible (they're Invisible members
          // with no room), but not tappable — there's nothing to configure for a
          // standalone sub; add it to a home theater from the HT setup flow.
          ...system.bondableSubs.map((sub) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.graphic_eq),
                  title: const Text('Subwoofer'),
                  subtitle: Text(sub.typeLabel),
                ),
              )),
        ],
      ),
    );
  }
}

class _PairCard extends ConsumerWidget {
  final SonosSystem system;
  final ZoneGroupMember pair;
  const _PairCard({required this.system, required this.pair});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uuids = pair.stereoPairUuids;
    final left = uuids.isNotEmpty ? system.device(uuids[0]) : null;
    final right = uuids.length > 1 ? system.device(uuids[1]) : null;
    final models = [left?.typeLabel, right?.typeLabel]
        .whereType<String>()
        .join(' + ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => context.push('/room/${pair.uuid}'),
        leading: const Icon(Icons.speaker_group),
        title: Text(pair.zoneName),
        subtitle: Text(models.isEmpty ? 'Stereo pair' : models),
        trailing: TextButton(
          onPressed: (left != null && right != null)
              ? () => _confirmSeparate(context, ref, left, right)
              : null,
          child: const Text('Separate'),
        ),
      ),
    );
  }

  Future<void> _confirmSeparate(
      BuildContext context, WidgetRef ref, SonosDevice left, SonosDevice right) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.link_off),
        title: const Text('Separate stereo pair?'),
        content: const Text(
            'The two speakers become standalone rooms again. Their original '
            'room names will be restored.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Separate'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final controller = ref.read(sonosControllerProvider.notifier);
    // No success toast — the progress screen already showed the outcome.
    await showBondingProgress(
      context,
      title: 'Separate stereo pair',
      run: () => controller.separateStereoPair(left: left, right: right),
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
                      Gap.s,
                      _GroupChips(system: system, member: member),
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

/// Small chips on a home-theater card showing which extra-speaker groups are
/// bonded (Fronts / Surrounds / Sub) with their speaker names.
class _GroupChips extends StatelessWidget {
  final SonosSystem system;
  final ZoneGroupMember member;
  const _GroupChips({required this.system, required this.member});

  static const _groups = [
    ('Fronts', Icons.speaker, [SonosChannel.leftFront, SonosChannel.rightFront]),
    ('Surrounds', Icons.surround_sound, [SonosChannel.leftRear, SonosChannel.rightRear]),
    ('Subwoofer', Icons.graphic_eq, [SonosChannel.sub]),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[];
    for (final (label, icon, channels) in _groups) {
      if (channels.any((c) => hasChannel(member, c))) {
        chips.add(_chip(scheme, icon, label, scheme.primary));
      }
    }
    if (chips.isEmpty) {
      chips.add(_chip(scheme, Icons.info_outline, 'No extra speakers',
          scheme.onSurfaceVariant));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chip(ColorScheme scheme, IconData icon, String text, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
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
