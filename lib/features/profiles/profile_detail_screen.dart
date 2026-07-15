import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/entity_cards.dart';
import 'profile.dart';
import 'profile_controller.dart';
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
          Text('Included', style: theme.textTheme.titleSmall),
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
          // the entity detail — disabled while previewing an unsaved re-snapshot,
          // since the detail route reads the stored profile by index.
          for (final (i, e) in entities.indexed)
            _entityCard(context, profile, i, e, system,
                tappable: _pendingEntities == null),
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

/// One entity, rendered with the same card the system overview uses for its
/// kind, built from the stored snapshot (`fromSnapshot`) instead of live
/// topology, with a "settings saved" footer and a tap to the entity detail.
/// [tappable] is false while previewing an unsaved re-snapshot (the detail route
/// reads the stored profile, which doesn't yet have the pending entities).
Widget _entityCard(BuildContext context, Profile profile, int index,
    EntitySnapshot e, SonosSystem? system, {required bool tappable}) {
  final onTap = tappable
      ? () => context.go('/profiles/edit/${profile.id}/entity/$index')
      : null;
  final footer =
      settingsBadges(audio: e.hasAudioSettings, volume: e.hasVolume);
  final member = e.toMember();
  return switch (e.kind) {
    EntityKind.homeTheater => TheaterEntityCard(
        model: TheaterCardModel.fromSnapshot(system, member),
        onTap: onTap,
        footer: footer),
    EntityKind.single => SingleEntityCard(
        model: SingleCardModel.fromSnapshot(system, member),
        onTap: onTap,
        footer: footer),
    EntityKind.stereoPair || EntityKind.zone || EntityKind.custom =>
      GroupEntityCard(
          model: GroupCardModel.fromSnapshot(system, member),
          onTap: onTap,
          footer: footer),
  };
}
