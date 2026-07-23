import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/localized_error.dart';
import '../../state/sonos_controller.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/reorderable_card_grid.dart';
import 'profile.dart';
import 'profile_controller.dart';
import 'profile_ui.dart';

/// The Profiles tab: saved layouts you can re-apply in one tap.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  /// Reorder mode: cards become drag-only (no apply / delete / open).
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    final hasSystem = ref.watch(sonosControllerProvider).value != null;
    // Reordering needs ≥2 profiles; keep the toggle visible while editing so
    // "Done" is always reachable.
    final count = profiles.value?.length ?? 0;
    final showToggle = count > 1 || _editing;

    final body = profiles.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text(
              context.l10n.profileLoadError(localizedError(context.l10n, e)))),
      data: (list) {
        if (list.isEmpty) return const _EmptyState();
        // One reorderable grid for every width: a single column on a phone, 2–3
        // when wide. Drag/reorder is gated behind the reorder-mode toggle.
        return ReorderableCardGrid<Profile>(
          items: list,
          idOf: (p) => p.id,
          reordering: _editing,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
          itemBuilder: (context, p) =>
              _profileCard(context, ref, p, editing: _editing),
          onReorder: (from, to) =>
              ref.read(profilesProvider.notifier).reorder(from, to),
        );
      },
    );

    return AppScaffold(
      title: context.l10n.tabProfiles,
      actions: [
        if (showToggle)
          IconButton(
            tooltip:
                _editing ? context.l10n.actionDone : context.l10n.profileReorder,
            onPressed: () => setState(() => _editing = !_editing),
            icon: Icon(_editing ? Icons.check : Icons.low_priority),
          ),
      ],
      // Nothing else is actionable in reorder mode, so the "new profile" FAB
      // steps aside.
      floatingActionButton: _editing
          ? null
          : FloatingActionButton.extended(
              onPressed: hasSystem
                  ? () => context.go('/profiles/new')
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.profileScanFirst)),
                      ),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.profileNew),
            ),
      body: body,
    );
  }
}

/// One profile tile. In reorder mode (`editing`) the card is inert — no tap,
/// no action buttons — and the ⋮ menu becomes a drag handle.
Widget _profileCard(
  BuildContext context,
  WidgetRef ref,
  Profile p, {
  bool editing = false,
}) {
  return ProfileCard(
    profile: p,
    onTap: editing ? null : () => context.go('/profiles/edit/${p.id}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    actionsCollapsed: editing,
    // Drag handle in reorder mode, else the overflow menu (destructive Delete).
    // Both are IconButton-sized so they occupy the exact same spot; ProfileCard
    // cross-fades between them (keyed).
    trailing: editing
        ? IconButton(
            key: const ValueKey('handle'),
            onPressed: null, // inert affordance; the whole card is the drag surface
            style: IconButton.styleFrom(
              disabledForegroundColor:
                  Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            icon: const Icon(Icons.drag_handle),
          )
        : PopupMenuButton<String>(
            key: const ValueKey('menu'),
            tooltip: context.l10n.actionMore,
            onSelected: (_) => _confirmDelete(context, ref, p),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'delete', child: Text(context.l10n.actionDelete)),
            ],
          ),
    // Always built so ProfileCard can animate it out; collapsed in reorder mode.
    actions: Row(
      children: [
        Expanded(
          child: FilledButton.tonal(
            onPressed: () => context.go('/profiles/edit/${p.id}'),
            child: Text(context.l10n.profileEdit),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => applyProfileInteractive(context, ref, p),
            icon: const Icon(Icons.play_arrow),
            label: Text(context.l10n.actionApply),
          ),
        ),
      ],
    ),
  );
}

Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Profile p) async {
  final ok = await confirmDialog(
    context,
    title: context.l10n.profileDeleteConfirm(p.name),
    message: context.l10n.profileDeleteMessage,
    confirmLabel: context.l10n.actionDelete,
  );
  if (ok) await ref.read(profilesProvider.notifier).remove(p.id);
}

/// In-app apply (the tile's Apply button): the system is already discovered, so
/// pre-flight runs immediately and the confirm dialog shows ONLY when there are
/// issues (missing / conflicting speakers) — a clean apply goes straight to the
/// progress screen.
Future<void> applyProfileInteractive(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final system = ref.read(sonosControllerProvider).value;
  if (system == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.profileScanFirst)),
    );
    return;
  }
  final issues = preflightProfile(profile, system);
  final hasIssues = issues.any(
    (i) => i.missing.isNotEmpty || i.conflicts.isNotEmpty,
  );
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
    title: context.l10n.profileApplying(profile.name),
    run: () => ctrl.applyProfile(profile, skip: skip),
  );
}

/// Launch apply (app shortcut / home-screen widget): there's no reliable prior
/// scan, so go straight to the progress screen — its FIRST step scans the
/// network. If that scan finds missing/conflicting speakers, the SAME confirm
/// dialog as an in-app apply pops over the progress screen; otherwise it applies
/// straight through.
Future<void> applyProfileFromLaunch(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final ctrl = ref.read(sonosControllerProvider.notifier);
  await showBondingProgress(
    context,
    title: context.l10n.profileApplying(profile.name),
    run: () => ctrl.scanAndApplyProfile(
      profile,
      confirmIssues: (issues) async {
        if (!context.mounted) return false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) =>
              _ApplyConfirmDialog(profile: profile, issues: issues),
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
            Text(context.l10n.profileEmptyTitle,
                style: theme.textTheme.titleLarge),
            Gap.s,
            Text(
              context.l10n.profileEmptyBody,
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
      title: Text(context.l10n.profileApplyConfirmTitle(profile.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.profileApplyConfirmBody,
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
                        context.l10n.profileIssueMissing(
                            i.missing.toSet().join(', ')),
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    : i.conflicts.isNotEmpty
                    ? Text(context.l10n
                        .profileIssueFree(i.conflicts.toSet().join(', ')))
                    : null,
              ),
            if (applicable.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.l10n.profileNothingApplicable,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            else if (blocked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.l10n.profileApplySummary(
                      applicable.length, issues.length, blocked.length),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.actionCancel),
        ),
        TextButton(
          onPressed: applicable.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          child: Text(context.l10n.actionApply),
        ),
      ],
    );
  }
}
