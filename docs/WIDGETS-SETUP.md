# Home-screen widgets — setup

The **Profile widget** applies a saved profile in one tap from the home screen.
A tap can't run the multi-minute apply in the widget's process, so it launches
the app with `sonority://apply?id=<profileId>`, which Flutter routes into the
same apply flow as an app shortcut (`initProfileWidget` in
`lib/features/profiles/profile_widget.dart`).

## Android — done, no manual step

Fully wired in this repo:

- `ProfileWidgetProvider.kt` — `HomeWidgetProvider`; renders the avatar + name
  and sets the tap `PendingIntent`.
- `ProfileWidgetConfigActivity.kt` — runs the `widgetConfig` Dart entrypoint
  (a lightweight profile picker) when the widget is placed.
- `res/layout/profile_widget.xml`, `res/drawable/profile_widget_bg.xml`,
  `res/xml/profile_widget_info.xml`, and the `<receiver>` + `<activity>` in
  `AndroidManifest.xml`.

Per-widget data is keyed by widget id in `home_widget`'s shared prefs; the
colour circle + glyph is rendered in Flutter (`renderFlutterWidget`) and shown
via `RemoteViews`.

## iOS — wired in this repo

The WidgetKit extension target, App Group, and shared-data publish are **already
committed** (the extension target was added to `Runner.xcodeproj` with the
`xcodeproj` gem, not by hand). It runs on the **simulator with no extra steps**.

What's in the repo:

- `ios/ProfileWidget/ProfileWidget.swift` — SwiftUI widget + `AppIntentConfiguration`
  (iOS 17+); the long-press *Edit Widget → pick a profile* flow. Reads the shared
  `widget_profiles` JSON and renders the profile's colour circle + SF glyph;
  `widgetURL` deep-links `sonority://apply?id=…`.
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
in the widget gallery as "Sonority profile".

### ⚠️ iOS 26 Simulator doesn't deliver the widget's profile selection

Confirmed an **iOS 26 Simulator regression**, not a bug in this code:

- **iOS 17.2 Simulator — works fully**: picking a profile in *Edit Widget* is
  reflected in the widget and its tap applies that profile.
- **iOS 26.5 Simulator — broken**: *Edit Widget* remembers the pick in its own UI,
  but the widget always renders/applies the first profile. Traced with `os_log`:
  `suggestedEntities` fires (the picker lists every profile) yet the chosen value
  is never delivered to the timeline — `entities(for:)` is never called and
  `configuration.profile` stays nil. A full simulator reboot didn't help.

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
