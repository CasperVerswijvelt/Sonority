import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import 'profile.dart';
import 'profile_controller.dart';
import 'profile_ui.dart';

/// Creates a profile from a live snapshot: pick which of the current entities
/// (home theaters / stereo pairs / rooms) to include, name it, save. Content is
/// only ever captured here — editing later changes the name only.
class ProfileCreateScreen extends ConsumerStatefulWidget {
  const ProfileCreateScreen({super.key});

  @override
  ConsumerState<ProfileCreateScreen> createState() => _State();
}

class _State extends ConsumerState<ProfileCreateScreen> {
  final _name = TextEditingController(text: 'My setup');
  final List<EntitySnapshot> _entities = [];
  final Map<String, bool> _included = {};
  bool _seeded = false;

  void _seed(SonosSystem system) {
    if (_seeded) return;
    for (final m in system.allMembers) {
      final e = EntitySnapshot.fromMember(m);
      _entities.add(e);
      _included[e.primaryUuid] = true;
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

    if (system == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New profile')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Scan your system first (System tab), then create a '
                'profile from it.', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    _seed(system);

    final profiles = ref.watch(profilesProvider).value ?? const [];
    final name = _name.text.trim();
    final taken = isProfileNameTaken(profiles, name);
    final anyIncluded = _included.values.any((v) => v);
    final canSave = name.isNotEmpty && !taken && anyIncluded;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverAppBar.large(
                    pinned: true, title: const Text('New profile')),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverList.list(
                    children: [
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
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      Gap.s,
                      for (final e in _entities) ...[
                        _SelectableEntityCard(
                          entity: e,
                          system: system,
                          included: _included[e.primaryUuid] ?? true,
                          onChanged: (v) =>
                              setState(() => _included[e.primaryUuid] = v),
                        ),
                        Gap.s,
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomButtonBar(
                label: 'Create profile',
                onPressed: canSave ? () => _save(name) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(String name) async {
    final chosen = [
      for (final e in _entities)
        if (_included[e.primaryUuid] ?? false) e,
    ];
    final router = GoRouter.of(context);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await ref
        .read(profilesProvider.notifier)
        .add(Profile(id: id, name: name, entities: chosen));
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
