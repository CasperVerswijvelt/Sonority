import '../../data/models/sonos_models.dart';

/// What kind of bonded entity a snapshot captures. One visible
/// [ZoneGroupMember] == one selectable entity.
enum EntityKind { homeTheater, stereoPair, zone, custom, single }

/// An immutable snapshot of one "entity" (a home theater, a stereo pair, or a
/// single unbonded speaker) as it was at capture time — just the authoritative
/// map string(s) the engine round-trips, plus the room names to restore.
class EntitySnapshot {
  final EntityKind kind;

  /// HT coordinator / stereo-pair primary (left) / the single speaker's UUID.
  final String primaryUuid;

  /// HT: the `HTSatChanMapSet`. Pair: the `ChannelMapSet`. Single: null.
  final String? mapSet;

  /// UUID → desired room name (restored on apply). Always includes [primaryUuid].
  final Map<String, String> names;

  const EntitySnapshot({
    required this.kind,
    required this.primaryUuid,
    required this.mapSet,
    required this.names,
  });

  /// Captures the visible [member]'s current layout.
  factory EntitySnapshot.fromMember(ZoneGroupMember member) {
    final kind = member.isHomeTheater
        ? EntityKind.homeTheater
        : switch (member.groupKind) {
            GroupKind.stereoPair => EntityKind.stereoPair,
            GroupKind.zone => EntityKind.zone,
            GroupKind.custom => EntityKind.custom,
            GroupKind.none => EntityKind.single,
          };
    return EntitySnapshot(
      kind: kind,
      primaryUuid: member.uuid,
      mapSet: switch (kind) {
        EntityKind.homeTheater => member.htSatChanMapSet,
        EntityKind.stereoPair ||
        EntityKind.zone ||
        EntityKind.custom =>
          member.channelMapSet,
        EntityKind.single => null,
      },
      // Just the coordinator (= group) name. A group absorbs its members'
      // individual names; whatever profile later turns them back into single
      // rooms restores those.
      names: {member.uuid: member.zoneName},
    );
  }

  /// A short human label for the create checklist + profile tiles.
  String get label => names[primaryUuid] ?? primaryUuid;

  String get kindLabel => switch (kind) {
        EntityKind.homeTheater => 'Home theater',
        EntityKind.stereoPair => 'Stereo pair',
        EntityKind.zone => 'Zone',
        EntityKind.custom => 'Custom group',
        EntityKind.single => 'Speaker',
      };

  /// Every UUID this entity bonds — used for pre-flight resolution + conflict
  /// detection. For an HT that's the coordinator + all satellites; for a pair
  /// both halves; for a single just itself.
  Set<String> get involvedUuids =>
      kind == EntityKind.single ? {primaryUuid} : _mapUuids().toSet();

  /// UUIDs parsed from [mapSet] (`UUID:CH...;UUID:CH...`), primary first.
  List<String> _mapUuids() {
    final raw = mapSet;
    if (raw == null || raw.isEmpty) return [primaryUuid];
    return [
      for (final part in raw.split(';'))
        if (part.contains(':')) part.split(':').first.trim()
    ].where((u) => u.isNotEmpty).toList();
  }

  EntitySnapshot copyWith({Map<String, String>? names}) => EntitySnapshot(
        kind: kind,
        primaryUuid: primaryUuid,
        mapSet: mapSet,
        names: names ?? this.names,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'primaryUuid': primaryUuid,
        'mapSet': mapSet,
        'names': names,
      };

  factory EntitySnapshot.fromJson(Map<String, dynamic> j) => EntitySnapshot(
        kind: EntityKind.values.byName(j['kind'] as String),
        primaryUuid: j['primaryUuid'] as String,
        mapSet: j['mapSet'] as String?,
        names: Map<String, String>.from(j['names'] as Map),
      );
}

/// A named, ordered set of entity snapshots the user can re-apply in one tap.
class Profile {
  final String id;
  final String name;
  final List<EntitySnapshot> entities;

  const Profile({required this.id, required this.name, required this.entities});

  Profile copyWith({String? name, List<EntitySnapshot>? entities}) => Profile(
        id: id,
        name: name ?? this.name,
        entities: entities ?? this.entities,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'entities': entities.map((e) => e.toJson()).toList(),
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        entities: [
          for (final e in (j['entities'] as List))
            EntitySnapshot.fromJson(e as Map<String, dynamic>)
        ],
      );
}
