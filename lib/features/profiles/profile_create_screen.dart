import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import 'profile.dart';
import 'profile_controller.dart';
import 'profile_ui.dart';

/// Captures a profile from a live snapshot: pick which of the current entities
/// (home theaters / stereo pairs / rooms) to include, name it, save.
///
/// Two modes: when [profileId] is null this creates a new profile; when set it
/// **re-snapshots** an existing one — overwriting its captured layout with the
/// current setup, keeping the same profile (id). Re-snapshot pre-fills the name,
/// pre-selects the entities that were originally in the profile, and gates the
/// save behind a confirm dialog since the old layout is lost.
class ProfileCreateScreen extends ConsumerStatefulWidget {
  final String? profileId;
  const ProfileCreateScreen({super.key, this.profileId});

  @override
  ConsumerState<ProfileCreateScreen> createState() => _State();
}

class _State extends ConsumerState<ProfileCreateScreen> {
  final _name = TextEditingController();
  final List<EntitySnapshot> _entities = [];
  final Map<String, bool> _included = {};
  bool _seeded = false;

  void _seed(SonosSystem system, Profile? existing) {
    if (_seeded) return;
    _name.text = existing?.name ?? 'My setup';
    // Re-snapshot pre-selects the entities that were originally in the profile.
    // Match by involved UUIDs, not primaryUuid — current live bonding may differ
    // from what the profile stored, which is the whole point of re-snapshotting.
    final originalUuids =
        existing?.entities.expand((e) => e.involvedUuids).toSet();
    for (final m in system.allMembers) {
      final e = EntitySnapshot.fromMember(m);
      _entities.add(e);
      _included[e.primaryUuid] = originalUuids == null
          ? true
          : e.involvedUuids.any(originalUuids.contains);
    }
    _seeded = true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final system = ref.watch(sonosControllerProvider).value;
    final profiles = ref.watch(profilesProvider).value ?? const [];
    final isResnapshot = widget.profileId != null;
    final existing = isResnapshot
        ? profiles
            .where((p) => p.id == widget.profileId)
            .cast<Profile?>()
            .firstOrNull
        : null;

    if (system == null) {
      return Scaffold(
        appBar: AppBar(title: Text(isResnapshot ? 'Update profile' : 'New profile')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Scan your system first (System tab), then create a '
              'profile from it.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    // Re-snapshot needs its profile loaded before seeding name/selection.
    if (isResnapshot && existing == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _seed(system, existing);

    final name = _name.text.trim();
    final taken = isProfileNameTaken(profiles, name, exceptId: widget.profileId);
    final anyIncluded = _included.values.any((v) => v);
    final canSave = name.isNotEmpty && !taken && anyIncluded;

    return AppScaffold(
      title: isResnapshot ? 'Update profile' : 'New profile',
      bottomOverlay: _BottomButtonBar(
        label: isResnapshot ? 'Update profile' : 'Create profile',
        onPressed: canSave ? () => _save(name, existing) : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (existing != null) ...[
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer),
                    Gap.s,
                    Expanded(
                      child: Text(
                        'This replaces everything captured in '
                        '“${existing.name}”. The previously saved layout '
                        'will be lost.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Gap.l,
          ],
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Profile name',
              border: const OutlineInputBorder(),
              errorText: taken ? 'A profile with this name exists' : null,
            ),
          ),
          Gap.l,
          Text('Include', style: theme.textTheme.titleSmall),
          Text(
            'Pick which of your current home theaters, pairs and '
            'rooms to capture in this profile.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Gap.s,
          for (final e in _entities) ...[
            _SelectableEntityCard(
              entity: e,
              system: system,
              included: _included[e.primaryUuid] ?? true,
              onChanged: (v) => setState(() => _included[e.primaryUuid] = v),
            ),
            Gap.s,
          ],
        ],
      ),
    );
  }

  Future<void> _save(String name, Profile? existing) async {
    final chosen = [
      for (final e in _entities)
        if (_included[e.primaryUuid] ?? false) e,
    ];
    final router = GoRouter.of(context);
    final notifier = ref.read(profilesProvider.notifier);

    if (existing != null) {
      // Re-snapshot: gate the overwrite behind an explicit confirm.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Replace “${existing.name}”?'),
          content: const Text(
            'The previously captured layout will be permanently replaced '
            'with your current setup.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await notifier.replace(existing.copyWith(name: name, entities: chosen));
    } else {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await notifier.add(Profile(id: id, name: name, entities: chosen));
    }
    router.go('/profiles');
  }
}

class _SelectableEntityCard extends StatelessWidget {
  final EntitySnapshot entity;
  final SonosSystem system;
  final bool included;
  final ValueChanged<bool> onChanged;

  const _SelectableEntityCard({
    required this.entity,
    required this.system,
    required this.included,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: CheckboxListTile(
        value: included,
        onChanged: (v) => onChanged(v ?? false),
        secondary: Icon(entityIcon(entity.kind)),
        title: Text(entity.label),
        subtitle: Text(entitySummary(entity, system)),
      ),
    );
  }
}

/// A full-width button over a scrim so the list scrolls visibly behind it.
class _BottomButtonBar extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _BottomButtonBar({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surface.withValues(alpha: 0), surface, surface],
        ),
      ),
      child: FilledButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
