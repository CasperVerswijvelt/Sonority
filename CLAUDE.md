# CLAUDE.md — Sonority

Guidance for AI agents (and humans) working on this repo. Read this first; it
captures hard-won, non-obvious knowledge that is expensive to re-derive.

## What this app is

**Sonority** is a cross-platform (iOS / Android / macOS) Flutter app that
**unlocks Sonos home-theater / speaker configurations the official Sonos app
refuses to create**, via Sonos' undocumented **local UPnP/SOAP API** (port 1400).
It's a cleaner, focused alternative to *SonoSequencr*.

### Product principle (important)
**Default: do NOT duplicate features the official Sonos app already has** (EQ/bass/
treble, volume, grouping, surround level sliders, night sound, Trueplay, …). Every
feature should be something the Sonos app **won't** let users do. Examples:
- **Dedicated front L/R speakers** on a soundbar (the bar becomes center). ✅ built
- **Mismatched / app-blocked stereo pairs**. ✅ built
- **Zones** — bond 2–16 speakers into one room (full-range L+R, no L/R split),
  including models the app blocks from zones (Play:1 zones fine on hardware).
  NB: this is the Sonos *zone* feature, NOT temporary playback grouping (which
  the app already does and we don't duplicate). ✅ built
- **Config profiles** — snapshot the current unofficial layout + room names and
  re-apply it in one tap (rebuild fronts/surrounds after moving speakers away).
  The validated #1 SonoSequencr request; unique because the Sonos app won't
  recreate a blocked config. ✅ built

**Deliberate exception (softened principle):** full in-app **surround/sub setup**
and **room renaming** DO exist in the official app, but we now do them anyway —
because profiles are only useful if a *complete* HT/stereo setup can be finished
inside Sonority (otherwise you snapshot a half-config and still bounce to the
Sonos app). Justified by "finish a setup in one app, then save it." Keep this the
*only* exception; don't widen it to EQ/volume/grouping/etc.

The app does **no audio processing** — it only issues the bonding/config SOAP
calls the official app blocks. Audio quality comes from the real speakers.

## Toolchain & commands

Flutter is **not on PATH**; this machine uses **fvm, Flutter 3.35.2**:
```
~/fvm/versions/3.35.2/bin/flutter <cmd>
~/fvm/versions/3.35.2/bin/dart run tool/<x>.dart
```
- `flutter analyze` and `flutter test` must stay green before committing.
- CocoaPods is **Homebrew's** (`/opt/homebrew/bin/pod`); system-Ruby pod is broken — don't use it. iOS/macOS builds need full **Xcode** (installed).
- Identifiers: Dart package `sonority`, bundle id / Android namespace
  `be.casperverswijvelt.sonority`. The **project folder is still `soyes`**
  (intentional — renaming it breaks git/cwd paths). Git author: gmail identity,
  no `@basalte.be` (history was scrubbed — keep it that way).
- Repo: github.com/CasperVerswijvelt/Sonority. CI in
  `.github/workflows/release.yml` — six per-platform jobs on `v*` tags (android;
  ios-unsigned; ios-testflight; macos-dmg = Developer-ID notarized; macos-testflight;
  publish-github) → release-signed APK + unsigned iOS .ipa + notarized macOS .dmg on the
  GitHub Release, plus iOS/macOS → TestFlight. Release notes from
  `.github/release-install-notes.md` (do NOT add `generate_release_notes` — it overrides the body).
- **Signing secrets/keys: `docs/SIGNING.md`** is the map of where every value/file lives
  (Bitwarden masters, GitHub Actions secrets, gitignored local files, the match certs repo).
  No secret values are committed. Apple setup details: `docs/PUBLISHING-APPLE.md`.
- **Version bumps happen ONLY on `main`, after a feature branch is merged** — never
  bump `version:` in `pubspec.yaml` on a feature branch (avoids merge churn/conflicts
  on the build number). Bump + tag as a dedicated step on `main` when cutting a release.

## Architecture

A **pure-Dart engine** (no Flutter imports) drives Sonos; the Flutter app and the
CLI tools both sit on top of it. This split is deliberate — it lets us validate
the engine headlessly against real hardware via `tool/*.dart`.

```
lib/
  core/            result.dart, theme.dart (M3), tone_generator.dart (chime WAV)
  data/models/     sonos_models.dart — SonosDevice, ZoneGroupMember, SonosSystem, SonosChannel
  data/sonos/      THE ENGINE (pure Dart, no Flutter):
                     ssdp_discovery · device_description · soap_client
                     zone_topology  · device_properties (bonding + stereo + zone attrs)
                     channel_map    · front_layout (buildLayoutMap + diffHtLayout — any role)
                     apply_progress (ApplyStep/ApplyProgress — per-step status)
                     identify_service (chime)
                     sonos_repository (orchestrates; bondAndVerify write+retry;
                       removeHtSatellites; freeSpeaker; setRoomName; + shared_preferences ⇒ Flutter dep)
  state/           sonos_controller.dart — AsyncNotifier<SonosSystem?>; applyHomeTheaterLayout,
                     applyProfile, _applyHtTarget (diff-based), renameRoom; applyProgressProvider
  features/        discovery / home_theater / front_surrounds (full HT setup) /
                     group (unified Stereo/Zone/Custom) / profiles / room / widgets
  app.dart, main.dart — go_router StatefulShellRoute (System|Profiles tabs), ProviderScope
tool/              spike, roundtrip, full_layout, diff_apply_spike, chirp, dump_chime, zone_probe, lr_audiotest
```
Note: CLI tools must NOT import `sonos_repository.dart` (it pulls in
`shared_preferences` → Flutter). The pure recipes live in `front_layout.dart` /
`zone_layout.dart` for exactly this reason.

## Sonos local API — the knowledge that matters

- **Discovery**: SSDP `M-SEARCH` to `239.255.255.250:1900` (ST
  `urn:schemas-upnp-org:device:ZonePlayer:1`) → each player's
  `http://<ip>:1400/xml/device_description.xml` (gives `RINCON_…` UUID, model, room).
- **Topology**: `ZoneGroupTopology.GetZoneGroupState` returns the whole system as
  a **double-encoded** XML string (unescape `<ZoneGroupState>` innerText, parse again).
- **All SOAP**: POST to `http://<ip>:1400<controlPath>` with `SOAPACTION` header.
  See `soap_client.dart`. **Send `Connection: close`** — Sonos players are flaky
  with HTTP keep-alive: a pooled socket the player already closed makes the next
  request hang to timeout. Harmless for occasional calls, but rapid-fire bursts
  (e.g. the LED blink's ~9 calls) intermittently 8s-timeout without it.
  **Confirmed on hardware:** adding `Connection: close` fixed a flaky LED blink.
- **`DeviceProperties` service** (`/DeviceProperties/Control`):
  - `AddHTSatellite` / `RemoveHTSatellite` — bond/unbond satellites & sub.
    **Staged-bonding rule (confirmed on hardware, Phase 0):** a *single*
    `AddHTSatellite` with a full map (CC+LF/RF+LR/RR+SW) from a **bare** soundbar
    does NOT hold — it 8s-times-out, briefly reads back as applied, then Sonos
    tears the whole bond down after the ~15–30s settle (satellites that don't
    finish joining are **silently dropped**, reverting to standalone with old
    names). The reliable primitive is **converge by re-assertion**: write the
    target map, settle ~16s, re-read the authoritative `HTSatChanMapSet`, and
    **re-write the SAME map until every channel is present** (a real Beam rebuild
    needed ~4–6 re-asserts). Bonding is eventually-consistent and BOTH failure
    modes are transient: the 8s `TimeoutException` AND `UPnPError 800` ("can't add
    a satellite mid-reshuffle") — the write still partially applies, so treat
    either as "go verify", never as fatal. This is `SonosRepository.bondAndVerify`
    (retries=10), used by `SonosController.applyHomeTheaterLayout` / `applyProfile`.
    **Apply the DIFF, don't strip-and-rebuild.** `AddHTSatellite` 800s only on a
    map that would *drop* a currently-bonded speaker — **adding** to a live HT is
    fine (confirmed on hardware, `tool/diff_apply_spike.dart`). So
    `SonosController._applyHtTarget` diffs current-vs-target
    (`front_layout.diffHtLayout`): **no-op when unchanged** (zero writes — the
    common re-apply case), else `RemoveHTSatellite` ONLY the satellites that
    move/leave, then additively `bondAndVerify` the target. This is both faster
    and *more reliable* than the old strip-to-bare path — adding only the missing
    satellite(s) converges in ~1 attempt, whereas a full rebuild-from-bare is the
    flaky case that needs many re-asserts. **A whole layout is applied in ONE
    `bondAndVerify`, never staged.** A/B-tested on a real Beam (single vs
    surrounds-then-fronts, 3 trials each): single-call rebuilt the full 5.1 from
    bare in a steady **6 re-asserts** every time; **staging was worse** (each
    phase reshuffles and the second disturbs the first → 7–24 re-asserts, often
    past the cap). So don't reintroduce staging. **Validated end-to-end on real
    hardware** via the Android E2E test (`integration_test/profile_e2e_test.dart`,
    now a no-op apply). **Sub-on-a-stereo-pair is NOT supported** —
    `AddHTSatellite` on a pair coordinator returns UPnPError 401.
  - `CreateStereoPair` / `SeparateStereoPair` — stereo pairs.
  - `AddBondedZones(ChannelMapSet)` — **creates** a Sonos **zone** (the 2025
    multi-speaker bond: 2–16 individual speakers play as one room, full-range
    L+R, no L/R split). **Confirmed on hardware** (`tool/zone_probe.dart`):
    `ChannelMapSet = UUID:LF,RF;UUID:LF,RF;…` (coordinator first, every member
    full-range — vs a pair's single-sided `LF,LF`/`RF,RF`). Structurally like a
    pair (coordinator stays visible carrying the map, the rest go Invisible).
    Sonos does NOT restore member names on separate, so we snapshot + restore
    them like pairs.
  - **Zone REMOVAL is a two-step gotcha (hardware-confirmed, cost real debugging):**
    1. `RemoveBondedZones` **does not work** on the 2025 zones feature — it
       returns `200 OK` but silently no-ops (it's the legacy bonded-zone action).
       The working dissolve is **`SeparateStereoPair`** with the zone's full
       `ChannelMapSet` (a zone shares the pair's bond mechanism) →
       `DevicePropertiesClient.separateBondedZones`.
    2. Even `SeparateStereoPair` no-ops while the zone coordinator is a
       **non-coordinator member of a larger playback group**. So you must FIRST
       detach it into its own group via `AVTransport.
       BecomeCoordinatorOfStandaloneGroup` (`AvTransportClient`), poll until it's
       standalone, THEN `SeparateStereoPair`. `SonosController.separateZone`
       orchestrates detach → poll-standalone → separate → poll; `freeSpeaker`
       does detach + fixed settle + separate for profile-apply conflict freeing.
  - **Supported-speaker findings (read carefully — the eligibility list is part
    measured, part assumed):**
    - Sonos *officially* allows only Era 100/300/100 Pro, One, One SL, Five.
    - **Measured on hardware:** a **Play:1 zones fine** (One + 2× Play:1) even
      though Play:1 is NOT on Sonos' official list. So we deliberately do **not**
      gate creation on the official model list — that would block configs that
      actually work, against the whole point of the app.
    - **Assumed, NOT yet hardware-verified:** Amp, Sub, and soundbars are
      excluded as zone candidates (`SonosSystem.zoneableSpeakers` drops
      amps/subs/soundbars) per Sonos' stated limits — but we never probed an Amp
      (none on the test system) or a Sub/soundbar reject, so those exclusions are
      defensive policy, not a confirmed finding. The real backstop is runtime:
      `createZone` polls and throws "a speaker may be incompatible" if Sonos
      silently no-ops the bond. If an Amp/Sub/soundbar ever needs revisiting,
      probe it with `tool/zone_probe.dart --members …` first.
  - **`AddBondedZones` accepts almost ANY channel map (API-only finding,
    `tool/zone_probe.dart --explore`):** a 19-config hardware battery (2–8
    speakers) was accepted 19/19 and stored verbatim — symmetric, **asymmetric**
    (2L+1R … 7L+1R), mixed full-range+single-sided, **degenerate** (all-LF), and
    even **HT-channel tokens on plain speakers** (CC/LR/RR). The local API does
    essentially no validation on the channel-assignment shape.
  - **Audio ROUTING confirmed on hardware (`tool/lr_audiotest.dart`, an L/R voice
    track):** Sonos genuinely HONORS per-speaker assignment — `LF,LF` plays only
    left, `RF,RF` only right, `LF,RF` both. Verified: stereo pair, **2L+2R (real
    2-per-side wide stereo)**, asymmetric 2L+1R (unused speakers silent),
    full-range zone (all both), all-LF degenerate (right channel fully dropped).
    **Correction to the earlier guess:** discrete rears (`LR`/`RR`) on plain
    speakers are NOT silent — with a stereo source they play the FULL stereo mix
    (no discrete rear content to isolate), so CC/LR/RR tokens are pointless to
    expose. **Feature opportunity (on hold):** every working shape is just a
    per-speaker **Left / Right / Both** choice, so one "custom stereo zone" flow
    (assign each of 2–16 speakers to L/R/Both) subsumes stereo pair + N-per-side
    wide stereo + asymmetric + the full-range `isZone` the app builds today.
  - **A Sub CAN be bonded into a zone (`UUID:SW`) — contradicts Sonos' docs.**
    Hardware-confirmed: a Sub freed from its HT and added to a zone map
    (`A:LF,RF;B:LF,RF;SUB:SW`) is accepted, bonded as `SW`, AND audibly renders
    (user verified by raising sub level). Sonos' "subs can't be added to a zone"
    is an app-side restriction only. (So if a custom-zone feature is built, a Sub
    could optionally be included — but it must be freed from any HT first.)
  - **Large zones get flaky under playback (hardware observation):** every zone
    drops out for the first ~30–60s after audio starts (the bond settling under
    stream load), then stabilises — EXCEPT an 8-speaker zone on this mix of older
    gear (Play:1s) kept dropping even after settling. Practical ceiling is well
    below Sonos' claimed 16. A feature should settle before reporting success and
    probably cap / warn on large mixed-gear zones.
  - `GetZoneAttributes` / `SetZoneAttributes` — read/set room name (used to restore
    names after un-pairing / un-zoning).
  - `GetLEDState` / `SetLEDState` (`CurrentLEDState`/`DesiredLEDState` = `On`/`Off`)
    — the white status light. Used by the **LED-blink identify**
    (`led_identify.dart`): an outbound-only SOAP call, so unlike the audio chime it
    works under the macOS sandbox. `blink()` snapshots the state and restores it in
    a `finally` (self-reverting, like the chime's volume save/restore).
- **`RenderingControl` service** (`/MediaRenderer/RenderingControl/Control`):
  - `GetVolume`/`SetVolume`/`GetMute`/`SetMute` (used by the identify chime).
  - **Trueplay / room calibration** (`room_calibration.dart`): per-speaker,
    confirmed via the device SCPD — `GetRoomCalibrationStatus(InstanceID)` →
    `RoomCalibrationEnabled` + `RoomCalibrationAvailable`; `SetRoomCalibrationStatus
    (InstanceID, RoomCalibrationEnabled)`. **available = a tuning is stored**
    (measured once in the **iOS** Sonos app — cloud DSP + Apple-only mic profiles,
    **cannot** be done from Android); **enabled = applied**. We only read + toggle
    (non-destructive, instant), which is the part the Sonos app won't expose for
    the unofficial fronts config. Toggle ALL bonded members so the separately-tuned
    fronts engage; **Amp-driven fronts can't be Trueplay'd** (native speakers only).
  - **Gotcha (A/B-tested on hardware):** Sonos **invalidates** Trueplay across the
    WHOLE bonded set when that set changes. Measured: a freshly-tuned Beam HT
    (bar `CC`, rears `LR`/`RR`, sub `SW` all `available=1`) → `AddHTSatellite`
    fronts → **every** member, coordinator included, dropped to `available=0`; an
    untouched standalone (Eetkamer) kept `available=1` throughout. So the
    "tune-then-bond" workaround **failed outright on Beam-gen gear** — and it's a
    catch-22 (the official app refuses to tune the very fronts config you want).
    Reddit reports of it working are firmware/model-specific. Sonority reads and
    reports this honestly but cannot restore a tuning Sonos has cleared.

### Channel maps (`channel_map.dart`)
`HTSatChanMapSet` format: `UUID:CH[,CH];UUID:CH;…`. Tokens: `LF RF CC LR RR SW`.
- **Confirmed on a real Sonos Beam**: stock 5.1 = `BEAM:CC;…:LR;…:RR;…:SW` — the
  soundbar is **`CC` (center)**, NOT `LF,RF`. To add **dedicated fronts**: keep the
  bar as `CC`, append the two chosen speakers as `LF` / `RF`, preserve existing
  rears/sub. This produces a real 5.1 with discrete fronts. (`front_layout.dart`.)
- **Amp as fronts**: a single Sonos Amp drives two passive front speakers, so it
  occupies BOTH front channels in one entry — `AMP:LF,RF` — instead of two
  separate Sonos speakers. Bar still becomes `CC`. (`buildAmpFrontsMap`;
  detected via `SonosDevice.isAmp`. Confirmed working on hardware.)
- Adding fronts to a setup that already has rears yields 4 satellites — that's the
  natural max; Sonos has no true 7.1 (6 boxes).
- **Stereo pair** map: `UUID_LEFT:LF,LF;UUID_RIGHT:RF,RF`. Left stays visible; right
  becomes hidden.
- **Zone** map: `UUID:LF,RF;UUID:LF,RF;…` — every member full-range, coordinator
  first (`buildZoneMap` in `zone_layout.dart`). The discriminator vs a stereo
  pair: pair entries are single-sided (`LF`-only / `RF`-only), zone entries carry
  both `LF`+`RF`. `ZoneGroupMember.isZone` / `isStereoPair` encode this; `isZone`
  needs ≥2 full-range entries, and `isStereoPair` was narrowed to exactly two
  single-sided entries so a zone is never mistaken for a pair.

### Topology representations (parse these, don't guess)
- **HT satellite**: a `<Satellite>` child of the primary `<ZoneGroupMember>`, with
  channels living in the primary's `HTSatChanMapSet` attribute.
- **Stereo pair**: the visible primary `<ZoneGroupMember>` carries a `ChannelMapSet`
  attribute (`…:LF,LF;…:RF,RF`); the hidden speaker is a **separate**
  `<ZoneGroupMember Invisible="1">` (its `ZoneName` is absorbed to the pair name).
  → `SonosSystem.allMembers` excludes `Invisible` members.
- **Zone**: same shape as a stereo pair but N members and full-range channels —
  the coordinator stays visible carrying the `ChannelMapSet`
  (`…:LF,RF;…:LF,RF;…`), the other members are separate `Invisible="1"`
  `<ZoneGroupMember>`s (names absorbed). `SonosSystem.zones` surfaces them.

## CRITICAL gotchas (these caused real bugs)

1. **~15s topology lag.** After ANY bonding change, `GetZoneGroupState` is slow/
   inconsistent for ~15s: `<Satellite>` elements briefly vanish, `Invisible` flags
   and restored names propagate late. **Never trust the first read.**
   - **Detect state from the authoritative `HTSatChanMapSet` / `ChannelMapSet`
     attributes**, NOT from the transient `<Satellite>` list (see
     `ZoneGroupMember.frontSatelliteUuids`, `channelAssignments`, `isStereoPair`).
   - After a write, **poll until the FULL end-state settles** — not just the first
     signal. E.g. create-pair polls until paired AND the right speaker is gone from
     the room list; separate polls until unpaired AND the name has propagated.
     See `SonosController._pollUntil`.
2. **Some writes silently no-op.** A SOAP call can return `200 OK` yet do nothing
   (e.g. `CreateStereoPair` on truly incompatible hardware — though **mismatched is
   allowed**: One + Play:1 pairs fine; only genuinely incompatible combos are
   rejected). Always **poll to confirm the change actually happened** and surface a
   clear error if not.
3. **Live writes are destructive** to the user's real living-room system. Pattern:
   snapshot first, gate behind explicit confirm, make it self-reverting, verify by
   re-reading. The user HAS a real Sonos system on the LAN — validate against it.
4. **Identify chime** (`identify_service.dart`): spins up an in-app HTTP server
   serving a generated WAV, then `AVTransport.SetAVTransportURI`+`Play`, with
   `RenderingControl` volume save/bump/restore. The clip needs lead/trail silence
   (~1.25s) or Sonos clips the start. Works on **CLI, iOS, Android**;
   **fails on the sandboxed macOS app** (App Sandbox blocks the inbound LAN
   connection despite `network.server` + firewall off). **The default identify is
   now the LED blink** (`led_identify.dart`, outbound-only → works on macOS too,
   default on all platforms). The chime is a **separate button** shown only on
   iOS/Android (`_chimeSupported` gates `_onChime`); hidden on macOS.

## CLI tools (validate against hardware before/without the GUI)

Run on the same Wi-Fi as the Sonos system:
- `tool/spike.dart` — read-only: discover + dump full topology (incl. raw maps).
- `tool/roundtrip.dart` — live HT fronts; dry-run by default; `--confirm`,
  `--apply-only`, `--remove-only`.
- `tool/full_layout.dart` — strip the bar to bare → rebuild a FULL HT map in one
  `AddHTSatellite` → verify each channel → restore. The Phase 0 spike that proved
  re-assertion converges a from-bare rebuild; dry-run by default, `--confirm`. ⚠️ wipes Trueplay.
- `tool/diff_apply_spike.dart` — validates the diff-based apply on hardware:
  no-op (zero writes), additive-in-place (drop the sub → re-add without strip),
  and a LR↔RR swap. Self-restoring; dry-run does the no-op check only, `--confirm`
  runs the writes. ⚠️ wipes Trueplay.
- `tool/zone_probe.dart` — Sonos speaker-group probe: dump DeviceProperties
  zone/bond SCPD actions + any existing `ChannelMapSet` members; `--members
  a,b,c [--confirm]` round-trips a group; `--separate`, `--explore` (config
  battery). Self-reverting; confirmed the `UUID:LF,RF;…` format on hardware.
- `tool/lr_audiotest.dart` — plays an L/R voice track on a group to verify Sonos
  honours per-speaker channel assignment (play/stop/snapshot/freesat/addht).
- `tool/chirp.dart <room|uuid|ip>` — play the identify chime on one speaker.
- `tool/led_probe.dart <room|uuid|ip>` — dump DeviceProperties SCPD LED actions +
  blink one speaker's status LED (read-only/self-reverting; the macOS-safe identify).
- `tool/dump_chime.dart <path>` — write the generated WAV to disk.
- `tool/trueplay_probe.dart` — read-only Trueplay/room-calibration status per
  speaker (+ SCPD dump); `--enable/--disable <room|uuid>` to toggle (reversible).

## Platform notes
- iOS: `Info.plist` has `NSLocalNetworkUsageDescription` + `NSBonjourServices`
  (mandatory on iOS 14+ or all LAN traffic is silently blocked).
- macOS: entitlements include `network.client` + `network.server`; window is locked
  to a fixed **420×880 portrait** (`MainFlutterWindow.swift`) so the UI only ever
  handles one mobile layout.
- All platforms: portrait-only (`SystemChrome` + iOS plist + Android manifest).
- Emulators/simulators usually can't reach the LAN's SSDP multicast (this Android
  AVD happens to). Use a **physical device** for real discovery.

## Feature status
- ✅ Discovery + topology + Material 3 UI (discovery → home-theater diagram).
- ✅ Dedicated front surrounds (add with guided flow + Identify; remove), incl. a
  single **Sonos Amp** driving passive fronts (`AMP:LF,RF`; exclusive selection).
- ✅ Identify a speaker by **blinking its status LED** (`led_identify.dart`, default,
  all platforms incl. macOS) with the audio chime as a mobile-only long-press extra.
- ✅ **Speaker groups** (`features/group/group_flow.dart`, `zone_layout.dart`) —
  one unified "Group speakers" page (Stereo / Zone / Custom segmented control)
  over a single `AddBondedZones` path: stereo pair (L/R), full-range zone (2–16),
  custom per-speaker L/R/Both, each with an optional Sub (`UUID:SW`). Separate via
  detach → `SeparateStereoPair` on the live map; names restored. Overview shows
  them in one "Speaker groups" section (`groupKind`-labelled); captured in
  profiles (`EntityKind.stereoPair/zone/custom`). Not gated to Sonos' official
  model list (Play:1 + Sub-in-group confirmed on hardware; audio routing verified).
- ✅ **Full in-app HT setup** — the guided flow now bonds fronts **+ rear surrounds
  (LR/RR) + a sub (SW)**, each optional, applied via the **diff-based**
  `_applyHtTarget` (no-op when unchanged, else add what's missing) + a live
  per-step progress stepper that shows the active step and exactly where it failed
  (`front_surrounds_flow.dart`, `apply_progress_view.dart`, `applyHomeTheaterLayout`).
- ✅ **Config profiles** (`features/profiles/`) — bottom-tab page; a profile is a
  snapshot of current state trimmed to chosen entities (one HT / pair / unbonded
  room = one entity), with stored room names. Create-from-snapshot only (no config
  builder); tiles **edit** + **apply (play)**. Apply does pre-flight resolution
  (missing/conflicting speakers), frees conflicts, re-bonds via the diff-based
  `_applyHtTarget` (no-op if unchanged, else add only what's missing), restores
  names, and reports per-step progress. Sub-on-stereo-pair is out (hardware-rejected).
- ✅ **Room renaming** from the room / HT detail pages (`renameRoom` + `rename_dialog`).
- ✅ Trueplay read + toggle (`room_calibration.dart` + `trueplay_control.dart`) on
  all speakers/HTs — toggles the iOS-measured calibration the Sonos app won't
  expose for unofficial fronts. Measurement stays iOS-only (out of scope).
- ✅ CI release pipeline.
- Candidate next: channel-level/height trim (overlaps the app — weak). Discovery
  now recovers topology-only speakers when a description fetch fails (done upstream).

## Conventions
- Keep `flutter analyze` clean and unit tests passing; add tests for new parsing/
  recipe logic (see `test/`).
- Match the existing engine/UI style; isolate all UPnP wire-format details in
  `lib/data/sonos/` so firmware quirks are cheap to patch.
- **Don't duplicate logic where sharing is logical.** If the same widget, action,
  or helper is being copy-pasted across features/tools, extract it. Established
  shared pieces to reuse (don't reinvent): `features/widgets/identify_controls.dart`
  (`IdentifyButtons` + `IdentifyMixin` — speaker blink/chime), `features/widgets/
  speaker_side_card.dart` (the L/R card), and `tool/discover_util.dart`
  (`resolveSpeaker` — CLI room/uuid/IP resolution). Prefer a shared widget/mixin/
  helper over a second copy; only keep a bespoke variant when forcing it into the
  shared shape would genuinely hurt readability.
- **Names vs. types in the UI.** Once a speaker is bonded into an HT or stereo
  entity its individual room name stops mattering — Sonos absorbs it into the
  entity name (a satellite/hidden half just echoes the HT/pair name), so showing
  it is noise. Inside a bonded entity we therefore show the speaker **type**
  (`SonosDevice.typeLabel` — "Beam (Gen 2)", "Play:1", "Sub") via
  `typeForChannel` / `entitySummary`. The **name** only matters for the entity as
  a whole (the HT / pair) and for individual standalone speakers — that's where
  rename and the room-name labels live.
- Commit only when asked; end commit messages with the Co-Authored-By trailer.
