# Changelog

All notable changes to Sonority are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releasing: before tagging `vX.Y.Z-<rebuild>` (e.g. `v0.5.0-12` for build
50012), rename `[Unreleased]` below to `[X.Y.Z] - YYYY-MM-DD`. CI copies that
section into the GitHub Release notes regardless of the build suffix
(see `.github/workflows/release.yml`).

## [Unreleased]

### Changed
- UI consistency pass: the Profiles list now aligns to the same page gutter as the other screens, share/save and empty-state layouts use consistent sizing, and short animations share one duration — plus removed a few redundant theme overrides that just restated Flutter defaults. No behaviour change.

## [0.6.0] - 2026-07-17

### Added
- Profiles can be reordered: tap the reorder button in the Profiles app bar, then drag a tile. Works at every width, with screen-reader move actions.
- Responsive layout for wide windows and iPad: the bottom tabs become an expanded left navigation rail (with a vertical tab transition), content fills the width, and card lists flow into 2–3 columns across the overview, Profiles, detail pages and setup flows. The macOS window is now resizable (it was locked to a fixed phone size). The app also runs natively on iPad in any orientation, including Split View. Phones are unchanged.
- Profiles: tap an entity in a profile to open a detail view — the system-overview layout (home-theater diagram / per-speaker channel cards) plus a per-speaker breakdown of every saved audio setting and volume. Profile tiles are roomier too: the capture summary sits on its own line spelling out what a profile does and doesn't store, shows "Updated X ago", and has a full-width Apply button.
- Diagnostics: a new bottom-bar tab with a hide-nothing technical view of your system (hidden speakers, IPs, MAC addresses, firmware). Package it, the raw topology, raw device info, your saved profiles, a per-speaker EQ/volume/mute snapshot and app logs into a zip to share, email to the developer, or save to disk. App logs and network info are optional toggles.
- Identify a speaker (blink its LED, plus a test chime on iOS/Android for standalone speakers) directly from the room and speaker-group detail views — a bonded speaker shows LED-only, since a chime would play the whole bond.
- Standalone rooms can jump straight into a setup: the room page has "Group with another speaker" and "Add to a home theater" shortcuts.
- Localization groundwork: every user-facing string now runs through Flutter's localization system and the app follows the device language. English is the only bundled language for now — a new one is added by dropping in a translation file, no code changes. No visible change yet.

