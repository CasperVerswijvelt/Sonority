import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import 'profile.dart';
import 'profile_controller.dart';

/// Create (profileId == null) a profile from a live snapshot, or edit an
/// existing one. Profiles are only ever built from current state — there's no
/// standalone config builder; here you pick which entities to include, rename
/// the profile, and adjust the stored room names.
class ProfileEditScreen extends ConsumerStatefulWidget {
  final String? profileId;
  const ProfileEditScreen({super.key, required this.profileId});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final TextEditingController _name;
  // Entities offered, keyed by primary UUID, plus include + edited-name state.
  final List<EntitySnapshot> _entities = [];
  final Map<String, bool> _included = {};
  final Map<String, TextEditingController> _names = {};
  bool _init = false;
  bool get _isNew => widget.profileId == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  void _seed() {
    if (_init) return;
    if (_isNew) {
      final system = ref.read(sonosControllerProvider).value;
      _name.text = 'My setup';
      for (final m in system?.allMembers ?? const []) {
        _entities.add(EntitySnapshot.fromMember(m));
      }
    } else {
      final p = ref
          .read(profilesProvider)
          .value
          ?.where((x) => x.id == widget.profileId)
          .cast<Profile?>()
          .firstOrNull;
      if (p == null) return; // not loaded yet; _seed runs again on rebuild
      _name.text = p.name;
      _entities.addAll(p.entities);
    }
    for (final e in _entities) {
      _included[e.primaryUuid] = true;
      _names[e.primaryUuid] =
          TextEditingController(text: e.names[e.primaryUuid] ?? e.label);
    }
    _init = true;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _seed();
    final theme = Theme.of(context);

    if (_isNew && ref.watch(sonosControllerProvider).value == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New profile')),
        body: const Center(
            child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Scan your system first (System tab), then create a '
              'profile from it.', textAlign: TextAlign.center),
        )),
      );
    }

    final anyIncluded = _included.values.any((v) => v);

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'New profile' : 'Edit profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Profile name', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.sentences,
            ),
            Gap.l,
            Text('Include', style: theme.textTheme.titleSmall),
            Text(
              _isNew
                  ? 'Pick which of your current home theaters, pairs and rooms '
                      'to capture. Room names are stored too — tweak them here.'
                  : 'Toggle entities and adjust the stored room names.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Gap.s,
            if (_entities.isEmpty)
              const Text('No entities available to capture.')
            else
              for (final e in _entities) _entityCard(e, theme),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: anyIncluded && _name.text.trim().isNotEmpty ? _save : null,
          child: Text(_isNew ? 'Create profile' : 'Save'),
        ),
      ),
    );
  }

  Widget _entityCard(EntitySnapshot e, ThemeData theme) {
    final included = _included[e.primaryUuid] ?? true;
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            value: included,
            onChanged: (v) =>
                setState(() => _included[e.primaryUuid] = v ?? false),
            title: Text(e.label),
            subtitle: Text(e.kindLabel),
          ),
          if (included)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _names[e.primaryUuid],
                decoration: const InputDecoration(
                    labelText: 'Stored room name', isDense: true),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final chosen = [
      for (final e in _entities)
        if (_included[e.primaryUuid] ?? false)
          e.copyWith(names: {
            ...e.names,
            e.primaryUuid: _names[e.primaryUuid]?.text.trim().isNotEmpty == true
                ? _names[e.primaryUuid]!.text.trim()
                : (e.names[e.primaryUuid] ?? e.label),
          }),
    ];
    final controller = ref.read(profilesProvider.notifier);
    final router = GoRouter.of(context);
    if (_isNew) {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await controller.add(Profile(id: id, name: _name.text.trim(), entities: chosen));
    } else {
      await controller
          .replace(Profile(id: widget.profileId!, name: _name.text.trim(), entities: chosen));
    }
    router.go('/profiles');
  }
}
