import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/entity_cards.dart';
import '../widgets/section_header.dart';
import 'profile.dart';
import 'profile_controller.dart';
import 'profile_entity_detail_screen.dart';
import 'profile_ui.dart';

/// A profile's detail view and single save surface: edit the name/appearance,
/// review what each captured entity will restore, and re-snapshot to replace the
/// captured layout from the current setup. All edits are unsaved until Save.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  final String profileId;
  const ProfileDetailScreen({super.key, required this.profileId});

  @override
  ConsumerState<ProfileDetailScreen> createState() => _State();
}

class _State extends ConsumerState<ProfileDetailScreen> {
  final _name = TextEditingController();
  bool _seeded = false;
  late String _iconId;
  late int _color;

  /// Working copy of the entities from a re-snapshot, awaiting Save. Null until
  /// the user re-snapshots — the stored `profile.entities` is shown until then.
  List<EntitySnapshot>? _pendingEntities;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = ref.watch(profilesProvider).value ?? const [];
    final profile = profiles
        .where((p) => p.id == widget.profileId)
        .cast<Profile?>()
        .firstOrNull;
    final system = ref.watch(sonosControllerProvider).value;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_seeded) {
      _name.text = profile.name;
      _iconId = profile.iconId;
      _color = profile.color;
      _seeded = true;
    }

    final entities = _pendingEntities ?? profile.entities;
    final name = _name.text.trim();
    final taken = isProfileNameTaken(profiles, name, exceptId: profile.id);
    final appearanceChanged =
        _iconId != profile.iconId || _color != profile.color;
    final nameChanged = name != profile.name;
    final entitiesChanged = _pendingEntities != null;
    final changed = (nameChanged || appearanceChanged || entitiesChanged) &&
        name.isNotEmpty &&
        !taken;

    return AppScaffold(
      title: 'Profile',
      actions: [
        IconButton(
          tooltip: 'Re-snapshot from current setup',
          onPressed: system == null ? null : () => _resnapshot(profile),
          icon: const Icon(Icons.cameraswitch),
        ),
      ],
      // Save appears once the name, appearance (icon/colour), or a re-snapshot
      // differs from what's stored.
      floatingActionButton: changed
          ? FloatingActionButton.extended(
              onPressed: () => _save(profile, name),
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          ProfileNameField(
            controller: _name,
            iconId: _iconId,
            color: _color,
            nameTaken: taken,
            onChanged: () => setState(() {}),
            onAppearanceChanged: (icon, color) => setState(() {
              _iconId = icon;
              _color = color;
            }),
          ),
          Gap.l,
          const SectionHeader('Included'),
          Text(
            entitiesChanged
                ? 'Recaptured from your current setup — press Save to keep it.'
                : 'Captured when the profile was created. Use the re-snapshot '
                    'button (top right) to recapture from your current setup.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: entitiesChanged
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Gap.m,
          // Same cards as the system overview, fed a throwaway member built from
          // the stored snapshot, with a "settings saved" footer. Tapping opens
          // the entity detail sheet (fed the snapshot directly, so it works for a
          // pending re-snapshot entity too).
          for (final e in entities) _entityCard(context, e, system),
        ],
      ),
    );
  }

  /// Open the picker, and on return stash the recaptured entities as an unsaved
  /// change (committed only when the user taps Save).
  Future<void> _resnapshot(Profile profile) async {
    final result = await context.push<List<EntitySnapshot>>(
        '/profiles/edit/${profile.id}/resnapshot');
    if (result != null && mounted) {
      setState(() => _pendingEntities = result);
    }
  }

  Future<void> _save(Profile profile, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(profilesProvider.notifier).replace(profile.copyWith(
          name: name,
          iconId: _iconId,
          color: _color,
          entities: _pendingEntities ?? profile.entities,
        ));
    if (!mounted) return;
    // Stay on the page: clearing pending + the provider update make `changed`
    // false, so the Save FAB hides itself.
    setState(() => _pendingEntities = null);
    messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
  }
}

/// One entity as a compact tile (every kind — the profile list is uniform,
/// unlike the overview's rich HT card), built from the stored snapshot with a
/// "settings saved" footer and a tap that opens the entity detail sheet.
Widget _entityCard(
    BuildContext context, EntitySnapshot e, SonosSystem? system) {
  return EntityCard(
    model: EntityCardModel.fromSnapshot(system, e.toMember()),
    onTap: () => showEntitySheet(context, e, system),
    footer:
        settingsBadges(context, audio: e.hasAudioSettings, volume: e.hasVolume),
  );
}
