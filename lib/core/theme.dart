import 'package:flutter/material.dart';

/// Material 3 theming for Sonority. Full light/dark support; callers may
/// override with platform dynamic color (Material You) where available.
class AppTheme {
  static ThemeData light([ColorScheme? dynamicScheme]) =>
      _build(dynamicScheme ?? _lightFallback);

  static ThemeData dark([ColorScheme? dynamicScheme]) =>
      _build(dynamicScheme ?? _darkFallback);

  // Fallback schemes for platforms without Material You (iOS/macOS). These are
  // the EXACT schemes Android's `dynamic_color` produces from the Pixel
  // emulator wallpaper (seed ≈ 0xFF475D92) — captured verbatim rather than
  // re-derived via `fromSeed`, because the dynamic palette flattens every
  // `surfaceContainer*` role to one tone and `fromSeed` does not, which is what
  // made macOS diverge. Keep in sync if the reference look changes.
  static const _lightFallback = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF475D92),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD9E2FF),
    onPrimaryContainer: Color(0xFF001945),
    secondary: Color(0xFF575E71),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDCE2F9),
    onSecondaryContainer: Color(0xFF151B2C),
    tertiary: Color(0xFF725572),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFDD7FA),
    onTertiaryContainer: Color(0xFF2A122C),
    error: Color(0xFFBB0947),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDDADE),
    onErrorContainer: Color(0xFF400013),
    surface: Color(0xFFFEFBFF),
    onSurface: Color(0xFF1A1B20),
    onSurfaceVariant: Color(0xFF44464F),
    surfaceContainerHighest: Color(0xFFFEFBFF),
    surfaceContainerHigh: Color(0xFFFEFBFF),
    surfaceContainer: Color(0xFFFEFBFF),
    surfaceContainerLow: Color(0xFFFEFBFF),
    surfaceContainerLowest: Color(0xFFFEFBFF),
    surfaceDim: Color(0xFFFEFBFF),
    surfaceBright: Color(0xFFFEFBFF),
    outline: Color(0xFF757780),
    outlineVariant: Color(0xFFC5C6D0),
    inverseSurface: Color(0xFF2F3036),
    onInverseSurface: Color(0xFFF1F0F7),
    inversePrimary: Color(0xFFB0C6FF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF475D92),
  );

  static const _darkFallback = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFB0C6FF),
    onPrimary: Color(0xFF152E60),
    primaryContainer: Color(0xFF2F4578),
    onPrimaryContainer: Color(0xFFD9E2FF),
    secondary: Color(0xFFC0C6DC),
    onSecondary: Color(0xFF2A3042),
    secondaryContainer: Color(0xFF404659),
    onSecondaryContainer: Color(0xFFDCE2F9),
    tertiary: Color(0xFFE0BBDD),
    onTertiary: Color(0xFF412742),
    tertiaryContainer: Color(0xFF593D59),
    onTertiaryContainer: Color(0xFFFDD7FA),
    error: Color(0xFFFCB4BD),
    onError: Color(0xFF670023),
    errorContainer: Color(0xFF910034),
    onErrorContainer: Color(0xFFFCB4BD),
    surface: Color(0xFF1A1B20),
    onSurface: Color(0xFFE2E2E9),
    onSurfaceVariant: Color(0xFFC5C6D0),
    surfaceContainerHighest: Color(0xFF1A1B20),
    surfaceContainerHigh: Color(0xFF1A1B20),
    surfaceContainer: Color(0xFF1A1B20),
    surfaceContainerLow: Color(0xFF1A1B20),
    surfaceContainerLowest: Color(0xFF1A1B20),
    surfaceDim: Color(0xFF1A1B20),
    surfaceBright: Color(0xFF1A1B20),
    outline: Color(0xFF8F9099),
    outlineVariant: Color(0xFF44464F),
    inverseSurface: Color(0xFFE2E2E9),
    onInverseSurface: Color(0xFF2F3036),
    inversePrimary: Color(0xFF475D92),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFFB0C6FF),
  );

  static ThemeData _build(ColorScheme scheme) {
    // The page background must sit clearly BELOW the cards / bottom nav (both
    // `surfaceContainerHigh`). Dynamic-colour dark palettes flatten the
    // container tones, so in dark mode we blend the surface toward black to
    // guarantee that contrast; light mode keeps its (already lighter) surface.
    final pageBg = scheme.brightness == Brightness.dark
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.35), scheme.surface)
        : scheme.surface;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Center glyphs within their line box on every platform. The macOS system
      // font (SF) puts most of its line leading ABOVE the glyph, so text sits a
      // few px low in tiles/cards there; "even" splits the leading top/bottom so
      // it looks vertically centered cross-platform (Android already does this).
      textTheme: _evenLeading(
          ThemeData(useMaterial3: true, colorScheme: scheme).textTheme),
      scaffoldBackgroundColor: pageBg,
      appBarTheme: AppBarTheme(
        backgroundColor: pageBg,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        // Fully flat, top and bottom. The scroll-under affordance is a hairline
        // (AppScaffold's ScrolledUnderDivider), matching the flat nav-bar line —
        // no shadow, no tint.
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: scheme.shadow,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      // Cards: a lifted container tone PLUS a hairline outline so they always
      // read as distinct panels — dynamic-colour palettes flatten the container
      // tones, so tone alone isn't enough separation from the page.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      // A distinct bottom nav surface (the top divider is added in the shell).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        // Match the card radius so a tile's hover/tap ink follows the card
        // outline instead of a tighter, more-rounded corner inside it.
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(kCardRadius))),
      ),
    );
  }

  /// Returns [t] with every style set to [TextLeadingDistribution.even] so the
  /// glyph is vertically centered within its line box (fixes macOS SF text
  /// sitting low in tiles/cards).
  static TextTheme _evenLeading(TextTheme t) {
    TextStyle? e(TextStyle? s) =>
        s?.copyWith(leadingDistribution: TextLeadingDistribution.even);
    return t.copyWith(
      displayLarge: e(t.displayLarge),
      displayMedium: e(t.displayMedium),
      displaySmall: e(t.displaySmall),
      headlineLarge: e(t.headlineLarge),
      headlineMedium: e(t.headlineMedium),
      headlineSmall: e(t.headlineSmall),
      titleLarge: e(t.titleLarge),
      titleMedium: e(t.titleMedium),
      titleSmall: e(t.titleSmall),
      bodyLarge: e(t.bodyLarge),
      bodyMedium: e(t.bodyMedium),
      bodySmall: e(t.bodySmall),
      labelLarge: e(t.labelLarge),
      labelMedium: e(t.labelMedium),
      labelSmall: e(t.labelSmall),
    );
  }
}

