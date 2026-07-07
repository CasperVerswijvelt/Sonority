import AppIntents
import SwiftUI
import WidgetKit

// Home-screen widget: apply a saved profile in one tap. It only *reads* the
// profile list the app publishes to the shared App Group (no plugin needed);
// tapping deep-links `sonority://apply?id=…`, which the app routes into the
// apply flow (see profile_widget.dart `initProfileWidget`).

private let appGroup = "group.be.casperverswijvelt.sonority"

/// One profile as published by the app (`widget_profiles` JSON).
struct ProfileOption: AppEntity, Identifiable {
  let id: String
  let name: String
  let sf: String
  let colorHex: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Profile" }
  static var defaultQuery = ProfileQuery()
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

private func loadProfiles() -> [ProfileOption] {
  guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: "widget_profiles"),
    let data = raw.data(using: .utf8),
    let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
  else { return [] }
  return arr.compactMap { d in
    guard let id = d["id"] as? String else { return nil }
    return ProfileOption(
      id: id,
      name: d["name"] as? String ?? "",
      sf: d["sf"] as? String ?? "star.fill",
      colorHex: d["color"] as? String ?? "#5B6BF5")
  }
}

struct ProfileQuery: EntityQuery {
  func entities(for ids: [String]) async throws -> [ProfileOption] {
    loadProfiles().filter { ids.contains($0.id) }
  }
  func suggestedEntities() async throws -> [ProfileOption] { loadProfiles() }
  func defaultResult() async -> ProfileOption? { loadProfiles().first }
}

struct SelectProfileIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Choose profile"
  static var description = IntentDescription("Pick which profile this widget applies.")
  @Parameter(title: "Profile") var profile: ProfileOption?
}

struct ProfileEntry: TimelineEntry {
  let date: Date
  let profile: ProfileOption?
}

struct ProfileProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> ProfileEntry {
    ProfileEntry(date: Date(), profile: loadProfiles().first)
  }
  func snapshot(for configuration: SelectProfileIntent, in context: Context) async -> ProfileEntry {
    ProfileEntry(date: Date(), profile: configuration.profile ?? loadProfiles().first)
  }
  func timeline(for configuration: SelectProfileIntent, in context: Context) async -> Timeline<ProfileEntry> {
    Timeline(entries: [ProfileEntry(date: Date(), profile: configuration.profile ?? loadProfiles().first)], policy: .never)
  }
}

private extension Color {
  init(hex: String) {
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    self.init(
      .sRGB,
      red: Double((v >> 16) & 0xFF) / 255,
      green: Double((v >> 8) & 0xFF) / 255,
      blue: Double(v & 0xFF) / 255)
  }
}

struct ProfileWidgetView: View {
  let entry: ProfileEntry

  var body: some View {
    let p = entry.profile
    VStack(spacing: 6) {
      ZStack {
        Circle().fill(p.map { Color(hex: $0.colorHex) } ?? Color.gray)
        Image(systemName: p?.sf ?? "square.stack.3d.up")
          .font(.system(size: 22))
          .foregroundStyle(.white)
      }
      .frame(width: 48, height: 48)
      Text(p?.name ?? "Choose profile")
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(.primary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(p.flatMap { URL(string: "sonority://apply?id=\($0.id)") })
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

@main
struct ProfileWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "ProfileWidget",
      intent: SelectProfileIntent.self,
      provider: ProfileProvider()
    ) { entry in
      ProfileWidgetView(entry: entry)
    }
    .configurationDisplayName("Sonority profile")
    .description("Apply a saved profile in one tap.")
    .supportedFamilies([.systemSmall])
  }
}
