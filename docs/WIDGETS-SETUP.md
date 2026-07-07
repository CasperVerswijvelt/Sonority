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

## iOS — one-time Xcode setup required

iOS home-screen widgets need a **WidgetKit extension target** and an **App
Group**, both created in Xcode (they can't be scripted — hand-editing
`project.pbxproj` to add a target breaks the build). Once done, the widget uses
the same `sonority://apply?id=…` deep link and the existing Dart handler.

### 1. App Group

1. `ios/Runner.xcworkspace` → **Runner** target → *Signing & Capabilities* → **+
   App Groups** → add `group.be.casperverswijvelt.sonority` (matches
   `_appGroupId` in `profile_widget.dart`).
2. Add the **same** group to the widget extension target (step 2).

### 2. Widget extension target

1. *File → New → Target… → Widget Extension* (uncheck "Include Live Activity").
   Name it `ProfileWidget` (matches `_iosWidgetName`).
2. Add the App Group capability to it (same id as above).
3. Add `home_widget` to the extension's Podfile target so it can read the shared
   store — in `ios/Podfile`:
   ```ruby
   target 'ProfileWidget' do
     use_frameworks!
     pod 'home_widget', :path => '.symlinks/plugins/home_widget/ios'
   end
   ```
   then `cd ios && pod install`.

### 3. Publish the profile list to the App Group (Dart)

The iOS widget picks its profile from a list the app shares. Add to
`profile_widget.dart` and call it from the `profilesProvider` listener in
`app.dart` (alongside `syncProfileShortcuts`) — harmless on Android:

```dart
Future<void> publishWidgetProfiles(List<Profile> profiles) async {
  final data = [
    for (final p in profiles)
      {'id': p.id, 'name': p.name, 'sf': sfSymbolName(p.iconId), 'color': p.color},
  ];
  await HomeWidget.saveWidgetData<String>('widget_profiles', jsonEncode(data));
  await HomeWidget.updateWidget(iOSName: _iosWidgetName);
}
```

(Expose `sfSymbolName(iconId)` from `profile_ui.dart` — the same `_sfSymbols`
map already used for shortcuts — so the widget and shortcut glyphs match.)

### 4. Widget SwiftUI + AppIntent (in the extension target)

Reference implementation for `ProfileWidget.swift`. `AppIntentConfiguration`
(iOS 17+) gives the long-press *Edit Widget → pick a profile* flow; its options
come from the shared list.

```swift
import WidgetKit
import SwiftUI
import AppIntents

private let appGroup = "group.be.casperverswijvelt.sonority"

struct ProfileOption: AppEntity, Identifiable {
  let id: String
  let name: String
  static var defaultQuery = ProfileQuery()
  var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Profile" }
}

struct ProfileQuery: EntityQuery {
  private func all() -> [ProfileOption] {
    guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: "widget_profiles"),
          let data = raw.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    return arr.compactMap { d in (d["id"] as? String).map { ProfileOption(id: $0, name: d["name"] as? String ?? "") } }
  }
  func entities(for ids: [String]) async -> [ProfileOption] { all().filter { ids.contains($0.id) } }
  func suggestedEntities() async -> [ProfileOption] { all() }
}

struct SelectProfileIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Choose profile"
  @Parameter(title: "Profile") var profile: ProfileOption?
}

struct Entry: TimelineEntry { let date: Date; let profile: ProfileOption? }

struct Provider: AppIntentTimelineProvider {
  func placeholder(in: Context) -> Entry { Entry(date: .now, profile: nil) }
  func snapshot(for c: SelectProfileIntent, in: Context) async -> Entry { Entry(date: .now, profile: c.profile) }
  func timeline(for c: SelectProfileIntent, in: Context) async -> Timeline<Entry> {
    Timeline(entries: [Entry(date: .now, profile: c.profile)], policy: .never)
  }
}

struct ProfileWidgetView: View {
  let entry: Entry
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "square.stack.3d.up") // swap per-profile if you share the SF name
      Text(entry.profile?.name ?? "Choose profile").font(.caption).lineLimit(1)
    }
    .widgetURL(entry.profile.map { URL(string: "sonority://apply?id=\($0.id)")! })
  }
}

@main
struct ProfileWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "ProfileWidget", intent: SelectProfileIntent.self, provider: Provider()) {
      ProfileWidgetView(entry: $0)
    }
    .configurationDisplayName("Sonority profile")
    .description("Apply a saved profile in one tap.")
    .supportedFamilies([.systemSmall])
  }
}
```

`widgetURL` makes the whole widget a deep link; `initiallyLaunchedFromHomeWidget`
/ `widgetClicked` in `initProfileWidget` already handle it. To show the
per-profile colour/SF glyph, extend `ProfileOption` with those fields from the
shared JSON and use them in the view.