/// Shared corner radius for cards / tiles / tinted panels — the single source
/// so the value can't drift across `cardTheme`, tiles and ad-hoc `circular(20)`.
const double kCardRadius = 20;

/// The app's standard page/sheet horizontal gutter — the value screens pad
/// their content by, matching a card's internal padding for a shared rhythm.
const double kPageGutter = 16;

/// Vertical gap between stacked cards in a list (applied as a card `margin` /
/// bottom padding, so it's a `double` rather than a [Gap] SizedBox).
const double kCardGap = 12;

/// Width at/above which the UI switches to its wide (desktop/large-window)
/// layout: a left `NavigationRail` instead of the bottom nav bar, and content
/// centered within a max width. Below it, the single-column phone layout. The
/// only responsive breakpoint in the app — keep width branches keyed to it.
const double kWideLayoutBreakpoint = 720;

/// Max width a single-column page clamps to on a wide layout, so lists don't
/// stretch edge-to-edge across a desktop window. The System overview overrides
/// this with a wider cap (it lays cards out in multiple columns instead).
const double kContentMaxWidth = 720;

/// Wide-overview cap — roomier than [kContentMaxWidth] so the entity-card grid
/// gets several columns.
const double kOverviewMaxWidth = 1100;

/// A zone with at least this many bonded speakers gets a "can drop out" warning.
/// Heuristic from hardware: an 8-speaker Play:1-era zone kept dropping even after
/// settling, so the practical ceiling is well below Sonos' claimed 16.
const int kZoneWarnSize = 5;

/// Shared spacing scale (each a square [SizedBox], so it works as height OR
/// width).
class Gap {
  static const xs = SizedBox(height: 4, width: 4);
  static const s = SizedBox(height: 8, width: 8);
  static const m = SizedBox(height: 16, width: 16);
  static const l = SizedBox(height: 24, width: 24);
}

/// Named text styles shared across the UI, so a recurring style is declared
/// once instead of re-`copyWith`-ing it at every call site.
extension AppTextStyles on ThemeData {
  /// The muted helper/caption style: small body text in the muted
  /// on-surface-variant colour. The most-repeated inline style in the app
  /// (helper paragraphs, subtitles, empty/hint lines).
  TextStyle? get mutedText =>
      textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);
}
