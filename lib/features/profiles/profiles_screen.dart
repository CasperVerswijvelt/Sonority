import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import '../widgets/collapsing_scaffold.dart';
import 'profile.dart';
import 'profile_apply_screen.dart';
import 'profile_controller.dart';

/// The Profiles tab: saved layouts you can re-apply in one tap.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final hasSystem = ref.watch(sonosControllerProvider).value != null;

    Widget filler(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);

    final slivers = profiles.when(
      loading: () => [filler(const Center(child: CircularProgressIndicator()))],
      error: (e, _) => [filler(Center(child: Text('Couldn’t load profiles: $e')))],
      data: (list) => list.isEmpty
          ? [filler(const _EmptyState())]
          : [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                sliver: SliverList.list(
                  children: [
                    for (final p in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ProfileTile(
                          profile: p,
                          onApply: () => _apply(context, ref, p),
                          onEdit: () => context.go('/profiles/edit/${p.id}'),
                          onDelete: () => _confirmDelete(context, ref, p),
                        ),
                      ),
                  ],
                ),
              ),
            ],
    );

    return CollapsingScaffold(
      title: 'Profiles',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: hasSystem
            ? () => context.go('/profiles/new')
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Scan your system first (System tab).')),
                ),
        icon: const Icon(Icons.add),
        label: const Text('New profile'),
      ),
      slivers: slivers,
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref, Profile p) async {
    final system = ref.read(sonosControllerProvider).value;
    if (system == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan your system first (System tab).')));
      return;
    }
    final issues = preflightProfile(p, system);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ApplyConfirmDialog(profile: p, issues: issues),
    );
    if (ok != true || !context.mounted) return;
    final skip = {
      for (final i in issues)
        if (i.blocked) i.entity.primaryUuid
    };
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => ProfileApplyScreen(profile: p, skip: skip),
    ));
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${p.name}”?'),
        content: const Text('This removes the saved profile. Your speakers are '
            'not changed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(profilesProvider.notifier).remove(p.id);
  }
}

class _ProfileTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onApply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProfileTile({
    required this.profile,
    required this.onApply,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = profile.entities.map((e) => e.label).join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: theme.textTheme.titleMedium),
                    Gap.xs,
                    Text(
                      summary.isEmpty ? 'No entities' : summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Gap.s,
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Apply'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            Icon(Icons.dashboard_customize_outlined,
                size: 56, color: theme.colorScheme.primary),
            Gap.m,
            Text('No profiles yet', style: theme.textTheme.titleLarge),
            Gap.s,
            Text(
              'A profile snapshots your current home theaters, stereo pairs and '
              'rooms so you can rebuild them in one tap — handy after moving '
              'speakers away. Tap “New profile” to capture your setup now.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  i.blocked ? Icons.error_outline : Icons.check_circle_outline,
                  color: i.blocked
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                title: Text('${i.entity.kindLabel}: ${i.entity.label}'),
                subtitle: i.blocked
                    ? Text(
                        'Missing: ${i.missing.toSet().join(', ')} — will be skipped',
                        style: TextStyle(color: theme.colorScheme.error))
                    : i.conflicts.isNotEmpty
                        ? Text('Will free: ${i.conflicts.toSet().join(', ')}')
                        : null,
              ),
            if (applicable.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Nothing can be applied — all entities are missing '
                    'speakers.',
                    style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (blocked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Will apply ${applicable.length} of ${issues.length} '
                    'entities; ${blocked.length} skipped.',
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: applicable.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Apply')),
      ],
    );
  }
}
