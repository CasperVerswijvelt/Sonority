import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sonos_models.dart';
import 'profile.dart';
import 'profile_store.dart';

final profileStoreProvider = Provider<ProfileStore>((ref) => ProfileStore());

/// Loads, persists, and edits the user's saved profiles.
final profilesProvider =
    AsyncNotifierProvider<ProfilesController, List<Profile>>(
        ProfilesController.new);

class ProfilesController extends AsyncNotifier<List<Profile>> {
  ProfileStore get _store => ref.read(profileStoreProvider);

  @override
  Future<List<Profile>> build() => _store.load();

  Future<void> _persist(List<Profile> next) async {
    state = AsyncData(next);
    await _store.save(next);
  }

  Future<void> add(Profile p) async => _persist([...?state.value, p]);

  Future<void> replace(Profile p) async => _persist([
        for (final x in state.value ?? const <Profile>[])
          if (x.id == p.id) p else x,
      ]);

  Future<void> remove(String id) async => _persist([
        for (final x in state.value ?? const <Profile>[])
          if (x.id != id) x,
      ]);
}

/// What a profile entity would need at apply time, resolved against [system].
class EntityIssue {
  final EntitySnapshot entity;

  /// Involved speakers not currently present/reachable on the network.
  final List<String> missing;

  /// Involved speakers currently bonded in another role (auto-freed on apply).
  final List<String> conflicts;

  const EntityIssue(
      {required this.entity, required this.missing, required this.conflicts});

  bool get blocked => missing.isNotEmpty;
}

/// Pre-flight: resolves every entity's speakers against the live [system] so the
/// UI can show what will change and flag missing/conflicting speakers before any
/// destructive write.
List<EntityIssue> preflightProfile(Profile profile, SonosSystem system) {
  String label(String uuid) =>
      system.device(uuid)?.roomName ??
      profile.entities
          .map((e) => e.names[uuid])
          .firstWhere((n) => n != null, orElse: () => null) ??
      uuid;

  return [
    for (final e in profile.entities)
      EntityIssue(
        entity: e,
        missing: [
          for (final u in e.involvedUuids)
            if (system.device(u) == null || system.device(u)!.reachable == false)
              label(u),
        ],
        // A speaker is conflicting if it's currently bonded into ANY other
        // entity — HT satellite, stereo-pair half, OR zone/custom group member.
        // Uses the shared [SonosSystem.ownerOf] so pre-flight and apply agree.
        conflicts: [
          for (final u in e.involvedUuids)
            if (u != e.primaryUuid &&
                system.device(u) != null &&
                system.ownerOf(u) != null)
              label(u),
        ],
      ),
  ];
}
