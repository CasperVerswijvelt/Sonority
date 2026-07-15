# Publishing to the App Store (iOS + Mac)

Companion to `PUBLISHING.md` (Google Play). Covers the one-time Apple setup and
the per-release flow. Listing copy lives in `app-store/listing.md`; the required
legal pages are `privacy-policy.html` + `support.html` (host them, see below).
Screenshots + how to regenerate them: [`MARKETING-ASSETS.md`](MARKETING-ASSETS.md).

Decisions baked in: **paid app, $1.49 / €1.49**, **individual** enrollment,
iOS **and** Mac App Store.

## One-time setup

### 1. Account & agreements (App Store Connect)

1. Enroll in the Apple Developer Program (individual, ~€109/yr).
2. **Agreements, Tax, and Banking** → accept the **Paid Apps** agreement and
   complete **banking + tax (W-8BEN)**. Required even at $1.49.
3. **EU Digital Services Act trader status** → enter the public **name, address,
   phone, email** (shown on the product page). Without this the app can't ship in
   the EU. Use a P.O. box + dedicated email if you don't want home details public.

### 2. Xcode signing + privacy manifest

Open `ios/Runner.xcworkspace` and `macos/Runner.xcworkspace`:

1. Runner target → **Signing & Capabilities** → set your **Team**
   (sets `DEVELOPMENT_TEAM`). Set the macOS target to **Automatic** signing.
2. **Add `PrivacyInfo.xcprivacy` to the Runner target.** The files exist
   (`ios/Runner/PrivacyInfo.xcprivacy`, `macos/Runner/PrivacyInfo.xcprivacy`) but
   must be in the target's _Copy Bundle Resources_ or they won't ship. In Xcode:
   right-click the Runner group → _Add Files…_ → select the file → tick the
   **Runner** target. (Already declared: no tracking, no data, UserDefaults
   `CA92.1`.)
3. `ITSAppUsesNonExemptEncryption=false` is already in both `Info.plist`s, so
   uploads won't prompt for export compliance.

### 2b. Multicast entitlement (iOS discovery)

