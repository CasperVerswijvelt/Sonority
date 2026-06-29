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

/// A short human description of what an entity snapshot bonds, resolving speaker
/// names against the live [system] when available (falling back to the names
/// captured at snapshot time, then the UUID). Used on profile tiles.
///
/// - HT: `Fronts: A, B · Surrounds: C, D · Sub: S`
/// - Pair: `A + B`
/// - Single: the model name (or "Standalone speaker").
String entitySummary(EntitySnapshot e, SonosSystem? system) {
  String nameOf(String uuid) =>
      system?.device(uuid)?.roomName ?? e.names[uuid] ?? 'Speaker';

  switch (e.kind) {
    case EntityKind.single:
      return system?.device(e.primaryUuid)?.modelName ?? 'Standalone speaker';

    case EntityKind.stereoPair:
      final uuids = e.involvedUuids.toList();
      if (uuids.length < 2) return 'Stereo pair';
      return '${nameOf(uuids[0])} + ${nameOf(uuids[1])}';

    case EntityKind.homeTheater:
      final map = e.mapSet;
      if (map == null) return e.kindLabel;
      final fronts = <String>[], surrounds = <String>[], sub = <String>[];
      // Skip the first entry (the soundbar primary / CC).
      for (final entry in ChannelMap.parse(map).entries.skip(1)) {
        for (final ch in entry.channels) {
          final bucket = switch (ch) {
            SonosChannel.leftFront || SonosChannel.rightFront => fronts,
            SonosChannel.leftRear || SonosChannel.rightRear => surrounds,
            SonosChannel.sub => sub,
            SonosChannel.center => null,
          };
          if (bucket != null && !bucket.contains(entry.uuid)) bucket.add(entry.uuid);
        }
      }
      final parts = <String>[
        if (fronts.isNotEmpty) 'Fronts: ${fronts.map(nameOf).join(', ')}',
        if (surrounds.isNotEmpty) 'Surrounds: ${surrounds.map(nameOf).join(', ')}',
        if (sub.isNotEmpty) 'Sub: ${sub.map(nameOf).join(', ')}',
      ];
      return parts.isEmpty ? 'Soundbar only' : parts.join(' · ');
  }
}
