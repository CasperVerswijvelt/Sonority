import 'package:flutter/material.dart';
import 'package:flutter_sficon/flutter_sficon.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../widgets/entity_glyph.dart';
import '../widgets/pill_chip.dart';
import 'profile.dart';

/// True if [name] (trimmed, case-insensitive) is already used by another
/// profile in [existing], excluding the profile with [exceptId] (the one being
/// edited). Used to keep profile names unique on create/rename.
bool isProfileNameTaken(
  List<Profile> existing,
  String name, {
  String? exceptId,
}) {
  final n = name.trim().toLowerCase();
  return existing.any(
    (p) => p.id != exceptId && p.name.trim().toLowerCase() == n,
  );
}

/// Curated icon ids a user can pick for a profile, in picker order. Stored in
/// [Profile.iconId]; each id resolves to an SF Symbol glyph ([profileSfIcon] /
/// [sfSymbolName]) on every platform. Deliberately small — no arbitrary image
/// upload.
const profileIconIds = [
  'speaker',
  'home_theater',
  'movie',
  'music',
  'living',
  'tv',
  'party',
  'night',
];

/// Each curated icon's SF Symbol — the glyph shown on every platform (in-app
/// tiles, widgets, shortcuts).
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

/// Key sets of the two hand-synced icon maps ([_profileSfIcons] and
/// [_sfSymbolNames]) — exposed so a test can assert they stay in sync with the
/// curated [profileIconIds]. Drift silently falls back to a default glyph, so
/// the parity test guards against it.
@visibleForTesting
Set<String> get profileSfIconKeys => _profileSfIcons.keys.toSet();
@visibleForTesting
Set<String> get sfSymbolNameKeys => _sfSymbolNames.keys.toSet();

/// The SF Symbol [IconData] for a profile icon (falls back to a star). Used on
/// every platform now — profiles are visualised with SF Symbols throughout.
IconData profileSfIcon(String iconId) =>
    _profileSfIcons[iconId] ?? SFIcons.sf_star;

/// The profile glyph as a widget — an SF Symbol on all platforms (profiles use
/// SF Symbols everywhere). SF renders larger/tighter than a Material icon at the
/// same point size, so scale down for the same visual weight + padding.
Widget profileGlyph(
  String iconId, {
  required double size,
  required Color color,
}) => SFIcon(profileSfIcon(iconId), fontSize: size * 0.82, color: color);

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
      icon: _ensureContrast(
        _mix(a, Colors.white, 0.30),
        card,
        toward: Colors.white,
      ),
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

// Tonal chips/tiles use the shared [kCardRadius] so their corner reads
// consistent with the app's cards; mirrored by the iOS Swift widget and the
// Android native tile, which also compute glyph/label sizes from the tile's
// short edge (`clamp(0.30·s, 18, 40)` / `clamp(0.12·s, 11, 15)`).

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
  const AppearanceButton({
    super.key,
    required this.iconId,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = profileTonal(color, Theme.of(context).brightness);
    return InkWell(
      borderRadius: BorderRadius.circular(kCardRadius),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(kCardRadius),
        ),
        child: Center(child: profileGlyph(iconId, size: 26, color: t.icon)),
      ),
    );
  }
}

/// The name row shared by the create and detail screens: the appearance swatch
/// (tap to edit icon/colour) beside the "Profile name" field. Owns the
/// appearance dialog so callers just react to the picked (iconId, color) via
/// [onAppearanceChanged]. The field pins [VisualDensity.standard] so its box
/// stays 56 = the swatch — desktop's compact density would otherwise shrink it
/// and knock the swatch off-centre (and make it jump when the error grows the
/// field). [onChanged] fires on every keystroke so the parent can recompute
/// [nameTaken].
class ProfileNameField extends StatelessWidget {
  final TextEditingController controller;
  final String iconId;
  final int color;
  final bool nameTaken;
  final VoidCallback onChanged;
  final void Function(String iconId, int color) onAppearanceChanged;

  const ProfileNameField({
    super.key,
    required this.controller,
    required this.iconId,
    required this.color,
    required this.nameTaken,
    required this.onChanged,
    required this.onAppearanceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppearanceButton(
          iconId: iconId,
          color: color,
          onTap: () async {
            final result = await showAppearanceDialog(
              context,
              iconId: iconId,
              color: color,
            );
            if (result != null) onAppearanceChanged(result.$1, result.$2);
          },
        ),
        Gap.s,
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.profileNameLabel,
              border: const OutlineInputBorder(),
              errorText: nameTaken ? context.l10n.profileNameTaken : null,
              visualDensity: VisualDensity.standard,
            ),
          ),
        ),
      ],
    );
  }
}

