# Changelog

All notable changes to Sonority are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releasing: before tagging `vX.Y.Z`, rename `[Unreleased]` below to
`[X.Y.Z] - YYYY-MM-DD`. CI copies that section into the GitHub Release notes
(see `.github/workflows/release.yml`).

## [Unreleased]

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
