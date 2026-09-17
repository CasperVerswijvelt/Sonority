import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sonos_models.dart';
import '../../data/sonos/channel_map.dart';
import '../../data/sonos/front_layout.dart';
import 'profile.dart';
import 'profile_store.dart';

final profileStoreProvider = Provider<ProfileStore>((ref) => ProfileStore());

/// The profile id an out-of-app entry point (app shortcut / home-screen widget)
/// asked to apply, or null. It's a single funnel: every launch producer just
/// sets this, and one top-level listener (in `app.dart`) reacts — running the
/// scan→preflight→apply flow — then clears it. Kept out of any screen so apply
/// works regardless of which tab is showing.
final pendingApplyProvider =
    NotifierProvider<PendingApplyController, String?>(PendingApplyController.new);

class PendingApplyController extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

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

  /// Reorders the list (drag in the Profiles overview) and persists. This order
  /// is the canonical profile order — widgets render their picked tiles in it.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final next = [...?state.value];
    if (oldIndex < 0 || oldIndex >= next.length) return;
    // newIndex arrives already adjusted for the removed item (onReorderItem
    // semantics), so no manual `-1` here — it would double-shift downward drags.
    next.insert(newIndex.clamp(0, next.length - 1), next.removeAt(oldIndex));
    await _persist(next);
  }
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

/// True when the live [system] already carries this snapshot's layout AND room
/// name — i.e. applying it would issue no bonding/rename write. Layout + name
/// only: captured EQ/volume is readable over SOAP only, never from cached
/// topology, so "active" means the configuration is in place, not that every
/// captured setting is in effect.
bool entityIsActive(EntitySnapshot e, SonosSystem system) {
  // Visible members only — a bonded satellite / hidden pair half isn't one, so a
  // snapshot whose primary got absorbed elsewhere is correctly inactive.
  final live = system.memberByUuid(e.primaryUuid);
  if (live == null || e.names[e.primaryUuid] != live.zoneName) return false;
  final map = e.mapSet;
  // The stored map read through the shared parsing getters (snapshot → member).
  final snap = e.toMember();
  return switch (e.kind) {
    EntityKind.single => system.isStandalone(e.primaryUuid),
    EntityKind.homeTheater => map != null &&
        live.isHomeTheater &&
        diffHtLayout(current: live, target: ChannelMap.parse(map)).isNoOp,
    EntityKind.stereoPair || EntityKind.zone || EntityKind.custom => map != null &&
        live.matchesGroupLayout(snap.groupChannels, subUuid: snap.subUuid),
  };
}

/// Whether every entity of [p] is currently live (see [entityIsActive]) — drives
/// the "Active" badge on the profile tile. Two profiles can both be active when
/// they cover disjoint entities; that's truthful, not a bug.
bool profileIsActive(Profile p, SonosSystem system) =>
    p.entities.isNotEmpty && p.entities.every((e) => entityIsActive(e, system));

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
        // A speaker is conflicting only if it's currently bonded into a
        // DIFFERENT entity — i.e. its owner is outside this entity. A speaker
        // already bonded to this entity's own coordinator is NOT a conflict
        // (apply is a no-op for it). Mirrors the exact owner checks in
        // [SonosController._applyEntity] so pre-flight and apply agree.
        conflicts: [
          for (final u in e.involvedUuids)
            if (u != e.primaryUuid &&
                system.device(u) != null &&
                switch (system.ownerOf(u)) {
                  null => false,
                  final owner => !e.involvedUuids.contains(owner),
                })
              label(u),
        ],
      ),
  ];
}
