# Publishing to the App Store (iOS + Mac)

Companion to `PUBLISHING.md` (Google Play). Covers the one-time Apple setup and
the per-release flow. Listing copy lives in `app-store/listing.md`; the required
legal pages are `privacy-policy.html` + `support.html` (host them, see below).

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
   must be in the target's *Copy Bundle Resources* or they won't ship. In Xcode:
   right-click the Runner group → *Add Files…* → select the file → tick the
   **Runner** target. (Already declared: no tracking, no data, UserDefaults
   `CA92.1`.)
3. `ITSAppUsesNonExemptEncryption=false` is already in both `Info.plist`s, so
   uploads won't prompt for export compliance.

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
  (`docs/index.html`) links both. URLs become:
  - `https://casperverswijvelt.github.io/Sonority/privacy-policy.html`
  - `https://casperverswijvelt.github.io/Sonority/support.html`
  (This is a one-time GitHub setting — can't be flipped from the CLI without a
  token. Give it a minute after saving to go live.)
- Replace `SUPPORT_EMAIL` / `REPLACE_DATE` / `DEMO_VIDEO_URL` placeholders first.

### 5. Screenshots
Required sizes (Apple rejects missing ones):
- iPhone 6.9" and 6.5".
- iPad 13" only if you keep iPad support enabled.
- macOS (1280×800 or 2560×1600).
Starting frames are in `docs/screenshots/`; regenerate at the exact sizes.

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
```
The first `release` still needs the screenshots/description filled in App Store
Connect (or run `deliver` with a metadata folder later).

**CI (optional, later):** the same lanes can run in GitHub Actions on a `v*` tag
like the Android lane, with the `.p8` + key ids as repo secrets. iOS signing in
CI is the fiddly part (needs the cert/profile available to the runner); defer
until the local flow is proven.