### Changed
- Navigation is predictable: everything you can act on — a home theater, a speaker group, or a single room — opens as a full page, and bottom sheets are reserved for read-only peeks (a profile's captured-entity view, and the version/changelog viewer). The home-theater setup flow is a step within a home theater's page; only the from-scratch group-creation flow covers the tabs.
- UI refresh so different concepts look different: entity tiles share one rounded-square glyph and show their makeup with pills instead of a run-on "· · ·" subtitle; every "pick speakers" list uses one flat checkbox style; the group-creation review shows per-speaker cards instead of a text list; settings (Trueplay, a profile's saved per-speaker settings) render as flat, divider-led rows rather than cards; plus unified card radius, page gutters, spacing, section headers and a single muted-text style.
- The home-theater setup is now titled "Configure home theater" (matching the shorter, settings-cog "Configure" button that opens it, in place of the sliders/EQ glyph reserved for audio controls). The flow sets each front/surround speaker's left vs right side with an in-card toggle (mirroring the group flow), replacing the separate rows that didn't take.
- Detail-page polish: the home-theater diagram stretches to a wide window's full width at a fixed height (instead of blowing up); destructive/primary actions (a group's "Separate", a room's group / home-theater shortcuts and Trueplay toggle) sit at the bottom of the page; a profile's "Re-capture from current setup" moved above the captured list; and group / room speaker lists get a "Speakers" heading.
- Profile editing is a single save surface: the profile screen keeps you on the page after saving (with a toast) instead of jumping to the list, and re-snapshot recaptures the current setup as an unsaved change you review and commit with Save, instead of instantly overwriting.
- Renamed the home-theater "Remove all extra speakers" button to "Separate" (with a "Separate home theater?" confirmation), consistent with the speaker-groups wording.
- The bonding progress screen's Done button is now colored by result (green on success, red on failure/abort). On a partial failure it shows a plain-English reason for errors we recognize (full detail still in the raw log) and reassures you it's safe to retry — re-applying picks up where it left off and converges to the target.
- A standalone (unbonded) Sub on the overview is now tappable — a small sheet identifies it and explains how to add it to a home theater or group (previously it was shown but did nothing).
- An unreachable speaker's card is now shown dimmed with a short "Unreachable" subtitle instead of an alarming red warning tile with a long hint.
- Identify chime is now a repeated percussive ping (sharp attack, bright harmonics) instead of a soft two-tone sine — far easier to tell which speaker it's coming from by ear.
- iOS now carries the Apple-approved multicast entitlement, so discovery uses native SSDP multicast on physical iPhones instead of relying on the unicast /24 sweep (which stays as a backstop for multicast-filtering networks).
- Internal cleanup: deduplicated shared widgets/helpers and removed dead code; the GitHub Pages landing page now deploys automatically on each release tag and shows the current version. No user-facing behaviour change.

### Fixed
- The System overview no longer jitters / jumps while overscrolling with a trackpad on macOS (and iPad) — it now scrolls as a list view, which the platform bounce handles smoothly.
- Pull-to-refresh on the System overview and home-theater pages now works even when the content fits the screen without scrolling (previously the pull gesture did nothing there).
- The New/Re-snapshot profile form is now locked and dimmed while it reads a speaker's EQ/volume, so you can no longer flip the capture toggles or change the selection mid-save.
- Profile name field: the appearance swatch now stays vertically centered (and no longer jumps when the "name exists" error appears) on desktop, where the compact input density had made the field shorter than the swatch.

### Engine
- The Sonos engine (`lib/data/sonos/`) is now fully Flutter-free: persistence goes through an injected `KeyValueStore` port (a `shared_preferences` adapter in the app, an in-memory default for tests/CLI), so firmware/wire-format logic stays isolated and headlessly testable.
- Home-theater reconfiguration applies a **leaves-only diff**: a speaker that only changes channel (e.g. a fronts↔surrounds swap) is reassigned in place via `AddHTSatellite` instead of being unbonded first, so the layout no longer strips to one speaker per side mid-apply. Only speakers the target drops entirely are removed; an unchanged layout writes nothing.
- EQ capture is gated by **role, not probing**: since a speaker's supported EQ tokens aren't discoverable from its SCPD (byte-identical across models, and small speakers answer sub/height queries with harmless defaults), profiles read the extended EQ bundle only for soundbars, home theaters, or groups with a bonded sub; every other speaker captures bass/treble/loudness only.

## [0.5.1] - 2026-07-15

### Changed
- Aborting a profile apply now stops immediately (no confirmation dialog) and marks the step it stopped on as "Aborted" with a Retry option, instead of just closing — and aborting during the initial network scan now stops within a moment rather than waiting for the scan to finish.
- Icons now regenerate from a single source (`design/export.html` via `tool/gen_assets.sh`), ending the wordmark drift. Added an Android 13+ themed (monochrome) icon, gave the adaptive foreground real transparency, and switched the macOS icon to Apple's rounded squircle. iOS/macOS additionally support a layered glass-pane icon (Icon Composer) with the PNG icon kept as a fallback.
- Android: upgraded to Flutter 3.44 / AGP 9 (targetSdk 36) and enabled R8 code + resource shrinking, clearing the Play Console edge-to-edge, deprecated-API, and technical-quality recommendations.

### Fixed
- A failed bond/apply/rename no longer wipes the system overview — the last-known layout stays visible while the progress screen shows the error and offers Retry.
- Android splash screen: the logo is no longer clipped by the Android 12+ circular mask, and the "SONORITY" wordmark renders crisp, correctly proportioned, and in the right (Futura Medium) weight — no longer heavy, cropped, or stretched.
- Android home-screen widget tiles now fill the widget correctly on all launchers/sizes (no more dead space, clipped corners, or gaps drifting on resize).
- The "Done" button on the apply-progress screen now looks the same whether an apply succeeds or fails (a consistent filled button, with Retry beside it on failure).
- Apply-progress sub-step subtitles no longer render with a broken synthetic font weight on Android (Roboto has no `w200`; use `w300`).
- **macOS profile reordering** — removed the stray drag-handle icon that collided with each profile card's ⋮ menu, and made long-press-to-drag reordering work on macOS (it previously only responded to the now-removed handle).
- Applying a profile that reuses a speaker from another named stereo pair/zone now restores those speakers' room names instead of leaving them under the group's name.
- Removing home-theater speakers now reports a clear error if Sonos silently no-ops the change, rather than falsely showing success.
- Renaming a room no longer displays the new name until Sonos actually confirms it.
- Discovery now falls back to another player when the first one can't answer the topology read.
- A permanent bonding fault (e.g. a malformed map) now surfaces immediately instead of retrying for ~2½ minutes, and a failed EQ/volume restore is now reported instead of silently swallowed.

## [0.5.0] - 2026-07-12

### Added
- **Dual Subs** — a home theater can now bond **two Subs**, with both shown in the layout diagram and re-applied from a profile.
- **Profiles capture & restore per-speaker EQ** — a profile can snapshot each speaker's EQ (bass/treble/loudness, night sound, speech enhancement, sub, surround levels, lip-sync delay) and, as a separate opt-in, its **volume**, then re-apply them after the layout settles. Save/restore only — there are no EQ/volume sliders (that would duplicate the Sonos app).
- **Re-snapshot a profile** — update an existing profile in place from the current setup, without recreating it.
- **Speaker groups** — one "Group speakers" page (Stereo / Zone / Custom) to bond 2–16 speakers as a **stereo pair**, a full-range **zone**, or a **custom** per-speaker Left/Right/Both layout, each with an **optional Sub**. Mismatched models welcome; not restricted to Sonos' official model list (Play:1 and a Sub-in-group both confirmed working on hardware, audio routing verified). Separate restores original room names; groups are captured in config profiles. (Distinct from temporary playback groups, which the Sonos app already does.)
- **Config profiles** — snapshot your current layout (home theaters, speaker groups, rooms, with their names) and re-apply it in one tap, e.g. to rebuild a fronts/surrounds setup after moving speakers. A dedicated bottom tab.
- **Apply a profile from an app shortcut** — long-press the app icon to apply a saved profile in one tap. The shortcut opens the app and runs the apply, scanning your system first and asking for confirmation only when some speakers are missing or in use by another setup.
- **Per-profile icon & colour** — pick an icon and colour for each profile, shown on its tile, in the editor, and on its app shortcut (a full-colour glyph on Android, a matching SF Symbol on iOS).
- **Home-screen widgets** — place a widget showing a hand-picked set of profiles (small/medium/large) and apply any of them in one tap. Tiles use a muted tonal look that adapts to light/dark; reorder profiles in the Profiles tab by long-pressing a card.
- **Full in-app home-theater setup** — the guided flow now bonds dedicated fronts plus **rear surrounds and a sub** (each optional), with a live per-step progress timeline showing the active step and exactly where it failed. Applied with staged bonding (re-asserted until Sonos converges).
- **Room renaming** from the room and home-theater detail pages.
- **Identify a speaker by blinking its status LED** — works on every platform, including macOS (the audio chime stays as a mobile-only extra).
- Standalone **Subs are now shown in the overview** so a free Sub is easy to spot and add to a home theater or group.
- Internal: demo-data mode (`--dart-define=DEMO=true`) — a fake photogenic Sonos system + profiles for hardware-free marketing screenshots.
- Internal: marketing screenshots now capture from a Flutter web build in demo mode via `tool/capture_shots.dart` (headless Chrome), replacing the Android emulator + adb flow; `--frame` also renders the full framed Play/App Store graphic set. Web is a screenshot-only target, not a shipped platform.

### Changed
- **New app icon** — a three-speaker "trio" mark, used across every platform.
- UI overhaul: collapsing large-title app bars, a stepped stereo-pair creation flow, distinct card/nav-bar surfaces on a darker page background, and speaker **types** (e.g. "Beam (Gen 2)", "Play:1") shown wherever a model appears — in diagrams, bonded-speaker cards, and profile summaries.
- System overview re-sectioned: home theaters → speaker groups → single speaker rooms → other devices, with a compact "+" in the Speaker groups header.
- Speaker groups now have a **tappable detail view**, and the configure-bond flow **pre-selects the current layout** so it opens on what's actually bonded.
- The **app version** is shown as a tappable chip in the discovery app bar — it opens a dialog with the full version and build number, this changelog, and a link to the GitHub project.
- Discovery **auto-scans on launch** — the separate landing page is gone.
- Applying a home theater or profile now diffs against the live layout and only changes what moved — faster, and an unchanged layout re-applies with no writes.
- Trueplay: the "x/y active" counter is hidden for single speakers (shown only for home theaters and stereo pairs).
- The apply/profile progress timeline is now **two-level** — each phase's sub-steps are nested under the entity they act on, so it's clear what's happening and exactly where it failed.
- The apply progress timeline now marks no-op steps as **skipped** (grey dot + reason, e.g. "layout unchanged — nothing to do", "name unchanged — nothing to do") instead of showing them as completed work, so a re-apply that changed nothing is honest about it. The entity itself keeps its green checkmark — it's still in the desired state.
- Detail pages show the **entity type as an app-bar subtitle** (speaker model for a room, "Home theater", or the speaker-group kind).
- Profile creation warns before overwriting, and applying a profile is guarded against re-entrant taps.
- Profiles: the EQ capture toggle is now **"Save audio settings"** — the label undersold a bundle that also covers night sound, speech enhancement, sub & surround levels and lip sync. Profile cards now show separate **Audio settings** / **Volume** badges (instead of one combined "EQ" line) and use an icon-only play button with a bit more breathing room.
- Profiles and widgets now share one visual language: SF Symbol glyphs on every platform and soft colour-tinted (tonal) cards instead of bold full-colour fills.
- Re-snapshot moved to an app-bar action on the profile detail page.
- Switching bottom-nav tabs (System ↔ Profiles) now animates with a Material 3 shared-axis transition (fade + slide), sliding the way the tab bar moves.
- Consistent, flat separation for the top app bar and bottom navigation bar. The nav bar now shows a hairline dividing it from the page and cards (it was meant to but never rendered), and the app bar matches with a hairline that appears only while content scrolls under it — replacing its drop shadow, so every screen's chrome reads as flat and line-based.
- The macOS `.dmg` download now opens a styled drag-to-Applications install window — the app icon, an arrow, and an Applications shortcut over a branded background — instead of a bare disk image.

### Fixed
- **Discovery on iPhone** — the TestFlight build could hang on "Scanning your network" and fail: real iPhones silently block the multicast discovery packets (a restricted Apple entitlement the app doesn't carry; the simulator doesn't enforce it). When multicast finds nothing, discovery now falls back to directly probing the local network for Sonos players — which only needs the local-network permission the app already asks for. This also helps mesh/guest networks that filter multicast.
- The "couldn't find your system" screen no longer shows a raw `Exception:` prefix on its message, and its title now centres correctly when it wraps to two lines — so an empty network reads as a normal state, not a crash.
- The system overview no longer drifts to the vertical centre during the scan/rescan transition — short (non-scrolling) content now stays pinned to the top throughout the animation instead of floating to the middle and snapping back.
- macOS: the window is kept within the visible frame so the Dock can no longer clip it.
- Tap highlights on list rows now follow the card's rounded corners instead of rendering as a rectangle.

### Packaging
- iOS and macOS are now available via **TestFlight**; the macOS direct download is a **Developer ID-signed, notarized `.dmg`** (no Gatekeeper workaround) and the Android APK is **release-signed**.
- Release CI restructured into clear, per-platform jobs (Android, iOS sideload, iOS TestFlight, macOS `.dmg`, macOS TestFlight, GitHub Release).
- Fixed the macOS TestFlight CI job silently failing to upload: it died at fastlane `match` fetching a nonexistent macOS profile for the iOS-only widget, but showed green via `continue-on-error`. macOS signing now fetches the app profile only, and the job no longer masks failures.

## [0.4.0] - 2026-06-28

### Added
- **Trueplay (room calibration) read + toggle** on home theaters, stereo pairs and standalone rooms. Tuning is still measured in the Sonos app on iOS; Sonority reads the stored result and switches it on/off — including for the unofficial dedicated-fronts setups the Sonos app won't expose.
- Detail screen for stereo pairs and standalone rooms.

### Changed
- "Create stereo pair" is now a filled call-to-action button.
- Home-theater and room detail pages show a spinner on refresh and reload Trueplay status, not just the topology.
- GitHub Release notes are now generated from this changelog.

### Notes
- Sonos invalidates a speaker's Trueplay when its bonded set changes (adding or removing fronts), so a tuning may need to be redone after a layout change — a firmware limitation, not a Sonority bug.

## [0.3.0] - 2026-06-27

### Added
- App icon and splash screen (parametric Sonos 5.1 surround mark).
- Support a single **Sonos Amp** as the dedicated fronts (drives both front channels).
- Google Play Store listing graphics (icon, feature graphic, phone + tablet screenshots).
- CI now signs the release **App Bundle** and publishes it to the Google Play internal testing track on version tags.

## [0.2.0] - 2026-06-19

### Added
- **Stereo pairs**, including mismatched / app-blocked models (e.g. One + Play:1), with original room names restored on separation.
- Release CI: APK plus unsigned iOS and macOS artifacts on `v*` tags, with per-platform install instructions in the release.

### Changed
- Renamed the app from SoYes to **Sonority**.

## [0.1.0] - 2026-06-18

### Added
- Initial release: discover the Sonos system and add/remove dedicated front left/right speakers on a home theater via the local UPnP API, with identify-by-chime to tell speakers apart.
