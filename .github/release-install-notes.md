## Install

**Android — `Sonority-*.apk`** (release build, debug-signed)
- On your phone: download the APK, allow “install unknown apps” for your browser/files app, then open it.
- Or via adb: `adb install -r Sonority-*.apk`

**macOS — `Sonority-*-macos.zip`** (unsigned, not notarized)
- Unzip it, then strip the Gatekeeper quarantine flag — otherwise macOS reports the app is “damaged” / won’t open:
  ```sh
  xattr -r -d com.apple.quarantine Sonority.app
  ```
  If it’s in a protected location and that’s denied, use sudo:
  ```sh
  sudo xattr -r -d com.apple.quarantine Sonority.app
  ```
- Then open it (first launch: right-click → Open). Move it to `/Applications` if you like.

**iOS — `Sonority-*-ios-unsigned.ipa`** (unsigned; must be re-signed to install)
- Sideload with [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) using your Apple ID, or re-sign with your own provisioning profile.
- A plain install isn’t possible without signing.

> On every platform, keep the device on the **same Wi‑Fi** as your Sonos. iOS and macOS will prompt for **local network** access on the first scan — allow it, or discovery finds nothing.