/// The profile card used in the Profiles overview and the widget picker — the
/// same card everywhere. [trailing] is the top-right slot (a selection dot in
/// the picker); [actions] is an optional bottom row (the overview's big Apply
/// button + menu). [selected] highlights it. Capture chips (what the snapshot
/// stores, including what it does NOT) sit on their own line, and "updated X
/// ago" shows when known.
class ProfileCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? actions;
  final bool selected;

  /// When true, [actions] cross-fade + collapse away (animated) — used by the
  /// Profiles reorder mode. Pass [actions] anyway so they can animate out.
  final bool actionsCollapsed;

  /// Vertical placement of the header row's children — the picker top-aligns so
  /// its selection dot sits in the top-right.
  final CrossAxisAlignment crossAxisAlignment;

  const ProfileCard({
    super.key,
    required this.profile,
    this.onTap,
    this.trailing,
    this.actions,
    this.selected = false,
    this.actionsCollapsed = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tonal = profileTonal(profile.color, theme.brightness);
    final summary = profile.entities.map((e) => e.label).join(' · ');
    return Card(
      color: selected
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.12),
              scheme.surfaceContainerHigh,
            )
          : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kCardRadius),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: crossAxisAlignment,
                children: [
                  EntityGlyph(
                    size: 48,
                    background: tonal.card,
                    child: profileGlyph(
                      profile.iconId,
                      size: 24,
                      color: tonal.icon,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary.isEmpty ? context.l10n.profileNoEntities : summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.mutedText,
                        ),
                        // Capture time as header metadata (grouped with the
                        // name/summary), with a clock glyph so it reads as a
                        // timestamp rather than floating loose in the card.
                        // ALWAYS rendered (invisible for legacy profiles with no
                        // timestamp) so every card is the SAME height — the
                        // reorder grid lays cards out on one measured height.
                        const SizedBox(height: 4),
                        Opacity(
                          opacity: profile.updatedAt == null ? 0 : 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                // A space (not '') when absent so the line keeps
                                // its full height → identical card height.
                                profile.updatedAt == null
                                    ? ' '
                                    : context.l10n.profileUpdatedAgo(
                                        timeAgo(context.l10n, profile.updatedAt!)),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    // Cross-fade when the trailing swaps (⋮ menu ↔ drag handle
                    // when toggling reorder mode).
                    AnimatedSwitcher(
                      duration: kShortAnim,
                      child: trailing!,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Capture chips on their own line so they never crowd the glyph or
              // wrap awkwardly beside it; includes what is NOT captured.
              profileCaptureChips(
                context,
                audio: profile.hasAudioSettings,
                volume: profile.hasVolume,
              ),
              // Cross-fade + collapse the actions row so toggling reorder mode
              // animates the buttons out (not just the empty space). The reorder
              // grid measures the changing height each frame and its rows follow.
              if (actions != null)
                AnimatedCrossFade(
                  duration: kShortAnim,
                  sizeCurve: Curves.easeInOut,
                  firstCurve: Curves.easeInOut,
                  secondCurve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  crossFadeState: actionsCollapsed
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: actions!,
                  ),
                  secondChild: const SizedBox(width: double.infinity),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The captured-settings pills ("Audio settings" / "Volume"), or null when
/// neither is set. Shared by the profile tile (aggregate) and the per-entity
/// cards on the detail screen. Uses the shared [PillChip] (the app's one tag
/// pill), tinted `secondary` so a captured-setting tag reads distinct from a
/// composition chip (which is `primary`).
Widget? settingsBadges(
  BuildContext context, {
  required bool audio,
  required bool volume,
}) {
  if (!audio && !volume) return null;
  final color = Theme.of(context).colorScheme.secondary;
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      if (audio)
        PillChip(
            icon: Icons.tune, text: context.l10n.profileBadgeAudio, color: color),
      if (volume)
        PillChip(
            icon: Icons.volume_up,
            text: context.l10n.profileBadgeVolume,
            color: color),
    ],
  );
}

/// The profile TILE's capture summary: what the snapshot stores. Layout & names
/// are always captured; audio/volume are opt-in, so those show a positive
/// (`secondary`) chip when captured and a muted (`onSurfaceVariant`) "not saved"
/// chip when not — so the tile states plainly what applying will and won't
/// restore. (The per-entity detail footer keeps [settingsBadges], positive-only.)
Widget profileCaptureChips(
  BuildContext context, {
  required bool audio,
  required bool volume,
}) {
  final scheme = Theme.of(context).colorScheme;
  final on = scheme.secondary;
  final off = scheme.onSurfaceVariant;
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      PillChip(
        icon: Icons.check,
        text: context.l10n.profileChipLayoutNames,
        color: scheme.primary,
      ),
      audio
          ? PillChip(
              icon: Icons.tune, text: context.l10n.profileChipSettings, color: on)
          : PillChip(
              icon: Icons.tune,
              text: context.l10n.profileChipNoSettings,
              color: off),
      volume
          ? PillChip(
              icon: Icons.volume_up,
              text: context.l10n.profileBadgeVolume,
              color: on)
          : PillChip(
              icon: Icons.volume_off,
              text: context.l10n.profileChipNoVolume,
              color: off),
    ],
  );
}

/// Compact relative time ("just now", "3 days ago", "2 weeks ago") for the
/// profile tile's "updated X ago" line. No date dependency — a small ladder;
/// each unit is a localized ICU plural.
String timeAgo(AppLocalizations l10n, DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return l10n.profileTimeJustNow;
  if (d.inMinutes < 60) return l10n.profileTimeMinutesAgo(d.inMinutes);
  if (d.inHours < 24) return l10n.profileTimeHoursAgo(d.inHours);
  if (d.inDays < 7) return l10n.profileTimeDaysAgo(d.inDays);
  if (d.inDays < 30) return l10n.profileTimeWeeksAgo(d.inDays ~/ 7);
  if (d.inDays < 365) return l10n.profileTimeMonthsAgo(d.inDays ~/ 30);
  return l10n.profileTimeYearsAgo(d.inDays ~/ 365);
}

/// Icon + colour picker dialog. Returns the chosen `(iconId, color)`, or null if
/// cancelled. Shared by the create and edit screens.
Future<(String, int)?> showAppearanceDialog(
  BuildContext context, {
  required String iconId,
  required int color,
}) {
  var icon = iconId;
  var col = color;
  return showDialog<(String, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(context.l10n.profileAppearance),
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
            child: Text(context.l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, (icon, col)),
            child: Text(context.l10n.actionDone),
          ),
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
            for (final key in profileIconIds)
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
    final fill = filled || selected
        ? color
        : theme.colorScheme.surfaceContainerHighest;
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