SSDP discovery multicasts `M-SEARCH` to `239.255.255.250:1900`; on physical
iPhones that send is silently dropped unless the app carries the **restricted**
`com.apple.developer.networking.multicast` entitlement. (A unicast /24 sweep in
`ssdp_discovery_io.dart` is kept as a fallback regardless. macOS needs nothing —
the capability isn't applicable there.)

- ✅ **Done:** entitlement **requested** from Apple (developer.apple.com →
  "Multicast Networking Entitlement Request", discovery `239.255.255.250:1900`);
  the key is in `ios/Runner/Runner.entitlements`.
- ⏳ **After Apple grants it:**
  1. Identifiers → `be.casperverswijvelt.sonority` → enable **Multicast
     Networking** → Save. (Main app only — **not** the `…ProfileWidget` App ID.)
  2. Regenerate the shared profile so it carries the entitlement:
     `bundle exec fastlane ios certificates`. Otherwise CI's readonly `match`
     pulls a stale profile and signing/upload fails.
  3. Only then merge / cut a signed build. **A signed iOS build before the grant
     fails signing** ("provisioning profile doesn't include the … multicast
     entitlement") — local `Archive` / `fastlane ios beta` and the CI
     `ios-testflight` lane; the `ios-unsigned` job is unaffected.

### 3. Create the app records

App Store Connect → **Apps → +** → New App, for the bundle id
`be.casperverswijvelt.sonority`. Create an **iOS** app and (separately) a
**macOS** app. Set:

- Price: **$1.49 / €1.49** tier.
- Primary category: **Utilities**. Age rating: 4+.
- Privacy "Data collection": **No, we do not collect data** (matches the manifest).

### 4. Listing content

From `app-store/listing.md`: name, subtitle, description, keywords, promo text,
**review notes** (critical — reviewers won't have speakers; include a demo video
link). Host the two pages and set the URLs:

- **Privacy Policy URL** (required): host `privacy-policy.html`.
- **Support URL** (required): host `support.html`.
- **Hosting (GitHub Pages):** repo **Settings → Pages → Build and deployment →
  Deploy from a branch → `main` / `/docs`** → Save. A landing page
  (`docs/index.html`) links both. Live URLs (the github.io paths 301-redirect to
  the `casperverswijvelt.be` custom domain — use the `.be` ones in App Store Connect):
  - `https://casperverswijvelt.be/Sonority/privacy-policy.html`
  - `https://casperverswijvelt.be/Sonority/support.html`
    (This is a one-time GitHub setting — can't be flipped from the CLI without a
    token. Give it a minute after saving to go live.)
- Support email + privacy "last updated" date are filled in. Only `DEMO_VIDEO_URL`
  (in the listing's review notes) remains — paste it once you've recorded the demo.

### 5. Screenshots

Ready-to-upload, correctly-sized frames live in **`design/appstore/`** — regenerate
them any time with the pipeline in **`docs/MARKETING-ASSETS.md`**.

- **iPhone 6.9"** — `design/appstore/iphone69-*.png` (1290×2796). This is the only
  required iPhone size; Apple auto-scales it to smaller iPhones, so a 6.5" set is
  no longer needed.
- **macOS** — `design/appstore/mac-*.png` (2560×1600).
- **iPad** — not applicable; the iOS app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).

## Build, test, submit

1. Xcode → select **Any iOS Device** → **Product → Archive** → Organizer →
   **Validate App** (catches missing manifest/encryption issues), then
   **Distribute App → App Store Connect → Upload**. Repeat for the macOS scheme.
   (Alternatively upload the `.ipa`/`.pkg` with **Transporter**.)
2. **TestFlight**: install the uploaded build on your own device; confirm real
   discovery + one bonding round-trip, and the LED blink, against live hardware.
3. Add the build to the version, answer the App Privacy questions, and
   **Submit for Review**. Ship **iOS first**; submit macOS once iOS is approved.

## Per-release

Version numbering is shared with Android — see the `versionCode` formula in
`PUBLISHING.md` (`pubspec.yaml` `version: X.Y.Z+N`). For Apple, `X.Y.Z` is the
version string and `N` (`CFBundleVersion`) must strictly increase per upload.
Bump `pubspec.yaml`, update `CHANGELOG.md`, archive, upload, submit.

## Automate with Fastlane (scaffolded — `fastlane/`)

Lanes are ready; they build the Flutter app, sign/export via `gym`, and upload
via `pilot`/`deliver`, authenticating with an **App Store Connect API key** (no
2FA). Local-first (run from your Mac); also usable in CI later.

**One-time, after enrollment:**

1. `bundle install` (installs Fastlane from the `Gemfile`).
2. Create the API key: App Store Connect → Users and Access → Integrations →
   App Store Connect API → Team Keys → **(+)**, role **App Manager**. Download
   `AuthKey_XXXX.p8` (one-time) into `fastlane/`.
3. `cp fastlane/.env.example fastlane/.env` and fill in `ASC_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_KEY_FILEPATH`. (`.env` and `*.p8` are gitignored.)
4. Make sure the Team is set on the Runner targets in Xcode (step 2 above) — the
   lanes use automatic signing via `-allowProvisioningUpdates`.

**Then, per build:**

```sh
bundle exec fastlane ios beta       # → TestFlight
bundle exec fastlane ios release    # → submit for App Store review
bundle exec fastlane mac beta       # → TestFlight (macOS)
bundle exec fastlane mac release    # → submit (macOS)
bundle exec fastlane mac github     # → Developer ID-signed + notarized .dmg (dist/)
```

### Notarized macOS `.dmg` (direct download / GitHub Release)

`mac github` produces the signed + notarized `.dmg` attached to the GitHub Release.
It signs with a **Developer ID Application** certificate (distinct from the App
Store cert) and notarizes via the App Store Connect API key.

The Developer ID cert is **not** stored in match (match needs an empty-passphrase
p12 and logs in to the portal on import — both painful in CI). Instead the whole
identity is two GitHub secrets the `macos-dmg` job imports straight into its
keychain.

**One-time setup (Account Holder only):** a **Developer ID Application** cert
**cannot be created via the App Store Connect API** — Apple restricts creation to
the Account Holder, through Xcode or the Developer portal:

1. **Xcode → Settings → Accounts → (your team) → Manage Certificates → ＋ →
   Developer ID Application.** Installs the cert + private key in your login
   keychain. (Apple caps these at **2 per account**.)
2. **Keychain Access** → export the identity `Developer ID Application: …` as a
   `.p12` (any password — keep it, it goes in a secret).
3. **Set the two repo secrets** (Settings → Secrets → Actions):
   ```sh
   base64 -i devid.p12 | gh secret set MACOS_DEVID_P12_BASE64
   gh secret set MACOS_DEVID_P12_PASSWORD --body 'THE_P12_PASSWORD'
   ```
The CI `macos-dmg` job decodes the p12 and `import_certificate`s it with that
password, then `mac github` signs + notarizes. (Locally, `mac github` just uses
the identity already in your login keychain.)

Notarization requires the **Hardened Runtime** (the lane passes
`ENABLE_HARDENED_RUNTIME=YES`; also enable it on the macOS Runner target in Xcode
so it's baked into the archive). In CI the `macos-dmg` job runs `mac github`
automatically on a `v*` tag; with no signing secrets it falls back to an unsigned
`.dmg`.

The first `release` still needs the screenshots/description filled in App Store
Connect (or run `deliver` with a metadata folder later).

**CI (optional, later):** the same lanes can run in GitHub Actions on a `v*` tag
like the Android lane, with the `.p8` + key ids as repo secrets. iOS signing in
CI is the fiddly part (needs the cert/profile available to the runner); defer
until the local flow is proven.
