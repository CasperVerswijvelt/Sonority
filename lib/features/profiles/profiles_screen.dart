import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import 'profile.dart';
import 'profile_controller.dart';
import 'profile_ui.dart';

/// The Profiles tab: saved layouts you can re-apply in one tap.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final hasSystem = ref.watch(sonosControllerProvider).value != null;

    final body = profiles.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Couldn’t load profiles: $e')),
      data: (list) => list.isEmpty
          ? const _EmptyState()
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
              itemCount: list.length,
              // No default drag handles: on desktop they draw a trailing ≡ icon
              // (clashes with the card's ⋮ menu) and make dragging start only
              // from that handle. We wrap each item in a delayed listener below
              // so long-press-to-drag works on every platform (incl. macOS).
              buildDefaultDragHandles: false,
              // Drop the default elevated-Material drag proxy (it draws a square
              // highlight/shadow behind the rounded card); the card lifts as-is.
              proxyDecorator: (child, index, animation) =>
                  Material(color: Colors.transparent, child: child),
              // Long-press a card to drag it — this order is what the widgets use.
              onReorder: (oldIndex, newIndex) => ref
                  .read(profilesProvider.notifier)
                  .reorder(oldIndex, newIndex),
              itemBuilder: (context, i) {
                final p = list[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(p.id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ProfileCard(
                      profile: p,
                      onTap: () => context.go('/profiles/edit/${p.id}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filled(
                            onPressed: () =>
                                applyProfileInteractive(context, ref, p),
                            tooltip: 'Apply',
                            icon: const Icon(Icons.play_arrow),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) => v == 'edit'
                                ? context.go('/profiles/edit/${p.id}')
                                : _confirmDelete(context, ref, p),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );

    return AppScaffold(
      title: 'Profiles',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: hasSystem
            ? () => context.go('/profiles/new')
            : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Scan your system first (System tab).'),
                ),
              ),
        icon: const Icon(Icons.add),
        label: const Text('New profile'),
      ),
      body: body,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Profile p,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete “${p.name}”?',
      message: 'This removes the saved profile. Your speakers are not changed.',
      confirmLabel: 'Delete',
    );
    if (ok) await ref.read(profilesProvider.notifier).remove(p.id);
  }
}

/// In-app apply (the tile's Apply button): the system is already discovered, so
/// pre-flight runs immediately and the confirm dialog shows ONLY when there are
/// issues (missing / conflicting speakers) — a clean apply goes straight to the
/// progress screen.
Future<void> applyProfileInteractive(
    BuildContext context, WidgetRef ref, Profile profile) async {
  final system = ref.read(sonosControllerProvider).value;
  if (system == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scan your system first (System tab).')),
    );
    return;
  }
  final issues = preflightProfile(profile, system);
  final hasIssues =
      issues.any((i) => i.missing.isNotEmpty || i.conflicts.isNotEmpty);
  if (hasIssues) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ApplyConfirmDialog(profile: profile, issues: issues),
    );
    if (ok != true || !context.mounted) return;
  }
  final skip = {
    for (final i in issues)
      if (i.blocked) i.entity.primaryUuid,
  };
  final ctrl = ref.read(sonosControllerProvider.notifier);
  // No success toast — the progress screen already shows the outcome.
  await showBondingProgress(
    context,
    title: 'Applying “${profile.name}”',
    run: () => ctrl.applyProfile(profile, skip: skip),
  );
}

/// Launch apply (app shortcut / home-screen widget): there's no reliable prior
/// scan, so go straight to the progress screen — its FIRST step scans the
/// network. If that scan finds missing/conflicting speakers, the SAME confirm
/// dialog as an in-app apply pops over the progress screen; otherwise it applies
/// straight through.
Future<void> applyProfileFromLaunch(
    BuildContext context, WidgetRef ref, Profile profile) async {
  final ctrl = ref.read(sonosControllerProvider.notifier);
  await showBondingProgress(
    context,
    title: 'Applying “${profile.name}”',
    run: () => ctrl.scanAndApplyProfile(
      profile,
      confirmIssues: (issues) async {
        if (!context.mounted) return false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => _ApplyConfirmDialog(profile: profile, issues: issues),
        );
        return ok == true;
      },
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dashboard_customize_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            Gap.m,
            Text('No profiles yet', style: theme.textTheme.titleLarge),
            Gap.s,
            Text(
              'A profile snapshots your current home theaters, stereo pairs and '
              'rooms so you can rebuild them in one tap — handy after moving '
              'speakers away. Tap “New profile” to capture your setup now.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplyConfirmDialog extends StatelessWidget {
  final Profile profile;
  final List<EntityIssue> issues;
  const _ApplyConfirmDialog({required this.profile, required this.issues});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked = issues.where((i) => i.blocked).toList();
    final applicable = issues.where((i) => !i.blocked).toList();

    return AlertDialog(
      title: Text('Apply “${profile.name}”?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This re-bonds speakers on your live system and may take a while '
              '(each step waits for Sonos to settle). Trueplay may need '
              're-tuning afterward.',
              style: theme.textTheme.bodySmall,
            ),
            Gap.m,
            for (final i in issues)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  i.blocked ? Icons.warning_amber_rounded : Icons.check,
                  color: i.blocked
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                title: Text('${i.entity.kindLabel}: ${i.entity.label}'),
                subtitle: i.blocked
                    ? Text(
                        'Missing: ${i.missing.toSet().join(', ')} — will be skipped',
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    : i.conflicts.isNotEmpty
                    ? Text('Will free: ${i.conflicts.toSet().join(', ')}')
                    : null,
              ),
            if (applicable.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Nothing can be applied — all entities are missing '
                  'speakers.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            else if (blocked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Will apply ${applicable.length} of ${issues.length} '
                  'entities; ${blocked.length} skipped.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: applicable.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
