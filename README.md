<p align="center">
  <img src="docs/icon.png" width="160" alt="Sonority app icon" />
</p>

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=be.casperverswijvelt.sonority"><img src="docs/badges/google-play.png" height="48" alt="Get it on Google Play" title="Get it on Google Play" /></a>
  &nbsp;&nbsp;
  <a href="https://apps.apple.com/us/app/sonority-for-sonos/id6785994018"><img src="docs/badges/app-store-soon.png" height="48" alt="Download on the App Store" title="Download on the App Store" /></a>
  &nbsp;&nbsp;
  <a href="https://apps.apple.com/us/app/sonority-for-sonos/id6785994018"><img src="docs/badges/mac-app-store-soon.png" height="48" alt="Download on the Mac App Store" title="Download on the Mac App Store" /></a>
</p>

<p align="center">
  <sub><i>iOS &amp; macOS on the <a href="https://apps.apple.com/us/app/sonority-for-sonos/id6785994018">App Store</a>, Android on <a href="https://play.google.com/store/apps/details?id=be.casperverswijvelt.sonority">Google Play</a> — or manual installation, see <a href="https://github.com/CasperVerswijvelt/Sonority/releases">Releases</a>.</i></sub>
</p>

# Sonority

A clean, cross-platform (iOS + Android + macOS) Flutter app that unlocks Sonos speaker
configurations the official app refuses to create — **dedicated front left/right surround
speakers** on a home theater, a **full in-app home-theater setup** (fronts + rear surrounds +
sub), **speaker groups** — one page to bond 2–16 speakers as a stereo pair, a zone, or a
custom per‑speaker L/R/Both layout (mismatched models + an optional Sub, no model‑list
restriction) — and **config profiles** that snapshot a layout and re-apply it in one tap — via Sonos'
undocumented local UPnP API. A focused, better‑UX alternative to *SonoSequencr*.

> [!NOTE]
> **Built with AI-assisted programming.** I'm a software engineer, but every line
> of code here was written by an AI coding agent under close direction — I specified
> exactly what each change had to do rather than typing it myself. I worked to keep
> it from becoming "AI slop": exhaustive testing against my own Sonos hardware,
> deliberate attention to code quality and architecture, unit tests, and thorough
> documentation throughout. Sharing this openly for transparency.

## Screenshots

<p align="center">
  <img src="docs/screenshots/01-overview.png" width="23%" alt="System overview: home theaters, speaker groups, rooms" />
  &nbsp;
  <img src="docs/screenshots/02-home-theater.png" width="23%" alt="Home theater with dedicated front L/R speakers, surrounds and sub" />
  &nbsp;
  <img src="docs/screenshots/03-group.png" width="23%" alt="Grouping speakers: stereo pair, zone or custom" />
  &nbsp;
  <img src="docs/screenshots/04-profiles.png" width="23%" alt="Config profiles: save and reapply a layout in one tap" />
</p>

## Install (prebuilt)

