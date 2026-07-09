import 'package:flutter/material.dart';
import 'package:flutter_sficon/flutter_sficon.dart';

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

/// Curated icon set a user can pick for a profile. Keys are stored in
/// [Profile.iconId]; the same glyph renders on the tile, widget, and (where the
/// OS allows) the app shortcut. Deliberately small — no arbitrary image upload.
const profileIconChoices = <String, IconData>{
  'speaker': Icons.speaker,
  'home_theater': Icons.surround_sound,
  'movie': Icons.movie,
  'music': Icons.music_note,
  'living': Icons.weekend,
  'tv': Icons.tv,
  'party': Icons.celebration,
  'night': Icons.nightlight_round,
};

/// Resolves a stored [Profile.iconId] to its Material glyph (falls back to the
/// default). Used for the Android UI + the Android launcher-icon bitmap.
IconData profileIcon(String iconId) =>
    profileIconChoices[iconId] ?? profileIconChoices[kDefaultProfileIcon]!;

/// Each curated icon's SF Symbol (iOS), matching the native quick-action glyph
/// so the in-app icon and the home-screen shortcut look the same on iOS.
const _profileSfIcons = <String, IconData>{
  'speaker': SFIcons.sf_hifispeaker,
  'home_theater': SFIcons.sf_tv,
  'movie': SFIcons.sf_film,
  'music': SFIcons.sf_music_note,
  'living': SFIcons.sf_sofa,
  'tv': SFIcons.sf_play_tv,
  'party': SFIcons.sf_party_popper,
  'night': SFIcons.sf_moon,
};

/// SF Symbol *name* for a profile icon — the string form for `systemImageName`
/// (iOS app-shortcut icon + home-screen widget). Same non-filled glyphs as
/// [_profileSfIcons]. Single source so shortcut + widget stay in sync.
const _sfSymbolNames = <String, String>{
  'speaker': 'hifispeaker',
  'home_theater': 'tv',
  'movie': 'film',
  'music': 'music.note',
  'living': 'sofa',
  'tv': 'play.tv',
  'party': 'party.popper',
  'night': 'moon',
};

String sfSymbolName(String iconId) => _sfSymbolNames[iconId] ?? 'star';

/// Key sets of the three hand-synced icon maps (Material [profileIconChoices],
/// iOS SFIcon [_profileSfIcons], SF-symbol names [_sfSymbolNames]) — exposed so
/// a test can assert they stay in sync. Drift silently falls back to a default
/// glyph, so the parity test guards against it.
@visibleForTesting
Set<String> get profileSfIconKeys => _profileSfIcons.keys.toSet();
@visibleForTesting
Set<String> get sfSymbolNameKeys => _sfSymbolNames.keys.toSet();

/// The SF Symbol [IconData] for a profile icon (falls back to a star). Used on
/// every platform now — profiles are visualised with SF Symbols throughout.
IconData profileSfIcon(String iconId) => _profileSfIcons[iconId] ?? SFIcons.sf_star;

/// The profile glyph as a widget — an SF Symbol on all platforms (profiles use
/// SF Symbols everywhere). SF renders larger/tighter than a Material icon at the
/// same point size, so scale down for the same visual weight + padding.
Widget profileGlyph(String iconId, {required double size, required Color color}) =>
    SFIcon(profileSfIcon(iconId), fontSize: size * 0.82, color: color);

/// Fixed accent palette a user can pick for a profile. [Profile.color] stores an
/// index into this list; white foreground reads well on every entry.
const profilePalette = <Color>[
  Color(0xFF5B6BF5), // indigo
  Color(0xFF00A3A3), // teal
  Color(0xFFEA6A2E), // orange
  Color(0xFFD2436E), // pink
  Color(0xFF7C4DFF), // purple
  Color(0xFF3F9142), // green
  Color(0xFF4B8DF8), // blue
  Color(0xFF9E6B1F), // amber
];

/// Resolves a stored [Profile.color] index to its accent (wraps defensively).
Color profileColor(int index) => profilePalette[index % profilePalette.length];

/// The "muted tonal" rendering of a profile: a soft card fill, a contrast-safe
/// icon in the accent, and a normal-weight label. Every surface (in-app tile,
/// appearance preview, Android shortcut, both widgets) uses this so the look is
/// identical — the iOS widget mirrors this in Swift (`tonal(...)`), and the
/// Android widget derives it natively from the published accent hex + brightness.
typedef ProfileTonal = ({Color card, Color icon, Color label});

ProfileTonal profileTonal(int colorIndex, Brightness brightness) {
  final a = profileColor(colorIndex);
  if (brightness == Brightness.dark) {
    const surface = Color(0xFF1B1B20);
    final card = Color.alphaBlend(a.withValues(alpha: 0.30), surface);
    return (
      card: card,
      icon: _ensureContrast(_mix(a, Colors.white, 0.30), card, toward: Colors.white),
      label: const Color(0xFFECECEF),
    );
  }
  const surface = Color(0xFFFBFBFD);
  final card = Color.alphaBlend(a.withValues(alpha: 0.14), surface);
  return (
    card: card,
    icon: _ensureContrast(a, card, toward: Colors.black),
    label: const Color(0xFF1D1D22),
  );
}

/// Shared tile-shape/size spec (replicated in the iOS Swift widget + the Android
/// native tile). Sizes that depend on the tile's short edge `s` are computed by
/// [glyphSize] / [labelSize]; the corner radius is fixed so it reads consistent
/// across widget sizes.
const double tileRadius = 20;
double glyphSize(double s) => (0.30 * s).clamp(18, 40);
double labelSize(double s) => (0.12 * s).clamp(11, 15);

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Nudges [fg] toward [toward] (black or white) until it clears ~3:1 against
/// [bg] — icons are large, so 3:1 is an ample legibility floor.
Color _ensureContrast(Color fg, Color bg, {required Color toward}) {
  var c = fg;
  for (var i = 0; i < 8 && _contrast(c, bg) < 3.0; i++) {
    c = _mix(c, toward, 0.12);
  }
  return c;
}

