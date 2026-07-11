# Marketing assets — how to refresh listings & screenshots

Everything a store listing needs: the copy, the screenshots, and the framed
graphics for Google Play + the Apple App/Mac App Store. This is the repeatable
recipe — follow it whenever features change or the UI theme moves. It was used to
produce the current set; redo the same steps to regenerate.

## What lives where

| Asset | Path |
|---|---|
| Listing copy (App Store **and** Play) | `docs/app-store/listing.md` |
| One-line app description | `pubspec.yaml` `description:` |
| README screenshot gallery | `README.md` → `docs/screenshots/*` |
| Source app screenshots (raw captures) | `design/shots/0N-*.png` (1080×2400) |
| Parametric graphics generator | `design/store.html` |
| Google Play graphics | `design/play/*` |
| Apple screenshots (iPhone + macOS) | `design/appstore/*` |
| CHANGELOG (drives GitHub release notes) | `CHANGELOG.md` |

## 1. Copy — keep it in sync with the feature set

When features ship, update all four in one pass, cross-checking `CHANGELOG.md`:

1. `docs/app-store/listing.md` — subtitle, promotional text, keywords,
   description (**WHAT YOU CAN DO**), and **What's New**. Mind the limits: name
   ≤30, subtitle ≤30, promo ≤170, keywords ≤100, description ≤4000. Keep
   "Sonos" **out** of the name/subtitle/icon (App Store Guideline 5.2.1) — it may
   appear descriptively in the body/keywords only, with the disclaimer.
2. `pubspec.yaml` `description:`.
3. `design/store.html` — the `SHOTS` captions + the feature/tablet blurbs.
4. `README.md` screenshot alt text.

## 2. Screenshots — the four canonical screens

Sonority markets four screens: **overview**, **home-theater detail**,
**group creation**, **profiles**. Capture them with the app in **demo mode**
(`--dart-define=DEMO=true`, see `lib/demo/demo_mode.dart`): it feeds the UI a
hand-crafted photogenic system — a Living Room 5.1 with dedicated fronts, an
Office stereo pair, a 3-speaker Upstairs zone, three standalone rooms, and two
seeded profiles — with **no LAN, no real hardware, no staging, and no revert
step**. Demo mode is navigation-only: apply/bond/identify taps fail fast (the
demo SOAP client throws, so a demo build emits no network I/O at all).

### Capture (Flutter web + headless Chrome)

One command captures all four:

```sh
~/fvm/versions/3.35.2/bin/dart run tool/capture_shots.dart
```

