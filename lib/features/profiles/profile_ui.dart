import 'package:flutter/material.dart';

import '../../data/models/sonos_models.dart';
import '../../data/sonos/channel_map.dart';
import 'profile.dart';

/// True if [name] (trimmed, case-insensitive) is already used by another
/// profile in [existing], excluding the profile with [exceptId] (the one being
/// edited). Used to keep profile names unique on create/rename.
bool isProfileNameTaken(List<Profile> existing, String name, {String? exceptId}) {
  final n = name.trim().toLowerCase();
  return existing.any((p) => p.id != exceptId && p.name.trim().toLowerCase() == n);
}

/// Icon for a profile entity, matching the system-overview iconography.
IconData entityIcon(EntityKind kind) => switch (kind) {
      EntityKind.homeTheater => Icons.surround_sound,
      EntityKind.stereoPair => Icons.speaker_group,
      EntityKind.single => Icons.speaker,
    };

/// A short human description of what an entity snapshot bonds, by speaker TYPE
/// (the room names just echo the entity name, so the type is the useful detail).
/// Resolves types against the live [system]; falls back to the captured room
/// name only when the device isn't currently present.
///
/// - HT: `Fronts: One SL, One SL · Surrounds: Play:1, Play:1 · Subwoofer: Sub`
/// - Pair: `Play:1 + Play:1`
/// - Single: the type (or "Standalone speaker").
String entitySummary(EntitySnapshot e, SonosSystem? system) {
  String typeOf(String uuid) =>
      system?.device(uuid)?.typeLabel ?? e.names[uuid] ?? 'Speaker';

  switch (e.kind) {
    case EntityKind.single:
      return system?.device(e.primaryUuid)?.typeLabel ?? 'Standalone speaker';

    case EntityKind.stereoPair:
      final uuids = e.involvedUuids.toList();
      if (uuids.length < 2) return 'Stereo pair';
      return '${typeOf(uuids[0])} + ${typeOf(uuids[1])}';

    case EntityKind.homeTheater:
      final map = e.mapSet;
      if (map == null) return e.kindLabel;
      final fronts = <String>[], surrounds = <String>[], sub = <String>[];
      final fSeen = <String>{}, sSeen = <String>{}, wSeen = <String>{};
      // Skip the first entry (the soundbar primary / CC). One type per distinct
      // speaker (an Amp on both fronts shows once; two Play:1 surrounds show
      // twice — "Play:1, Play:1").
      for (final entry in ChannelMap.parse(map).entries.skip(1)) {
        for (final ch in entry.channels) {
          switch (ch) {
            case SonosChannel.leftFront || SonosChannel.rightFront:
              if (fSeen.add(entry.uuid)) fronts.add(typeOf(entry.uuid));
            case SonosChannel.leftRear || SonosChannel.rightRear:
              if (sSeen.add(entry.uuid)) surrounds.add(typeOf(entry.uuid));
            case SonosChannel.sub:
              if (wSeen.add(entry.uuid)) sub.add(typeOf(entry.uuid));
            case SonosChannel.center:
              break;
          }
        }
      }
      final parts = <String>[
        if (fronts.isNotEmpty) 'Fronts: ${fronts.join(', ')}',
        if (surrounds.isNotEmpty) 'Surrounds: ${surrounds.join(', ')}',
        if (sub.isNotEmpty) 'Subwoofer: ${sub.join(', ')}',
      ];
      return parts.isEmpty ? 'Soundbar only' : parts.join(' · ');
  }
}
