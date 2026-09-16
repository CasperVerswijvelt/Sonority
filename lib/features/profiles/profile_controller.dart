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

/// What a profile apply would FREE for entity [e] against the live [system] —
/// the exact arguments `SonosController._applyEntity` hands `_freeConflicts`.
///
/// Shared so pre-flight and apply cannot disagree. They did: apply moved to
/// [SonosSystem.mustFreeBeforeBonding] while pre-flight kept an owner-based
/// test, so a profile whose group had since GROWN (`{A,B}` captured, `{A,B,C}`
/// live) reported zero conflicts — no confirm dialog — and the apply then
/// dissolved the live zone, costing C its name and its tuning.
({Set<String> uuids, Set<String> keep, bool absorbing}) entityFreePlan(
    EntitySnapshot e, SonosSystem system) {
  const nothing = (uuids: <String>{}, keep: <String>{}, absorbing: false);
  switch (e.kind) {
    case EntityKind.single:
      // Freed unconditionally by apply — including when it IS the primary,
      // which the old pre-flight skipped outright.
      return (uuids: {e.primaryUuid}, keep: const <String>{}, absorbing: false);
    case EntityKind.homeTheater:
      final map = e.mapSet;
      if (map == null) return nothing; // apply throws malformedHomeTheater
      final live = system.memberByUuid(e.primaryUuid);
      return (
        // The bar is entry 0 and is never freed from itself.
        uuids: ChannelMap.parse(map).entries.skip(1).map((x) => x.uuid).toSet(),
        // An HT is not absorbable, so its own current members must be kept or
        // an unchanged re-apply would strip the bond it is rebuilding.
        keep: {e.primaryUuid, if (live != null) ...system.bondMemberUuids(live)},
        absorbing: true,
      );
    case EntityKind.stereoPair:
    case EntityKind.zone:
    case EntityKind.custom:
      final involved = e.involvedUuids;
      final live = system.memberByUuid(e.primaryUuid);
      final current = live?.channelMapUuids ?? const <String>[];
      // Already exactly this group ⇒ apply returns before freeing anything.
      if (live != null &&
          live.isGroup &&
          current.length == involved.length &&
          current.toSet().containsAll(involved)) {
        return nothing;
      }
      return (
        uuids: involved,
        // Only a rebuild that can re-assert over the live group keeps it;
        // otherwise the whole bond is dissolved first.
        keep: groupEditIsInPlace(
          currentUuids: current,
          targetUuids: involved.toList(),
          targetCoordUuid: e.primaryUuid,
        )
            ? current.toSet()
            : const <String>{},
        absorbing: false,
      );
  }
}

/// The speakers a profile apply would free for [e] — the pre-flight half of
/// [entityFreePlan], asked with the same `keep`/`absorbing` the apply passes.
List<String> _conflicts(
    EntitySnapshot e, SonosSystem system, String Function(String) label) {
  final plan = entityFreePlan(e, system);
  return [
    for (final u in plan.uuids)
      if (system.device(u) != null &&
          system.mustFreeBeforeBonding(u,
              keep: plan.keep, absorbing: plan.absorbing))
        label(u),
  ];
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
        // A speaker is conflicting exactly when the apply would FREE it — a
        // destructive write that dissolves whatever bond it sits in.
        conflicts: _conflicts(e, system, label),
      ),
  ];
}