It builds `flutter build web --release --dart-define=DEMO=true`, serves it, and
drives headless Chrome over the DevTools Protocol — deep-linking to each screen
by its go_router URL (no tapping) and waiting for Flutter to render (incl. the
wordmark PNG) before shooting into `design/shots/0N-*.png` at 1080×2400. No
emulator, no device, no LAN. `--no-build` reuses an existing `build/web`; set
`$CHROME` to override the browser. (The **web target is screenshot-only**, not a
shipped app — a browser can't do SSDP/sockets, so it only runs under `DEMO=true`.)

There's no OS status bar on a web canvas — so no `9:41`/battery faking to do, and
the look is identical for every store frame. Demo mode injects safe-area padding
(`lib/app.dart`, gated to `kIsWeb`) so the top/bottom don't look crammed. Two
Chrome details the tool bakes in and the framer relies on: `--enable-unsafe-
swiftshader` (else CanvasKit falls back to CPU rendering and draws images blank),
and a render-settle before each shot.

The four land as `design/shots/01-overview.png`, `02-home-theater.png`,
`03-group.png`, `04-profiles.png` — the exact files §3's framer reads.

### Changing what the screenshots show

Edit the fake system/profiles in `lib/demo/demo_mode.dart` — no live-Sonos
staging or revert ritual anymore. `test/demo_mode_test.dart` guards the
hand-written channel-map strings, so keep it in sync.

## 3. Generate the framed graphics

`design/store.html` renders every store size from the four source shots. Export
with headless Chrome at device-scale-factor 1 so the PNG is exactly the window
size:

```sh
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BASE="file://$PWD/design/store.html"
shot(){ "$CHROME" --headless=new --disable-gpu --force-device-scale-factor=1 \
  --hide-scrollbars --window-size=$2,$3 --virtual-time-budget=3500 \
  --screenshot="$4" "$BASE?mode=$1&i=${5:-0}" >/dev/null 2>&1; }

# Google Play → design/play/
shot feature 1024 500  design/play/feature-graphic.png
shot tablet7 1920 1080 design/play/tablet-7in.png
shot tablet10 2560 1440 design/play/tablet-10in.png
shot phone 1080 1920 design/play/phone-1-overview.png 0   # i=1 home-theater, 2 group, 3 profiles

# Apple → design/appstore/
shot ios69 1290 2796 design/appstore/iphone69-1-overview.png 0   # iPhone 6.9"
shot mac   2560 1600 design/appstore/mac-1-overview.png 0        # macOS
```

`i` (0–3) selects the source shot; `design/play/play-icon-512.png` is the app icon
(regenerate from `design/export.html`, below, only if the icon changes). For the
README gallery, copy the raw `design/shots/*` into `docs/screenshots/*`.

### App icon + wordmark (from `design/export.html`)

The launcher icon is the **mark only** (the 9c-3 speaker trio) on every platform;
the "SONORITY" wordmark lives in the logo lockup, not the icon. Sources render
from `design/export.html` the same headless way:

```sh
BASE="file://$PWD/design/export.html"
shot(){ "$CHROME" --headless=new --disable-gpu --force-device-scale-factor=1 \
  --hide-scrollbars --window-size=$2,$3 --virtual-time-budget=2500 \
  --screenshot="$4" "$1" >/dev/null 2>&1; }

shot "$BASE?mode=icon"    1024 1024 design/assets/icon.png      # iOS/macOS/Android-legacy + splash
shot "$BASE?mode=iconfg"  1024 1024 design/assets/icon_fg.png   # Android adaptive foreground (safe inset)
shot "$BASE?mode=wordmark" 1000 260 design/assets/wordmark.png  # splash branding (unchanged unless the wordmark changes)
shot "$BASE?mode=icon"     512  512 design/play/play-icon-512.png  # Play store icon
shot "$BASE?mode=icon"     512  512 docs/icon.png                  # README header icon
```

Then regenerate the native icon sets + splash and revert the manifest churn the
splash tool introduces (it strips `android:screenOrientation="portrait"`):

```sh
~/fvm/versions/3.35.2/bin/dart run flutter_launcher_icons
~/fvm/versions/3.35.2/bin/dart run flutter_native_splash:create
git checkout android/app/src/main/AndroidManifest.xml   # keep portrait-only + avoid reformat churn
```

The parametric source of the mark is `design/logo.html` (icon + lockup); the full
concept exploration is archived in `design/logo_concepts.html`.

Verify every output's exact pixels:

```sh
sips -g pixelWidth -g pixelHeight design/appstore/*.png design/play/*.png
```

## Required dimensions

| Store | Asset | Size (px) | `mode` |
|---|---|---|---|
| App Store | iPhone 6.9" | 1290 × 2796 | `ios69` |
| App Store | macOS | 2560 × 1600 | `mac` |
| App Store | iPad | — (iPhone-only app) | — |
| Google Play | Feature graphic | 1024 × 500 | `feature` |
| Google Play | Phone | 1080 × 1920 | `phone` |
| Google Play | 7" tablet | 1920 × 1080 | `tablet7` |
| Google Play | 10" tablet | 2560 × 1440 | `tablet10` |
| Google Play | Icon | 512 × 512 | (from `design/export.html`) |

Apple needs only the 6.9" iPhone set (auto-scaled to smaller iPhones); 6.5" is no
longer required.
