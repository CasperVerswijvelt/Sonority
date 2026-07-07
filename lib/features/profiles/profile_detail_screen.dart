import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import 'profile.dart';
import 'profile_controller.dart';
import 'profile_ui.dart';

/// A profile's detail view. The captured content (entities) is read-only — it's
/// only ever set when the profile is created from a snapshot. Here you can edit
/// the profile name and review what each entity will restore.
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

    final name = _name.text.trim();
    final taken = isProfileNameTaken(profiles, name, exceptId: profile.id);
    final appearanceChanged =
        _iconId != profile.iconId || _color != profile.color;
    final nameChanged = name != profile.name;
    final changed =
        (nameChanged || appearanceChanged) && name.isNotEmpty && !taken;

    return AppScaffold(
      title: 'Profile',
      actions: [
        IconButton(
          tooltip: 'Re-snapshot from current setup',
          onPressed: system == null
              ? null
              : () => context.go('/profiles/edit/${profile.id}/resnapshot'),
          icon: const Icon(Icons.cameraswitch),
        ),
      ],
      // Save only appears once the name actually differs from what's stored.
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
            'Captured when the profile was created. Use the re-snapshot button '
            '(top right) to recapture from your current setup.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Gap.s,
          for (final e in profile.entities) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(entityIcon(e.kind)),
                titleAlignment: ListTileTitleAlignment.center,
                title: Text(e.label),
                subtitle: Text(
                  e.settingsSummary.isEmpty
                      ? entitySummary(e, system)
                      : '${entitySummary(e, system)}\n${e.settingsSummary}',
                ),
              ),
            ),
            Gap.s,
          ],
        ],
      ),
    );
  }

  Future<void> _save(Profile profile, String name) async {
    final router = GoRouter.of(context);
    await ref.read(profilesProvider.notifier).replace(
        profile.copyWith(name: name, iconId: _iconId, color: _color));
    router.go('/profiles');
  }
}
