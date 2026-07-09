import AppIntents
import SwiftUI
import WidgetKit

// Home-screen widget: apply saved profiles in one tap. It only *reads* the
// profile list the app publishes to the shared App Group (no plugin needed);
// tapping a tile deep-links `sonority://apply?homeWidget=1&id=…`, which the app
// routes into the apply flow (see profile_widget.dart `initProfileWidget`).
//
// The widget holds a user-picked SET of profiles (Edit Widget). Small shows the
// first one full-bleed; medium/large lay the picks out as a row/grid of tiles,
// each independently tappable via its own `Link`.

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
    let byId = Dictionary(loadProfiles().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    // Preserve the caller's id order (the user's chosen tile order).
    return ids.compactMap { byId[$0] }
  }
  func suggestedEntities() async throws -> [ProfileOption] { loadProfiles() }
}

struct SelectProfileIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Choose profiles"
  static var description = IntentDescription("Pick the profiles this widget shows.")
  @Parameter(title: "Profiles") var profiles: [ProfileOption]
}

struct ProfileEntry: TimelineEntry {
  let date: Date
  let profiles: [ProfileOption]
}

struct ProfileProvider: AppIntentTimelineProvider {
  /// The picks, or — when unconfigured / a selection wasn't delivered — every
  /// published profile, so the widget is never blank.
  private func resolved(_ configuration: SelectProfileIntent?) -> [ProfileOption] {
    let picked = configuration?.profiles ?? []
    return picked.isEmpty ? loadProfiles() : picked
  }
  func placeholder(in context: Context) -> ProfileEntry {
    ProfileEntry(date: Date(), profiles: loadProfiles())
  }
  func snapshot(for configuration: SelectProfileIntent, in context: Context) async -> ProfileEntry {
    ProfileEntry(date: Date(), profiles: resolved(configuration))
  }
  func timeline(for configuration: SelectProfileIntent, in context: Context) async -> Timeline<ProfileEntry> {
    Timeline(entries: [ProfileEntry(date: Date(), profiles: resolved(configuration))], policy: .never)
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

/// Deep link for one profile. home_widget's iOS side only recognises URLs
/// carrying a `homeWidget` query item (see HomeWidgetPlugin.isWidgetUrl); without
/// it the tap is silently ignored. Single source so no tile drops the marker.
private func applyURL(id: String) -> URL? {
  URL(string: "sonority://apply?homeWidget=1&id=\(id)")
}

/// Best rows×cols to pack `n` equal squares into a `w`×`h` box so the square
/// side is as large as possible. Same logic mirrored on Android.
private func bestGrid(_ n: Int, _ w: CGFloat, _ h: CGFloat) -> (cols: Int, rows: Int) {
  guard n > 1, w > 0, h > 0 else { return (max(1, n), 1) }
  var best = (cols: 1, rows: n, side: 0.0)
  for cols in 1...n {
    let rows = Int(ceil(Double(n) / Double(cols)))
    let side = min(w / CGFloat(cols), h / CGFloat(rows))
    if side > best.side { best = (cols, rows, side) }
  }
  return (best.cols, best.rows)
}

private let tileGap: CGFloat = 8

// --- Muted-tonal treatment (mirrors Dart `profileTonal` so iOS matches the app
// + the Android widget): a soft card tint, a contrast-safe accent glyph, a
// normal-weight label. Colours are computed from the published accent hex.
private typealias RGB = (r: Double, g: Double, b: Double)
struct Tones { let card: Color; let icon: Color; let label: Color }

private func hexRGB(_ hex: String) -> RGB {
  let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
  var v: UInt64 = 0
  Scanner(string: s).scanHexInt64(&v)
  return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}
private func lerpRGB(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
  (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
}
private func lumRGB(_ c: RGB) -> Double {
  func ch(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
}
private func contrastRGB(_ a: RGB, _ b: RGB) -> Double {
  let la = lumRGB(a), lb = lumRGB(b)
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}
private func ensureContrast(_ fg: RGB, _ bg: RGB, toward: RGB) -> RGB {
  var c = fg, i = 0
  while i < 8 && contrastRGB(c, bg) < 3.0 { c = lerpRGB(c, toward, 0.12); i += 1 }
  return c
}
private func rgbColor(_ c: RGB) -> Color { Color(.sRGB, red: c.r, green: c.g, blue: c.b) }

private func widgetTonal(_ hex: String, _ scheme: ColorScheme) -> Tones {
  let a = hexRGB(hex)
  let white: RGB = (1, 1, 1), black: RGB = (0, 0, 0)
  if scheme == .dark {
    let card = lerpRGB((0.106, 0.106, 0.125), a, 0.30)
    return Tones(card: rgbColor(card),
                 icon: rgbColor(ensureContrast(lerpRGB(a, white, 0.30), card, toward: white)),
                 label: Color(white: 0.925))
  }
  let card = lerpRGB((0.984, 0.984, 0.992), a, 0.14)
  return Tones(card: rgbColor(card),
               icon: rgbColor(ensureContrast(a, card, toward: black)),
               label: rgbColor((0.114, 0.114, 0.133)))
}

private func clampCG(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(x, lo), hi) }

/// One profile's visual — a muted-tonal rounded card, accent glyph, normal label.
/// Fills its cell (`width`×`height`, possibly non-square); glyph/label are sized
/// from the shorter edge with a cap (so large widgets don't get oversized icons).
struct ProfileTile: View {
  @Environment(\.colorScheme) private var scheme
  let profile: ProfileOption
  let width: CGFloat
  let height: CGFloat
  private var unit: CGFloat { min(width, height) }

  var body: some View {
    let t = widgetTonal(profile.colorHex, scheme)
    VStack(spacing: clampCG(unit * 0.06, 3, 10)) {
      Image(systemName: profile.sf)
        // Sized to visually match the Android tile (SF renders larger than
        // Material at the same point size); regular weight, not semibold.
        .font(.system(size: clampCG(unit * 0.30, 18, 40) * 0.68, weight: .regular))
        .foregroundStyle(t.icon)
        .widgetAccentable()
      Text(profile.name)
        .font(.system(size: clampCG(unit * 0.12, 11, 15) * 0.95, weight: .regular))
        .foregroundStyle(t.label)
        .lineLimit(1)
        .padding(.horizontal, 4)
    }
    // Show the real glyph + name in the widget gallery too (default placeholder
    // redaction would grey them out).
    .unredacted()
    .frame(width: width, height: height)
    .background(t.card)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

struct ProfileWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ProfileEntry

  var body: some View {
    content
      // Soft neutral canvas (HIG: avoid a hard white fill; tiles carry the colour).
      .containerBackground(Color(.secondarySystemBackground), for: .widget)
      // systemSmall supports only one tap target (Link is ignored there), so the
      // whole widget applies the first tile; medium/large tap per-tile via Link.
      .widgetURL(family == .systemSmall ? entry.profiles.first.flatMap { applyURL(id: $0.id) } : nil)
  }

  @ViewBuilder private var content: some View {
    if entry.profiles.isEmpty {
      placeholder
    } else {
      GeometryReader { geo in
        let n = entry.profiles.count
        let g = bestGrid(n, geo.size.width, geo.size.height)
        // Tiles fill their cells so the grid fills the widget with a uniform gap
        // on every edge and between tiles (cells may be slightly non-square).
        let cellW = max(0, (geo.size.width - tileGap * CGFloat(g.cols + 1)) / CGFloat(g.cols))
        let cellH = max(0, (geo.size.height - tileGap * CGFloat(g.rows + 1)) / CGFloat(g.rows))
        VStack(alignment: .leading, spacing: tileGap) {
          ForEach(0..<g.rows, id: \.self) { r in
            HStack(spacing: tileGap) {
              ForEach(rowSlice(r, cols: g.cols), id: \.id) { p in cell(p, cellW, cellH) }
            }
          }
        }
        // Uniform outer margin equal to the between-tile gap; short last row
        // aligns left (under the first column).
        .padding(tileGap)
      }
    }
  }

  private func rowSlice(_ row: Int, cols: Int) -> [ProfileOption] {
    let start = row * cols
    return Array(entry.profiles[start..<min(start + cols, entry.profiles.count)])
  }

  @ViewBuilder private func cell(_ p: ProfileOption, _ cellW: CGFloat, _ cellH: CGFloat) -> some View {
    let tile = ProfileTile(profile: p, width: cellW, height: cellH)
    // small: tap handled by the whole-widget widgetURL (Link is a no-op there).
    if family == .systemSmall {
      tile
    } else if let url = applyURL(id: p.id) {
      Link(destination: url) { tile }
    } else {
      tile
    }
  }

  private var placeholder: some View {
    VStack(spacing: 8) {
      Image(systemName: "square.stack.3d.up")
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(.secondary)
      Text("Choose profiles")
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    .configurationDisplayName("Sonority profiles")
    .description("Apply saved profiles in one tap.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    // We control all spacing (equal edges + gaps); drop WidgetKit's default
    // content margins so the outer gap isn't doubled.
    .contentMarginsDisabled()
  }
}
