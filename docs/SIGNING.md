# Signing & release secrets — where everything lives

A **map**, not a secret store. **No secret values live in this file (or any committed
file).** Each row says where to find a value/file. Three homes:

- **Bitwarden** ("Sonority signing" note) — the durable master copies.
- **GitHub Actions secrets** (repo → Settings → Secrets and variables → Actions) — what CI uses.
- **Local gitignored files** — what local `fastlane`/Gradle use. These live in a working
  checkout (incl. disposable `.claude/worktrees/…`), so they are **working copies, not backups**.

The Apple certificates themselves are stored **encrypted in the private match repo**
(`MATCH_GIT_URL`), decryptable only with `MATCH_PASSWORD`.

## Constants (not secret; already in the repo)
- Bundle id / Android namespace: `be.casperverswijvelt.sonority`
- Apple Team ID: `V95M6HBV65` (see `fastlane/Fastfile`)
- App Store Connect app: **Sonority for Sonos**

## Apple — App Store Connect API key (TestFlight, notarization, match auth)
| Item | Bitwarden | GitHub secret | Local file |
|---|---|---|---|
| ASC Key ID | ✓ | `ASC_KEY_ID` | `fastlane/.env` → `ASC_KEY_ID` |
| ASC Issuer ID | ✓ | `ASC_ISSUER_ID` | `fastlane/.env` → `ASC_ISSUER_ID` |
| `.p8` private key (file) | ✓ (attach) | `ASC_KEY_BASE64` (base64) | `fastlane/AuthKey_<KEYID>.p8` |

The `.p8` downloads only **once** from App Store Connect. If lost: create a new key
(Users and Access → Integrations), then update `fastlane/.env` **and** the two GitHub
secrets (`ASC_KEY_ID`, `ASC_KEY_BASE64` = `base64 -i AuthKey_*.p8`).

## Apple — code signing via fastlane match
| Item | Bitwarden | GitHub secret | Local file |
|---|---|---|---|
| `MATCH_PASSWORD` — encrypts the certs repo; **cannot be regenerated** | ✓ | `MATCH_PASSWORD` | `fastlane/.env` |
| `MATCH_GIT_URL` — private certs repo | ✓ | `MATCH_GIT_URL` | `fastlane/.env` |
| `MATCH_GIT_BASIC_AUTHORIZATION` — base64 `user:PAT`, read access to certs repo | ✓ | `MATCH_GIT_BASIC_AUTHORIZATION` | — (regenerate a PAT if lost) |
| App Store distribution cert + profile (iOS + macOS TestFlight) | — | — | the **match repo** (encrypted) |

⚠️ **Lose `MATCH_PASSWORD` and the certs repo is unrecoverable** — you'd `fastlane match nuke`
and regenerate everything. Back it up first.

## Apple — Developer ID `.p12` (the notarized `.dmg`)
Developer ID is **not** in the match repo (match needs an empty-passphrase p12 and logs in to
the portal on import — both awkward in CI). The identity is a single p12 secret the CI
`macos-dmg` job imports straight into its keychain; the `mac github` lane signs with it.

| Item | Bitwarden | GitHub secret | Local file |
|---|---|---|---|
| `devid.p12` (Developer ID cert + private key) | ✓ (attach) | `MACOS_DEVID_P12_BASE64` (base64) | `fastlane/devid.p12` |
| its export password (`<export-password>`) | ✓ | `MACOS_DEVID_P12_PASSWORD` | — |

Created manually in **Xcode** (Account Holder only — the ASC API can't mint Developer ID
certs) and exported from Keychain. Full steps: `docs/PUBLISHING-APPLE.md`.

## Android — upload keystore + Play
| Item | Bitwarden | GitHub secret | Local file |
|---|---|---|---|
| Upload keystore `.jks` — **irreplaceable**: lose it and you can never update the Play app | ✓ (attach) | `ANDROID_KEYSTORE_BASE64` (base64) | path is `storeFile` in `android/key.properties` |
| Keystore (store) password | ✓ | `ANDROID_KEYSTORE_PASSWORD` | `android/key.properties` → `storePassword` |
| Key alias | ✓ | `ANDROID_KEY_ALIAS` | `android/key.properties` → `keyAlias` |
| Key password | ✓ | `ANDROID_KEY_PASSWORD` | `android/key.properties` → `keyPassword` |
| Play service-account JSON | ✓ (attach) | `PLAY_SERVICE_ACCOUNT_JSON` | — (regenerable in Google Cloud) |

## Distribution links (not secret)
- App Store (iOS + macOS, public): `https://apps.apple.com/us/app/sonority-for-sonos/id6785994018`
- Google Play (internal): `https://play.google.com/store/apps/details?id=be.casperverswijvelt.sonority`

The TestFlight beta join link is deliberately NOT recorded here — this repo is
public, and a public TestFlight link is a free bypass of the paid App Store.
Find it in App Store Connect → TestFlight when you need it.

## Gitignored working files (NOT backups)
`fastlane/.env`, `fastlane/AuthKey_*.p8`, `fastlane/devid.p12`, `fastlane/devid.cer`,
`android/key.properties`, and any `*.jks`/`*.keystore` — all in `.gitignore`. The real
backups are Bitwarden + the match repo.
