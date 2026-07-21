import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/brand_wordmark.dart';
import '../widgets/entity_cards.dart';
import '../widgets/identify_controls.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sheet_scaffold.dart';
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

    // Wide layout carries the wordmark + version in the nav rail, so the app
    // bar shows a plain "System" title; narrow (no rail) keeps the wordmark as
    // the title and the version badge in the actions.
    final wide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
    return AppScaffold(
      title: 'System',
      titleWidget: wide ? null : const BrandWordmark(),
      onRefresh: state.value != null ? () => controller.scan() : null,
      // Roomier cap than a single-column page — the overview lays entity cards
      // out in multiple columns on a wide window (see `_cardGrid`).
      maxContentWidth: kOverviewMaxWidth,
      actions: [
        if (!wide) const VersionBadge(),
        // Diagnostics now lives in the bottom nav (see app.dart), not here.
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
          SectionHeader('Home theaters', icon: Icons.theaters_outlined),
          if (theaters.isEmpty)
            const _EmptyHint(
              'No soundbar found. Dedicated fronts need an Arc, Beam, Ray, '
              'Playbar or Playbase.',
            ),
          _cardGrid(context, [
            for (final m in theaters)
              EntityCard(
                model: EntityCardModel.fromMember(system, m),
                onTap: () => context.push('/theater/${m.uuid}'),
              ),
          ]),
          Gap.l,
          // The "+" lives in the header; the flow itself explains if there
          // aren't two free speakers to bond.
          SectionHeader(
            'Speaker groups',
            icon: Icons.speaker_group_outlined,
            onAdd: () => context.push('/group'),
            addTooltip: 'Group speakers',
          ),
          if (groups.isEmpty)
            const _EmptyHint('No speaker groups yet')
          else
            _cardGrid(context, [
              for (final m in groups)
                EntityCard(
                  model: EntityCardModel.fromMember(system, m),
                  onTap: () => context.push('/group/${m.uuid}'),
                ),
            ]),
          // Single speaker rooms — hidden entirely when there are none.
          if (singleRooms.isNotEmpty) ...[
            Gap.l,
            SectionHeader('Single speaker rooms',
                icon: Icons.meeting_room_outlined),
            _cardGrid(context, [
              for (final m in singleRooms)
                EntityCard(
                  model: EntityCardModel.fromMember(system, m),
                  onTap: () => context.push('/room/${m.uuid}'),
                ),
            ]),
          ],
          // Other devices: unbonded Subs are shown so they're visible (they're
          // Invisible members with no room). Tapping opens a small sheet to
          // identify it and explains how to bond it — a standalone sub has no
          // config of its own, so this is the only affordance.
          if (system.bondableSubs.isNotEmpty) ...[
            Gap.l,
            SectionHeader('Other devices', icon: Icons.devices_other_outlined),
            _cardGrid(context, [
              for (final sub in system.bondableSubs)
                EntityCard(
                  model: EntityCardModel(
                    icon: Icons.graphic_eq,
                    title: 'Subwoofer',
                    subtitle: sub.typeLabel,
                  ),
                  onTap: () => _showSubSheet(context, sub),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Lays a section's entity cards out responsively: one full-width column on a
/// phone, a multi-column grid on a wide window. The wide/narrow switch keys off
/// the WINDOW width (like the nav rail), not the post-rail content width — so the
/// grid goes multi-column at exactly the same breakpoint the bottom bar becomes a
/// rail. Each [EntityCard] carries its own bottom gap, so the grid uses
/// `runSpacing: 0` and only adds horizontal spacing between columns.
Widget _cardGrid(BuildContext context, List<Widget> cards) {
  if (cards.isEmpty) return const SizedBox.shrink();
  if (MediaQuery.sizeOf(context).width < kWideLayoutBreakpoint) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
  }
  return LayoutBuilder(
    builder: (context, c) {
      final cols = (c.maxWidth / 360).floor().clamp(2, 3);
      final w = (c.maxWidth - (cols - 1) * kCardGap) / cols;
      return Wrap(
        spacing: kCardGap,
        runSpacing: 0,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    },
  );
}

/// Opens a standalone (unbonded) Sub as a small sheet: identify it by ear/LED and
/// a note on how to put it to use (it has no config of its own).
Future<void> _showSubSheet(BuildContext context, SonosDevice sub) =>
    showSheet<void>(
      context,
      SheetScaffold(
        title: 'Subwoofer',
        subtitle: sub.typeLabel,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 4, kPageGutter, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MemberChannelCard(
                icon: Icons.graphic_eq,
                type: sub.typeLabel,
                trailing: speakerIdentifyButton(sub),
              ),
              Gap.m,
              Text(
                'This Sub isn’t bonded to anything yet. Add it to a home theater '
                '(Configure home theater) or a speaker group to use it.',
                style: Theme.of(context).mutedText,
              ),
            ],
          ),
        ),
      ),
    );

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: kCardGap),
    child: Text(
      text,
      style: Theme.of(context).mutedText,
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