/// Compact 56×56 swatch showing a profile's icon on its colour; opens the
/// appearance picker on tap. Sits next to the name field on create + edit.
class AppearanceButton extends StatelessWidget {
  final String iconId;
  final int color;
  final VoidCallback onTap;
  const AppearanceButton(
      {super.key,
      required this.iconId,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = profileTonal(color, Theme.of(context).brightness);
    return InkWell(
      borderRadius: BorderRadius.circular(tileRadius),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(tileRadius),
        ),
        child: Center(child: profileGlyph(iconId, size: 26, color: t.icon)),
      ),
    );
  }
}

/// The profile card used in the Profiles overview and the widget picker — the
/// same card everywhere. [trailing] swaps the actions (Apply + menu on the
/// overview, a selection indicator in the picker); [selected] highlights it.
class ProfileCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool selected;

  /// Vertical placement of the row's children — the overview centres its Apply
  /// button; the picker top-aligns so its selection dot sits in the top-right.
  final CrossAxisAlignment crossAxisAlignment;

  const ProfileCard({
    super.key,
    required this.profile,
    this.onTap,
    this.trailing,
    this.selected = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tonal = profileTonal(profile.color, theme.brightness);
    final summary = profile.entities.map((e) => e.label).join(' · ');
    final settings = profile.settingsSummary;
    return Card(
      margin: EdgeInsets.zero,
      color: selected
          ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.12),
              scheme.surfaceContainerHigh)
          : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.primary, width: 1.5))
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, trailing == null ? 16 : 8, 12),
          child: Row(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: tonal.card,
                    borderRadius: BorderRadius.circular(tileRadius)),
                child: Center(
                    child: profileGlyph(profile.iconId,
                        size: 22, color: tonal.icon)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      summary.isEmpty ? 'No entities' : summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (settings.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.equalizer, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(settings,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.primary)),
                      ]),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + colour picker dialog. Returns the chosen `(iconId, color)`, or null if
/// cancelled. Shared by the create and edit screens.
Future<(String, int)?> showAppearanceDialog(BuildContext context,
    {required String iconId, required int color}) {
  var icon = iconId;
  var col = color;
  return showDialog<(String, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Appearance'),
        content: SingleChildScrollView(
          child: _AppearancePicker(
            iconId: icon,
            color: col,
            onIcon: (v) => setLocal(() => icon = v),
            onColor: (v) => setLocal(() => col = v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, (icon, col)),
              child: const Text('Done')),
        ],
      ),
    ),
  );
}

/// Icon + colour chips (dialog content). The icon swatches preview the selected
/// colour so the two choices read as one.
class _AppearancePicker extends StatelessWidget {
  final String iconId;
  final int color;
  final ValueChanged<String> onIcon;
  final ValueChanged<int> onColor;

  const _AppearancePicker({
    required this.iconId,
    required this.color,
    required this.onIcon,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tonal = profileTonal(color, theme.brightness);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final key in profileIconChoices.keys)
              _Swatch(
                selected: key == iconId,
                color: tonal.card,
                onTap: () => onIcon(key),
                child: profileGlyph(
                  key,
                  size: 22,
                  color: key == iconId
                      ? tonal.icon
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const Divider(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < profilePalette.length; i++)
              _Swatch(
                selected: i == color,
                color: profilePalette[i],
                filled: true,
                onTap: () => onColor(i),
                child: i == color
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ],
    );
  }
}

/// A 44×44 tappable circle used for both icon and colour choices.
class _Swatch extends StatelessWidget {
  final bool selected;
  final bool filled;
  final Color color;
  final Widget child;
  final VoidCallback onTap;

  const _Swatch({
    required this.selected,
    required this.color,
    required this.child,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Icon swatches fill only when selected; colour swatches are always filled.
    final fill =
        filled || selected ? color : theme.colorScheme.surfaceContainerHighest;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: theme.colorScheme.onSurface, width: 2)
              : null,
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Icon for a profile entity, matching the system-overview iconography.
IconData entityIcon(EntityKind kind) => switch (kind) {
      EntityKind.homeTheater => Icons.surround_sound,
      EntityKind.stereoPair => Icons.speaker_group,
      EntityKind.zone => Icons.groups_2,
      EntityKind.custom => Icons.tune,
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

    case EntityKind.zone:
      final uuids = e.involvedUuids.toList();
      if (uuids.length < 2) return 'Zone';
      return '${uuids.length} speakers: ${uuids.map(typeOf).join(', ')}';

    case EntityKind.custom:
      final map = e.mapSet;
      if (map == null) return 'Custom group';
      final tmp =
          ZoneGroupMember(uuid: e.primaryUuid, zoneName: '', channelMapSet: map);
      final ch = tmp.groupChannels.values.toList();
      final l = ch.where((c) => c == GroupChannel.left).length;
      final r = ch.where((c) => c == GroupChannel.right).length;
      final b = ch.where((c) => c == GroupChannel.both).length;
      final parts = [
        if (l > 0) 'L:$l',
        if (r > 0) 'R:$r',
        if (b > 0) 'Both:$b',
      ];
      return '${ch.length} speakers · ${parts.join(' ')}'
          '${tmp.subUuid != null ? ' · Sub' : ''}';

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
