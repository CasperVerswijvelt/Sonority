# Changelog

All notable changes to Sonority are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releasing: before tagging `vX.Y.Z-<rebuild>` (e.g. `v0.5.0-12` for build
50012), rename `[Unreleased]` below to `[X.Y.Z] - YYYY-MM-DD`. CI copies that
section into the GitHub Release notes regardless of the build suffix
(see `.github/workflows/release.yml`).

## [0.5.0] - 2026-07-11

### Added
- **Dual Subs** — a home theater can now bond **two Subs**, with both shown in the
  layout diagram and re-applied from a profile.
- **Profiles capture & restore per-speaker EQ** — a profile can snapshot each
  speaker's EQ (bass/treble/loudness, night sound, speech enhancement, sub,
  surround levels, lip-sync delay) and, as a separate opt-in, its **volume**,
  then re-apply them after the layout settles. Save/restore only — there are no
  EQ/volume sliders (that would duplicate the Sonos app).
- **Re-snapshot a profile** — update an existing profile in place from the
  current setup, without recreating it.
- **Speaker groups** — one "Group speakers" page (Stereo / Zone / Custom) to bond
  2–16 speakers as a **stereo pair**, a full-range **zone**, or a **custom**
  per-speaker Left/Right/Both layout, each with an **optional Sub**. Mismatched
  models welcome; not restricted to Sonos' official model list (Play:1 and a
  Sub-in-group both confirmed working on hardware, audio routing verified).
  Separate restores original room names; groups are captured in config profiles.
  (Distinct from temporary playback groups, which the Sonos app already does.)
- **Config profiles** — snapshot your current layout (home theaters, speaker
  groups, rooms, with their names) and re-apply it in one tap, e.g. to rebuild a
  fronts/surrounds setup after moving speakers. A dedicated bottom tab.
- **Apply a profile from an app shortcut** — long-press the app icon to apply a
  saved profile in one tap. The shortcut opens the app and runs the apply,
  scanning your system first and asking for confirmation only when some speakers
  are missing or in use by another setup.
- **Per-profile icon & colour** — pick an icon and colour for each profile,
  shown on its tile, in the editor, and on its app shortcut (a full-colour glyph
  on Android, a matching SF Symbol on iOS).
- **Home-screen widgets** — place a widget showing a hand-picked set of profiles
  (small/medium/large) and apply any of them in one tap. Tiles use a muted tonal
  look that adapts to light/dark; reorder profiles in the Profiles tab by
  long-pressing a card.
- **Full in-app home-theater setup** — the guided flow now bonds dedicated
  fronts plus **rear surrounds and a sub** (each optional), with a live
  per-step progress timeline showing the active step and exactly where it
  failed. Applied with staged bonding (re-asserted until Sonos converges).
- **Room renaming** from the room and home-theater detail pages.
- **Identify a speaker by blinking its status LED** — works on every platform,
  including macOS (the audio chime stays as a mobile-only extra).
- Standalone **Subs are now shown in the overview** so a free Sub is easy to spot
  and add to a home theater or group.

### Changed
- UI overhaul: collapsing large-title app bars, a stepped stereo-pair creation
  flow, distinct card/nav-bar surfaces on a darker page background, and speaker
  **types** (e.g. "Beam (Gen 2)", "Play:1") shown wherever a model appears —
  in diagrams, bonded-speaker cards, and profile summaries.
- System overview re-sectioned: home theaters → speaker groups → single speaker
  rooms → other devices, with a compact "+" in the Speaker groups header.
- Speaker groups now have a **tappable detail view**, and the configure-bond flow
  **pre-selects the current layout** so it opens on what's actually bonded.
- The **app version** is shown as a tappable chip in the discovery app bar — it
  opens a dialog with the full version and build number, this changelog, and a
  link to the GitHub project.
- Discovery **auto-scans on launch** — the separate landing page is gone.
- Applying a home theater or profile now diffs against the live layout and only
  changes what moved — faster, and an unchanged layout re-applies with no writes.
- Trueplay: the "x/y active" counter is hidden for single speakers (shown only
  for home theaters and stereo pairs).
- The apply/profile progress timeline is now **two-level** — each phase's
  sub-steps are nested under the entity they act on, so it's clear what's
  happening and exactly where it failed.
