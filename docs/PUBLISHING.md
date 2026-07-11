# Publishing to Google Play

CI (`.github/workflows/release.yml`) builds a **signed release AAB** and uploads
it to the **open testing** track (Play "beta") whenever a `vX.Y.Z-<rebuild>` tag is pushed — *once*
the one-time setup below is done. Without the secrets it just builds a
debug-signed APK and skips Play (so the workflow never breaks for forks).

> Listing copy is in `app-store/listing.md` (it serves both stores); the store
> graphics + screenshots and how to regenerate them are in
> [`MARKETING-ASSETS.md`](MARKETING-ASSETS.md).

## One-time setup

### 1. Create an upload keystore
```sh
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Pick a store password + key password and **keep them safe** — every future
upload must use this same key. Never commit the `.jks`.

### 2. (Optional) build & verify locally
Copy `android/key.properties.example` to `android/key.properties` (gitignored),
fill in the absolute keystore path + passwords, then:
```sh
~/fvm/versions/3.35.2/bin/flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

### 3. First upload is manual (required)
The Play API can't publish until the app exists and one bundle has been uploaded
by hand:
1. Play Console → **Create app** (name *Sonority*, App, language, free).
2. Complete the **"Set up your app"** dashboard tasks (privacy policy, data
   safety, content rating, target audience, ads) — required before *any* track
   can go live.
3. **Testing → Internal testing → Create new release** → upload the AAB from
   step 2. Accept **Play App Signing** (let Google generate the app signing key;
   your keystore becomes the *upload* key). Add testers, then roll out.

### 4. Service account for CI
1. Play Console → **Setup → API access** → link/create a Google Cloud project.
2. In Google Cloud Console → **IAM & Admin → Service Accounts** → create one
   (no GCP roles needed) → **Keys → Add key → JSON** → download.
3. Back in Play Console API access → grant that service account access to this
   app with **"Release to testing tracks"** (or Admin).

### 5. GitHub repo secrets
Settings → Secrets and variables → Actions → *New repository secret*:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/upload-keystore.jks \| pbcopy` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore (store) password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password |
| `PLAY_SERVICE_ACCOUNT_JSON` | full contents of the downloaded JSON |

## Every release
`versionCode` (the `+N` in `pubspec.yaml`'s `version: X.Y.Z+N`) is **derived from
the semver**, not hand-incremented:

    versionCode = major*1000000 + minor*10000 + patch*100 + build

`build` (0+) only distinguishes rebuilds of the *same* X.Y.Z. Examples:
`0.3.0` → `30000`, `0.3.0` rebuild → `30001`, `0.3.1` → `30100`, `1.0.0` →
`1000000`. Stays strictly increasing as long as the version climbs (≤99 rebuilds
per patch, ≤99 patches per minor, etc.).

Before tagging:
1. Set `version:` in `pubspec.yaml` to the computed `+N`.
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` (and
   start a fresh empty `[Unreleased]` above it). CI slices that section into the
   GitHub Release notes, followed by the install instructions.
3. Commit, then tag `vX.Y.Z-<rebuild>` — the rebuild counter from the
   versionCode formula above (e.g. `0.5.0+50012` → `v0.5.0-12`). Tags are
   unique per build and never moved, reused, or deleted; a re-cut gets
   rebuild+1 and a fresh tag:
```sh
git tag v0.5.0-12 && git push origin v0.5.0-12
```
CI signs the AAB, pushes it to Play open testing (the "beta" track), and
publishes the GitHub Release (changelog section + install notes) marked as **pre-release** — remove
that mark when it actually ships. Previous releases are never deleted. Promote
to production in the Console when ready.
