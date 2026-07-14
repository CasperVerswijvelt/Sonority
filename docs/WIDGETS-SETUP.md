# Home-screen widgets — setup

The **Profile widget** applies a saved profile in one tap from the home screen.
A tap can't run the multi-minute apply in the widget's process, so it launches
the app with `sonority://apply?homeWidget=1&id=<profileId>`, which Flutter routes
into the same apply flow as an app shortcut (`initProfileWidget` in
`lib/features/profiles/profile_widget.dart`).

## Sizes & multiple profiles

Each widget holds a **user-picked set of profiles** (not just one) and comes in
**small / medium / large**. Every size lays the picks out as a row/grid of tiles;
on medium/large **each tile is its own tap target** (deep-links that tile's `id`),
while small allows only one tap target (an OS limit) — tapping it applies the
first pick. The picked set is chosen when the widget is placed / edited.

## Tile appearance (muted tonal)

Tiles use one shared "muted tonal" treatment across every surface (in-app tile,
appearance picker, both widgets, Android shortcut): a soft tint of the profile
colour as the card, the icon in the (contrast-guarded) accent colour, and the name
in the normal on-surface colour — adapting to light/dark. The derivation lives in
`profileTonal` (`profile_ui.dart`) and is mirrored in `ProfileTonal` (Kotlin) +
`widgetTonal` (Swift) so all three match. Corner radius is a shared 20. Glyph/label
sizing differs by platform: **iOS** scales to the tile — glyph
`clamp(0.30·shortEdge, 18, 40)`, label `clamp(0.12·shortEdge, 11, 15)`; **Android**
uses a fixed 40dp glyph + 13sp label (the weight-filled `RemoteViews` grid doesn't
expose the cell's px, and scaling would drag back the launcher-size pixel math the
grid removed — see `profile_tile_cell.xml`). On Android the glyph is a white PNG
tinted at runtime + a native label; on iOS the SF glyph is `.widgetAccentable()` so
it stays clean on an iOS-18 tinted Home Screen. **Reordering lives in the Profiles tab**
(long-press a card to drag; that order is canonical and the widgets render their
picked tiles in it) — the widget config screen is select-only, reusing the same
`ProfileCard` with a checkmark/empty-circle selection indicator. **Glyphs are SF
Symbols on every platform**
(via `flutter_sficon`; `profileSfIcon`/`profileGlyph`) — note Apple's SF Symbols
license technically covers Apple platforms only. Both widgets sit on a **neutral
container card** that adapts light/dark (iOS `.containerBackground`; Android
`@drawable/widget_container` + `@android:id/background`, `@color/widget_container`
with a `values-night` variant). The tile radius is the container radius **minus the
8dp gap** so the cards nest concentrically — fixed 28/20dp on Android
(`res/values/dimens.xml`; deliberately NOT the launcher's system radii, so the
corners match the iOS tiles). The Android config picker follows the system
light/dark theme (`ThemeMode.system`). **Reorder:** both pickers are select-only.
On Android tile order is the Profiles-tab order; iOS can't reorder an array
parameter in the Edit sheet (Apple limitation), so order = selection order there.

- **iOS** — fixed families (`.systemSmall/.systemMedium/.systemLarge`). The picks
  live in the `SelectProfileIntent`'s `profiles: [ProfileOption]` array parameter;
  *Edit Widget* renders an add/remove picker sourced from the shared
  `widget_profiles` list (order = selection order; the Edit sheet can't reorder an
  array parameter — an Apple limitation). ⚠️ **Migration:** renaming the old single
  `profile`
  parameter to `profiles` orphans widgets placed by an earlier build — they fall
  back to showing the published profiles until re-edited once (harmless).
- **Android** — free resize (`resizeMode="horizontal|vertical"`).
  `ProfileWidgetProvider` builds a weight-filled grid (a vertical `LinearLayout` of
  weighted rows, each holding weighted tile cells) so the tiles fill the widget
  exactly at any size — no reading of the launcher-reported pixel size (which
  varies by launcher/size and used to cause left-anchored dead space, clipped
  corners, or gap drift). `bestGrid` only picks the rows×cols split. Widgets placed
  by an earlier build lazily migrate on next profile change (`profileIds_<id>` JSON
  with a `profileId_<id>` single-key fallback).

## Android — done, no manual step

Fully wired in this repo:

- `ProfileWidgetProvider.kt` — `HomeWidgetProvider`; builds the weighted-`LinearLayout`
  grid via `RemoteViews.addView` (rows and tile cells split height/width by
  `layout_weight`), tints each tile from its accent colour (`ProfileTonal`), and
  gives each tile its own tap-to-apply `PendingIntent`
  (`sonority://apply?homeWidget=1&id=<profileId>`).
- `ProfileWidgetConfigActivity.kt` — runs the `widgetConfig` Dart entrypoint
  (a multi-select profile picker) when the widget is placed.
- `res/layout/profile_widget.xml` (rounded container + vertical grid + empty view),
  `res/layout/profile_widget_row.xml` (a weighted row), `res/layout/profile_tile_cell.xml`
  (a weighted tile), `res/layout/profile_widget_spacer.xml` (pads a short last row),
  `res/xml/profile_widget_info.xml`, and the `<receiver>` + `<activity>` in
  `AndroidManifest.xml`.

Per-widget data (the ordered `profileIds_<widgetId>` JSON) is keyed by widget id in
`home_widget`'s shared prefs; each profile's colour tile + glyph is rendered in
Flutter (`renderFlutterWidget`, keyed `tile_<profileId>`) and shown via `RemoteViews`.

## iOS — wired in this repo

The WidgetKit extension target, App Group, and shared-data publish are **already
committed** (the extension target was added to `Runner.xcodeproj` with the
`xcodeproj` gem, not by hand). It runs on the **simulator with no extra steps**.

What's in the repo:

- `ios/ProfileWidget/ProfileWidget.swift` — SwiftUI widget + `AppIntentConfiguration`
  (iOS 17+); the long-press *Edit Widget → pick profiles* flow (a `[ProfileOption]`
  array parameter). Reads the shared `widget_profiles` JSON and renders each pick's
  colour tile + SF glyph across small/medium/large; small uses `widgetURL`,
  medium/large a `Link` per tile — both `sonority://apply?homeWidget=1&id=…`.
- `ios/ProfileWidget/{Info.plist,ProfileWidget.entitlements}` and
  `ios/Runner/Runner.entitlements` — both carry the App Group
  `group.be.casperverswijvelt.sonority`.
- `ProfileWidget` target in `Runner.xcodeproj` (embedded in Runner; "Embed App
  Extensions" ordered before the CocoaPods embed to avoid a build cycle).
- Dart: `publishWidgetProfiles` (in `profile_widget.dart`) writes the profile
  list to the App Group on every profile change (wired in `app.dart`);
  `sfSymbolName` in `profile_ui.dart` is the shared glyph map.

Verified on the simulator: the extension registers with the system
(`pluginkit -mv` lists `be.casperverswijvelt.sonority.ProfileWidget`) and appears
in the widget gallery as "Sonority profiles".

### ⚠️ iOS 26 Simulator doesn't deliver the widget's profile selection

Confirmed an **iOS 26 Simulator regression**, not a bug in this code:

- **iOS 17.2 Simulator — works fully**: picking a profile in *Edit Widget* is
  reflected in the widget and its tap applies that profile.
- **iOS 26.5 Simulator — broken**: *Edit Widget* remembers the pick in its own UI,
  but the widget always renders/applies the first profile. Traced with `os_log`:
  `suggestedEntities` fires (the picker lists every profile) yet the chosen value
  is never delivered to the timeline — `entities(for:)` is never called and
  `configuration.profiles` stays empty (the provider then falls back to showing all
  published profiles). A full simulator reboot didn't help.

The App Intents metadata (`SelectProfileIntent` / `ProfileOption` / `ProfileQuery`)
is correct, so the per-widget selection works on a real device / older simulator;
only the iOS 26 Simulator drops it. (Rendering + tap→apply work everywhere.)

### The one manual bit: signing for a real device / release

Simulator needs nothing. For a **physical device / TestFlight / App Store**, in
Xcode → each target's *Signing & Capabilities*:

1. Set the **Development Team** on the **ProfileWidget** target (Runner already
   has one).
2. Ensure the App Group `group.be.casperverswijvelt.sonority` is registered on
   the Apple Developer account and enabled on both the Runner and ProfileWidget
   provisioning profiles (Xcode's automatic signing does this once the capability
   is present, which it is).

CI note: `ios/exportOptions`/match may need the extension's bundle id
(`be.casperverswijvelt.sonority.ProfileWidget`) and the App Group added.
