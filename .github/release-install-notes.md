## Install

**iOS & macOS — TestFlight (recommended)**
- Join the beta: [TestFlight](TESTFLIGHT_URL). Installs the signed app and keeps it auto-updated.

Or install a direct download from the assets below:

**Android — `Sonority-*.apk`** (release-signed)
- On your phone: download the APK, allow “install unknown apps” for your browser/files app, then open it.
- Or via adb: `adb install -r Sonority-*.apk`

**macOS — `Sonority-*-macos.dmg`** (Developer ID-signed & notarized)
- Open the `.dmg`, drag **Sonority** to Applications, and launch it. No Gatekeeper workaround needed — Apple has notarized it.

**iOS — `Sonority-*-ios-unsigned.ipa`** (unsigned; sideload only)
- Prefer TestFlight above. To sideload the raw `.ipa`, re-sign it with [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) using your Apple ID. A plain install isn’t possible without signing.

> On every platform, keep the device on the **same Wi‑Fi** as your Sonos. iOS and macOS will prompt for **local network** access on the first scan — allow it, or discovery finds nothing.
