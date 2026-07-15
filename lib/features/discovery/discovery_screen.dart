import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../diagnostics/diagnostics_sheet.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/entity_cards.dart';
import '../widgets/version_badge.dart';

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
      error: (e, _) => _ErrorView(
        message: e.toString().replaceFirst('Exception: ', ''),
        onRetry: controller.scan,
      ),
      // discover() throws on an empty network, so data is never null here;
      // fall back to the spinner defensively rather than crash.
      data: (system) => system == null
          ? const Center(child: _Scanning())
          : _SystemView(system: system),
    );

    return AppScaffold(
      title: 'Sonority',
      // White glyphs on alpha → srcIn tint recolors them to the theme text
      // colour, so the one asset works in light and dark. ColorFiltered (not
      // Image(color:)) because CanvasKit renders an image `color` tint blank on
      // web — this path tints correctly on every platform (the screenshot host).
      titleWidget: ColorFiltered(
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.onSurface,
          BlendMode.srcIn,
        ),
        child: Image.asset('assets/brand/sonority_wordmark.png', height: 20),
      ),
      onRefresh: state.value != null ? () => controller.scan() : null,
      actions: [
        const VersionBadge(),
        IconButton(
          tooltip: 'Diagnostics',
          onPressed: () => showDiagnosticsSheet(context),
          icon: const Icon(Icons.bug_report_outlined),
        ),
        // Only when there's a discovered system to refresh; the error state
        // uses its own CTA button to scan.
        if (state.value != null)
          IconButton(
            tooltip: 'Rescan',
            onPressed: state.isLoading ? null : controller.scan,
            icon: const Icon(Icons.refresh),
          ),
      ],
      // The scanning/error placeholders center themselves (their Center
      // expands to the body height); _SystemView shrink-wraps when short. The
      // switcher's default layout is a center-aligned Stack, which floats that
      // shrink-wrapped content to the vertical middle mid-transition (when the
      // expanding placeholder inflates the Stack) — top-align it instead.
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 250),
        reverse: state.isLoading,
        layoutBuilder: (entries) =>
            Stack(alignment: Alignment.topCenter, children: entries),
        transitionBuilder: (child, anim, secondaryAnim) => SharedAxisTransition(
          animation: anim,
          secondaryAnimation: secondaryAnim,
          transitionType: SharedAxisTransitionType.scaled,
          fillColor: Colors.transparent,
          child: child,
        ),
        child: KeyedSubtree(key: ValueKey(branch), child: content),
      ),
    );
  }
}

class _SystemView extends ConsumerWidget {
  final SonosSystem system;
  const _SystemView({required this.system});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = system.speakerGroups;
    // Soundbars (whether or not they already have surrounds) are the HT targets.
    final theaters = system.allMembers
        .where(
          (m) =>
              m.isHomeTheater || (system.device(m.uuid)?.isSoundbar ?? false),
        )
        .toList();
    final singleRooms = system.allMembers
        .where((m) => !theaters.contains(m) && !m.isGroup)
        .toList();
    // Owns its own scroll, filling the screen-sized body. The app bar is fixed,
    // so there's no collapse to lose; Rescan / pull-to-refresh cover refresh.
    return SingleChildScrollView(
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
          ...theaters.map((m) => TheaterEntityCard(
                model: TheaterCardModel.fromMember(system, m),
                onTap: () => context.push('/theater/${m.uuid}'),
              )),
          Gap.l,
          // The "+" lives in the header; the flow itself explains if there
          // aren't two free speakers to bond.
          _SectionHeader(
            'Speaker groups',
            Icons.speaker_group_outlined,
            onAdd: () => context.push('/group'),
            addTooltip: 'Group speakers',
          ),
          if (groups.isEmpty)
            const _EmptySectionCard('No speaker groups yet')
          else
            ...groups.map((m) => EntityCard(
                  model: EntityCardModel.fromMember(system, m),
                  onTap: () => context.push('/group/${m.uuid}'),
                )),
          // Single speaker rooms — hidden entirely when there are none.
          if (singleRooms.isNotEmpty) ...[
            Gap.l,
            _SectionHeader('Single speaker rooms', Icons.meeting_room_outlined),
            ...singleRooms.map((m) => EntityCard(
                  model: EntityCardModel.fromMember(system, m),
                  onTap: () => context.push('/room/${m.uuid}'),
                )),
          ],
          // Other devices: unbonded Subs are shown so they're visible (they're
          // Invisible members with no room), but not tappable — there's nothing
          // to configure for a standalone sub; add it to a home theater from the
          // HT setup flow.
          if (system.bondableSubs.isNotEmpty) ...[
            Gap.l,
            _SectionHeader('Other devices', Icons.devices_other_outlined),
          ],
          ...system.bondableSubs.map(
            (sub) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.graphic_eq),
                title: const Text('Subwoofer'),
                subtitle: Text(sub.typeLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  /// When set, a small right-aligned "+" button that triggers this (e.g. create
  /// a stereo pair / zone).
  final VoidCallback? onAdd;
  final String? addTooltip;
  const _SectionHeader(this.title, this.icon, {this.onAdd, this.addTooltip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          Gap.s,
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (onAdd != null)
            IconButton.outlined(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              tooltip: addTooltip,
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                side: BorderSide(color: scheme.outlineVariant),
                foregroundColor: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// A subtle, fill-free outlined card with centered text for an empty section.
/// Uses a transparent [Card] so its shape + hairline outline come straight from
/// `cardTheme` (theme.dart) — radius stays in sync with the real cards, nothing
/// hardcoded.
class _EmptySectionCard extends StatelessWidget {
  final String text;
  const _EmptySectionCard(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
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
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
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
      Text(
        'Scanning your network…',
        style: Theme.of(context).textTheme.titleMedium,
      ),
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
          Text(
            'Couldn’t find your system',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Gap.s,
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
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
