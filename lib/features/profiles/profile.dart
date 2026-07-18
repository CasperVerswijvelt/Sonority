import '../../core/l10n.dart';
import '../../data/models/sonos_models.dart';
import '../../data/sonos/speaker_settings.dart';

/// Default icon key for a profile (see `profileIconIds` in `profile_ui.dart`).
const kDefaultProfileIcon = 'speaker';

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

  /// UUID → captured audio settings (EQ, optionally volume), restored on apply.
  /// Empty when the profile was created without the "save speaker settings"
  /// toggle (or from an older app version) — an empty map means zero extra
  /// writes on apply.
  final Map<String, SpeakerSettings> settings;

  const EntitySnapshot({
    required this.kind,
    required this.primaryUuid,
    required this.mapSet,
    required this.names,
    this.settings = const {},
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

  // Context-less (this getter is read from widgets), so it resolves strings via
  // the shared [appL10n] helper. Reuses the app-wide entity-kind keys — the same
  // labels the state layer's progress steps use.
  String get kindLabel {
    final l10n = appL10n();
    return switch (kind) {
      EntityKind.homeTheater => l10n.entityKindHomeTheater,
      EntityKind.stereoPair => l10n.entityKindStereoPair,
      EntityKind.zone => l10n.entityKindZone,
      EntityKind.custom => l10n.entityKindCustom,
      EntityKind.single => l10n.entityKindSpeaker,
    };
  }

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

  EntitySnapshot copyWith({
    Map<String, String>? names,
    Map<String, SpeakerSettings>? settings,
  }) =>
      EntitySnapshot(
        kind: kind,
        primaryUuid: primaryUuid,
        mapSet: mapSet,
        names: names ?? this.names,
        settings: settings ?? this.settings,
      );

  /// Whether this entity captured any audio settings / volume — drive the
  /// per-entity chips on the detail screen (mirrors [Profile]'s aggregates).
  bool get hasAudioSettings =>
      settings.values.any((s) => s.hasAudioSettings);
  bool get hasVolume => settings.values.any((s) => s.hasVolume);

  /// A throwaway [ZoneGroupMember] carrying the stored map string, so the shared
  /// entity cards (`EntityCardModel`) and the entity detail sheet can reuse the
  /// model's parsing getters against snapshot data. The single blessed place for
  /// this trick — HT maps go in `htSatChanMapSet`, group maps in `channelMapSet`,
  /// a single has neither.
  ZoneGroupMember toMember() => ZoneGroupMember(
        uuid: primaryUuid,
        zoneName: label,
        htSatChanMapSet: kind == EntityKind.homeTheater ? mapSet : null,
        channelMapSet: kind == EntityKind.homeTheater ? null : mapSet,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'primaryUuid': primaryUuid,
        'mapSet': mapSet,
        'names': names,
        // Omit when empty so profiles without settings stay compact.
        if (settings.isNotEmpty)
          'settings': {for (final e in settings.entries) e.key: e.value.toJson()},
      };

  factory EntitySnapshot.fromJson(Map<String, dynamic> j) => EntitySnapshot(
        kind: EntityKind.values.byName(j['kind'] as String),
        primaryUuid: j['primaryUuid'] as String,
        mapSet: j['mapSet'] as String?,
        names: Map<String, String>.from(j['names'] as Map),
        // Absent in older profiles → empty (no settings restored).
        settings: {
          for (final e in ((j['settings'] as Map?) ?? const {}).entries)
            e.key as String:
                SpeakerSettings.fromJson(Map<String, dynamic>.from(e.value as Map)),
        },
      );
}

/// A named, ordered set of entity snapshots the user can re-apply in one tap.
class Profile {
  final String id;
  final String name;
  final List<EntitySnapshot> entities;

  /// Appearance for the tile / widget / shortcut: a key into the curated icon
  /// set and an index into the fixed palette (see `profile_ui.dart`). Defaults
  /// keep pre-feature stored profiles rendering fine.
  final String iconId;
  final int color;

  const Profile({
    required this.id,
    required this.name,
    required this.entities,
    this.iconId = kDefaultProfileIcon,
    this.color = 0,
  });

  /// Aggregated across entities — drive the badges on the profile tile.
  bool get hasAudioSettings => entities.any((e) => e.hasAudioSettings);
  bool get hasVolume => entities.any((e) => e.hasVolume);

  Profile copyWith({
    String? name,
    List<EntitySnapshot>? entities,
    String? iconId,
    int? color,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        entities: entities ?? this.entities,
        iconId: iconId ?? this.iconId,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconId': iconId,
        'color': color,
        'entities': entities.map((e) => e.toJson()).toList(),
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        // Absent in pre-feature profiles → curated defaults.
        iconId: j['iconId'] as String? ?? kDefaultProfileIcon,
        color: j['color'] as int? ?? 0,
        entities: [
          for (final e in (j['entities'] as List))
            EntitySnapshot.fromJson(e as Map<String, dynamic>)
        ],
      );
}
