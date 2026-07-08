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
  bool _saveAudio = false;
  bool _saveVolume = false;
  bool _saving = false;
  String _iconId = kDefaultProfileIcon;
  int _color = 0;

  void _seed(SonosSystem system, Profile? existing) {
    if (_seeded) return;
    _name.text = existing?.name ?? 'My setup';
    _iconId = existing?.iconId ?? kDefaultProfileIcon;
    _color = existing?.color ?? 0;
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

  /// Icon + colour picker in a dialog (keeps the create page uncluttered).
  Future<void> _editAppearance() async {
    final result =
        await showAppearanceDialog(context, iconId: _iconId, color: _color);
    if (result != null) {
      setState(() {
        _iconId = result.$1;
        _color = result.$2;
      });
    }
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
    final canSave = name.isNotEmpty && !taken && anyIncluded && !_saving;

    return AppScaffold(
      title: isResnapshot ? 'Update profile' : 'New profile',
      bottomOverlay: _BottomButtonBar(
        label: _saving
            ? 'Reading settings…'
            : isResnapshot
                ? 'Update profile'
                : 'Create profile',
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tap the swatch to pick the icon + colour (kept off the main flow
              // so the include list stays the focus of the page).
              AppearanceButton(
                  iconId: _iconId, color: _color, onTap: _editAppearance),
              Gap.s,
              Expanded(
                child: TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Profile name',
                    border: const OutlineInputBorder(),
                    errorText: taken ? 'A profile with this name exists' : null,
                  ),
                ),
              ),
            ],
          ),
          Gap.l,
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
                  Gap.s,
                  Expanded(
                    child: Text(
                      'Applying a profile later rebuilds these speakers into this '
                      'layout. Any speaker that’s part of a different setup at that '
                      'time is removed from it first — which can dissolve another '
                      'stereo pair or zone and free its other speakers.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
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
          Gap.l,
          Text('Speaker settings', style: theme.textTheme.titleSmall),
          Text(
            'Optionally snapshot each speaker’s current settings and restore '
            'them when this profile is applied.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Gap.s,
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                // Split card: each tile rounds only the corners it shares with
                // the card, so the ink highlight matches (top tile → top corners,
                // bottom tile → bottom corners; the divider edge stays square).
                SwitchListTile(
                  value: _saveAudio,
                  onChanged: (v) => setState(() => _saveAudio = v),
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12))),
                  secondary: const Icon(Icons.tune),
                  title: const Text('Save audio settings'),
                  subtitle: const Text(
                      'EQ, night sound, speech enhancement, sub & surround '
                      'levels, lip sync & more'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _saveVolume,
                  onChanged: (v) => setState(() => _saveVolume = v),
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(12))),
                  secondary: const Icon(Icons.volume_up),
                  title: const Text('Save volume'),
                  subtitle: const Text(
                      'Applying the profile will change how loud each speaker plays'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(String name, Profile? existing) async {
    var chosen = [
      for (final e in _entities)
        if (_included[e.primaryUuid] ?? false) e,
    ];
    final router = GoRouter.of(context);
    final notifier = ref.read(profilesProvider.notifier);

    if (existing != null) {
      // Re-snapshot: gate the overwrite behind an explicit confirm before we
      // do the (potentially slow) settings read.
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
            // TextButton (not FilledButton) so the actions stay horizontal — the
            // theme stretches FilledButton to full width, which forces a stack.
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    // Reading settings is several SOAP calls per speaker — show progress and
    // enrich the snapshots before saving.
    if (_saveAudio || _saveVolume) {
      setState(() => _saving = true);
      try {
        chosen = await ref
            .read(sonosControllerProvider.notifier)
            .captureSettings(chosen, audio: _saveAudio, volume: _saveVolume);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    if (existing != null) {
      await notifier.replace(existing.copyWith(
          name: name, entities: chosen, iconId: _iconId, color: _color));
    } else {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await notifier.add(Profile(
          id: id, name: name, entities: chosen, iconId: _iconId, color: _color));
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
      clipBehavior: Clip.antiAlias,
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