- The apply progress timeline now marks no-op steps as **skipped** (grey dot +
  reason, e.g. "layout unchanged — nothing to do", "name unchanged — nothing to
  do") instead of showing them as completed work, so a re-apply that changed
  nothing is honest about it. The entity itself keeps its green checkmark — it's
  still in the desired state.
- Detail pages show the **entity type as an app-bar subtitle** (speaker model
  for a room, "Home theater", or the speaker-group kind).
- Profile creation warns before overwriting, and applying a profile is guarded
  against re-entrant taps.
- Profiles: the EQ capture toggle is now **"Save audio settings"** — the label
  undersold a bundle that also covers night sound, speech enhancement, sub &
  surround levels and lip sync. Profile cards now show separate **Audio
  settings** / **Volume** badges (instead of one combined "EQ" line) and use an
  icon-only play button with a bit more breathing room.
- Profiles and widgets now share one visual language: SF Symbol glyphs on every
  platform and soft colour-tinted (tonal) cards instead of bold full-colour
  fills.
- Re-snapshot moved to an app-bar action on the profile detail page.
- Switching bottom-nav tabs (System ↔ Profiles) now animates with a Material 3
  shared-axis transition (fade + slide), sliding the way the tab bar moves.
- Consistent, flat separation for the top app bar and bottom navigation bar. The
  nav bar now shows a hairline dividing it from the page and cards (it was
  meant to but never rendered), and the app bar matches with a hairline that
  appears only while content scrolls under it — replacing its drop shadow, so
  every screen's chrome reads as flat and line-based.
- The macOS `.dmg` download now opens a styled drag-to-Applications install
  window — the app icon, an arrow, and an Applications shortcut over a branded
  background — instead of a bare disk image.

### Fixed
- **Discovery on iPhone** — the TestFlight build could hang on "Scanning your
  network" and fail: real iPhones silently block the multicast discovery
  packets (a restricted Apple entitlement the app doesn't carry; the simulator
  doesn't enforce it). When multicast finds nothing, discovery now falls back
  to directly probing the local network for Sonos players — which only needs
  the local-network permission the app already asks for. This also helps
  mesh/guest networks that filter multicast.
- The "couldn't find your system" screen no longer shows a raw `Exception:`
  prefix on its message, and its title now centres correctly when it wraps to
  two lines — so an empty network reads as a normal state, not a crash.
- The system overview no longer drifts to the vertical centre during the
  scan/rescan transition — short (non-scrolling) content now stays pinned to
  the top throughout the animation instead of floating to the middle and
  snapping back.
- macOS: the window is kept within the visible frame so the Dock can no longer
  clip it.
- Tap highlights on list rows now follow the card's rounded corners instead of
  rendering as a rectangle.

### Packaging
- iOS and macOS are now available via **TestFlight**; the macOS direct download
  is a **Developer ID-signed, notarized `.dmg`** (no Gatekeeper workaround) and
  the Android APK is **release-signed**.
- Release CI restructured into clear, per-platform jobs (Android, iOS sideload,
  iOS TestFlight, macOS `.dmg`, macOS TestFlight, GitHub Release).

## [0.4.0] - 2026-06-28

### Added
- **Trueplay (room calibration) read + toggle** on home theaters, stereo pairs
  and standalone rooms. Tuning is still measured in the Sonos app on iOS;
  Sonority reads the stored result and switches it on/off — including for the
  unofficial dedicated-fronts setups the Sonos app won't expose.
- Detail screen for stereo pairs and standalone rooms.

### Changed
- "Create stereo pair" is now a filled call-to-action button.
- Home-theater and room detail pages show a spinner on refresh and reload
  Trueplay status, not just the topology.
- GitHub Release notes are now generated from this changelog.

### Notes
- Sonos invalidates a speaker's Trueplay when its bonded set changes (adding or
  removing fronts), so a tuning may need to be redone after a layout change —
  a firmware limitation, not a Sonority bug.

## [0.3.0] - 2026-06-27

### Added
- App icon and splash screen (parametric Sonos 5.1 surround mark).
- Support a single **Sonos Amp** as the dedicated fronts (drives both front
  channels).
- Google Play Store listing graphics (icon, feature graphic, phone + tablet
  screenshots).
- CI now signs the release **App Bundle** and publishes it to the Google Play
  internal testing track on version tags.

## [0.2.0] - 2026-06-19

### Added
- **Stereo pairs**, including mismatched / app-blocked models (e.g. One + Play:1),
  with original room names restored on separation.
- Release CI: APK plus unsigned iOS and macOS artifacts on `v*` tags, with
  per-platform install instructions in the release.

### Changed
- Renamed the app from SoYes to **Sonority**.

## [0.1.0] - 2026-06-18

### Added
- Initial release: discover the Sonos system and add/remove dedicated front
  left/right speakers on a home theater via the local UPnP API, with
  identify-by-chime to tell speakers apart.