**iOS & macOS — App Store (recommended)**
- Get it on the **[App Store](https://apps.apple.com/us/app/sonority-for-sonos/id6785994018)** — the same
  listing installs on both iPhone/iPad and Mac.

Or grab a direct download from [**Releases**](https://github.com/CasperVerswijvelt/Sonority/releases):

**Android — `Sonority-*.apk`** (release-signed)
- On your phone: download the APK, allow “install unknown apps” for your browser/files app, then open it.
- Or via adb: `adb install -r Sonority-*.apk`

**macOS — `Sonority-*-macos.dmg`** (Developer ID-signed & notarized)
- Open the `.dmg`, drag **Sonority** to Applications, and launch it. No Gatekeeper
  workaround needed — it’s notarized by Apple.

**iOS — `Sonority-*-ios-unsigned.ipa`** (unsigned; sideload only)
- Prefer the App Store above. To sideload the raw `.ipa`, re-sign it with
  [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) using your Apple ID —
  a plain install isn’t possible without signing.

> On every platform, keep the device on the **same Wi‑Fi** as your Sonos. iOS and macOS prompt for **local network** access on the first scan — allow it, or discovery finds nothing.

## How it works

Sonos players expose an undocumented **local UPnP/SOAP API** on port `1400`. Sonority does no
audio processing; it simply issues the bonding call the official app won't:

1. **Discovery** — SSDP `M-SEARCH` to `239.255.255.250:1900`, then each player's
   `http://<ip>:1400/xml/device_description.xml`. → `lib/data/sonos/ssdp_discovery.dart`,
   `device_description.dart`
2. **Topology** — `ZoneGroupTopology.GetZoneGroupState` for the full system layout.
   → `lib/data/sonos/zone_topology.dart`
3. **The unlock** — `DeviceProperties.AddHTSatellite` with a `HTSatChanMapSet` mapping the
   chosen speakers to channels (fronts `LF`/`RF`, rears `LR`/`RR`, sub `SW`). `RemoveHTSatellite`
   undoes it. Bonding is eventually-consistent, so writes are **staged and re-asserted** until the
   topology converges. → `lib/data/sonos/device_properties.dart`, `channel_map.dart`,
   `sonos_repository.dart` (`bondAndVerify`)

A restore point (the soundbar's current `HTSatChanMapSet`) is saved before every change.
**Config profiles** snapshot a whole layout (maps + room names) so it can be rebuilt later in one
tap. → `lib/features/profiles/`

## Project layout

```
lib/
  core/        result + theme
  data/        models + sonos/ (ssdp, descriptions, soap, topology, device props, channel map,
               front_layout, zone_layout, apply_progress, repository — staged bondAndVerify)
  state/       Riverpod controllers (system + apply-progress)
  features/    discovery / home_theater / front_surrounds (full HT setup) /
               group (unified Stereo/Zone/Custom) / profiles / room / widgets
tool/spike.dart  read-only hardware validation CLI
```

## Run

This repo uses [fvm](https://fvm.app) (Flutter 3.35.2). Replace `flutter` with
`fvm flutter` if you have fvm on PATH.

```bash
flutter pub get
flutter test          # unit tests (channel map, SOAP envelope, topology parsing)
flutter analyze
flutter run           # on a physical device on the same Wi-Fi as your Sonos
```

> Use a **physical** device — simulators/emulators can't reliably reach the LAN, and iOS 14+
> shows a one-time local-network permission prompt on first scan.

## Validate against your hardware first (read-only)

Before trusting any write, confirm the read path and capture the real channel-map string:

```bash
dart run tool/spike.dart
```

This discovers your system and prints every home theater's raw `HTSatChanMapSet`. The dedicated-front
recipe (soundbar stays `CC`, added speakers map to `LF`/`RF`, rears/sub preserved) is **confirmed on a
real Beam** and built by `buildLayoutMap` (`lib/data/sonos/front_layout.dart`) — adjust
there if a different model/firmware ever needs it.

## Tools

- `tool/spike.dart` — read-only discovery + topology dump
- `tool/roundtrip.dart` — live AddHTSatellite/RemoveHTSatellite (dry-run by default; `--confirm`, `--apply-only`, `--remove-only`)
- `tool/full_layout.dart` — strip to bare → rebuild a full HT map → verify each channel (dry-run by default; `--confirm`)
- `tool/zone_probe.dart` — speaker-group probe: dump zone/bond SCPD actions + round-trip a group (`--members a,b,c [--confirm]`, `--separate`, `--explore`); confirmed the `ChannelMapSet` format on hardware
- `tool/lr_audiotest.dart` — play an L/R voice track on a group to verify per-speaker channel routing
- `tool/chirp.dart` — play the identify chime on one speaker (validates `IdentifyService`)
- `tool/led_probe.dart` — blink a speaker's status LED (the macOS-safe identify; read-only/self-reverting)
- `tool/trueplay_probe.dart` — read/toggle per-speaker Trueplay status

## Status

- ✅ Discovery + home-theater topology UI (Material 3, dark mode)
- ✅ Dedicated front surrounds — guided add flow (+ Identify), one-tap remove
- ✅ Full in-app home-theater setup — fronts + rear surrounds + one or two subs (each
  optional), staged bonding with a live per-step progress timeline
- ✅ Config profiles — snapshot a layout (maps + room names, optionally per-speaker audio
  settings/EQ and volume) and re-apply in one tap; each profile has its own icon & colour
- ✅ Apply a profile from a home-screen widget (small/medium/large) or a long-press app-icon shortcut
- ✅ Room renaming from the room / home-theater detail pages
- ✅ Speaker groups — one page (Stereo / Zone / Custom) to bond 2–16 speakers as a stereo
  pair, a full-range zone, or a custom per-speaker L/R/Both layout, each with an optional Sub;
  separate with name restore, captured in profiles; not restricted to Sonos' official model list
- ✅ Identify a speaker by blinking its status LED (default; macOS-safe) or a chime (mobile)
- ✅ Trueplay read + toggle on speakers / pairs / home theaters
- ✅ Recipe confirmed on real hardware (Beam stays `CC`; fronts = `LF`/`RF`)
- ✅ CI release pipeline on `v*` tags: release-signed APK, unsigned iOS `.ipa`, notarized macOS `.dmg`, plus iOS/macOS → TestFlight

## Contributing / architecture

See **[CLAUDE.md](CLAUDE.md)** — the product principle (don't duplicate Sonos-app
features), the pure-Dart engine vs. UI split, the local UPnP API details, and the
critical gotchas (≈15s topology lag, poll-until-settled, authoritative channel-map
parsing, firmware-gated pairs, the macOS-sandbox chime limitation).
