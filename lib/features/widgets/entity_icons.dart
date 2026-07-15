import 'package:flutter/material.dart';

import '../../data/models/sonos_models.dart';

/// Icon for a bonded speaker-group kind. The single source of truth shared by
/// the system overview (`_GroupCard`) and the profile views (`entityIcon`), so
/// the two can never drift. All group kinds share the speaker-group icon — the
/// kind is spelled out in each card's subtitle (`groupKindLabel`) instead. The
/// label mapping lives in `sonos_models.dart` (pure Dart); the icon can't, since
/// `IconData` is a Flutter type and the engine stays Flutter-free.
IconData groupKindIcon(GroupKind kind) => switch (kind) {
      GroupKind.stereoPair ||
      GroupKind.zone ||
      GroupKind.custom =>
        Icons.speaker_group,
      GroupKind.none => Icons.speaker,
    };
