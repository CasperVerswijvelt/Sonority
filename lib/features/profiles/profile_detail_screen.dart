import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import '../widgets/collapsing_scaffold.dart';
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_seeded) {
      _name.text = profile.name;
      _seeded = true;
    }

    final name = _name.text.trim();
    final taken = isProfileNameTaken(profiles, name, exceptId: profile.id);
    final changed = name != profile.name && name.isNotEmpty && !taken;

    return CollapsingScaffold(
      title: 'Profile',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
              Gap.s,
              FilledButton(
                onPressed: changed ? () => _save(profile, name) : null,
                child: const Text('Save'),
              ),
              Gap.l,
              Text('Included', style: theme.textTheme.titleSmall),
              Text(
                'Captured when the profile was created. To change what’s '
                'included, create a new profile from your current setup.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Gap.s,
              for (final e in profile.entities) ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(entityIcon(e.kind)),
                    title: Text(e.label),
                    subtitle: Text(entitySummary(e, system)),
                    isThreeLine: e.kind == EntityKind.homeTheater,
                  ),
                ),
                Gap.s,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save(Profile profile, String name) async {
    final router = GoRouter.of(context);
    await ref
        .read(profilesProvider.notifier)
        .replace(profile.copyWith(name: name));
    router.go('/profiles');
  }
}
