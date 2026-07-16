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
| Source app screenshots (raw captures) | `design/shots/0N-*.png` (1290×2796) |
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

The landing page (`docs/index.html`, served by GitHub Pages) is **generated** —
`dart run tool/gen_site.dart` reuses the tagline from `pubspec.yaml` and the four
`SHOTS` captions from `design/store.html` (no text is copy-pasted), filling
`tool/site_template.html`. Re-run it after changing either source, and commit the
regenerated `docs/index.html`.

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

One command captures all four — add `--frame` to also render every framed store
graphic (§3) in the same run:

```sh
~/fvm/versions/3.44.6/bin/dart run tool/capture_shots.dart          # raw shots only
~/fvm/versions/3.44.6/bin/dart run tool/capture_shots.dart --frame  # shots + framed graphics
```

It builds `flutter build web --release --dart-define=DEMO=true`, serves it, and
drives headless Chrome over the DevTools Protocol — deep-linking to each screen
by its go_router URL (no tapping) and waiting for Flutter to render (incl. the
wordmark PNG) before shooting into `design/shots/0N-*.png` at 1290×2796. No
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

`tool/capture_shots.dart --frame` (§2) renders all of these automatically —
`design/store.html` framed at each store size via the same headless Chrome, into
`design/play/*` and `design/appstore/*`. To re-frame existing shots without
re-capturing (e.g. after editing `store.html`), run `--frame --no-capture`.

What it produces (the tool's job list mirrors this — `?mode=` picks the layout,
`?i=` 0–3 picks the source shot):

| Output | mode | size |
|---|---|---|
| `design/play/feature-graphic.png` | `feature` | 1024×500 |
| `design/play/tablet-7in.png` | `tablet7` | 1920×1080 |
| `design/play/tablet-10in.png` | `tablet10` | 2560×1440 |
| `design/play/phone-{1..4}-*.png` | `phone` | 1080×1920 |
| `design/appstore/iphone69-{1..4}-*.png` | `ios69` | 1290×2796 (iPhone 6.9") |
| `design/appstore/mac-{1..4}-*.png` | `mac` | 2560×1600 |

`design/play/play-icon-512.png` is the app icon (regenerate from
`design/export.html`, below, only if the icon changes — not part of `--frame`).
For the README gallery, copy the raw `design/shots/*` into `docs/screenshots/*`.

To render one graphic by hand (e.g. debugging `store.html`), it's still a plain
headless-Chrome screenshot at device-scale-factor 1:

```sh
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --force-device-scale-factor=1 \
  --hide-scrollbars --window-size=1290,2796 --virtual-time-budget=3500 \
  --screenshot=out.png "file://$PWD/design/store.html?mode=ios69&i=0"
```

### App icon + wordmark (single source: `design/export.html`)

`design/export.html` is the **single source of truth** for every raster icon,
wordmark, splash, and Icon Composer layer — each emitted by a `?mode=`. **Don't
hand-edit the PNGs** (that is how they drifted before): change `export.html`, then
run the generator, which renders every mode at the right size/aspect and fans them
out to the native trees:

```sh
tool/gen_assets.sh          # CHROME=… to override the browser
```

It reverts the manifest/web overreach `flutter_native_splash` introduces (it strips
`android:screenOrientation="portrait"` and injects a web splash). Review with
`git diff --stat` — expect only intended asset churn.

**`?mode=` outputs** (all mark-only icons — Apple HIG discourages icon text and the
Android mask clips it; the wordmark lives in the lockup/splash/marketing only):

| `mode` | Output | Notes |
|---|---|---|
| `icon` | `design/assets/icon.png` (1024) | full-bleed square; iOS/Android-legacy + splash image; `&round` = README corners |
| `iconfg` | `design/assets/icon_fg.png` | Android adaptive foreground — **transparent** bg (background-color layer shows) |
| `iconmono` | `design/assets/icon_mono.png` | Android 13+ **monochrome/themed** layer (holes cut out) |
| `icon-macos` | `design/assets/icon_macos.png` | macOS **squircle** (rounded + ~10% margin) fallback |
| `icon-a12` | `design/assets/icon_android12.png` (1152) | Android-12 splash icon, fits the **768px** circular mask |
| `wordmark` | `assets/brand/sonority_wordmark.png` (2500×650) | **Futura Medium**, white-on-alpha; splash branding + in-app appbar + marketing |
| `wordmark-a12` | `design/assets/wordmark_android12.png` (800×320) | Android-12 branding — letterboxed to the fixed **2.5:1** region (no vertical stretch) |
| `icontext&round` | `docs/icon.png` | README header lockup (mark + wordmark) |
| `layer-back` / `layer-front` | `design/assets/layers/*.png` | Icon Composer glass-pane layers (below) |

The parametric design twin is `design/logo.html`; concept exploration is archived
in `design/logo_concepts.html`.

### Layered iOS/macOS icon (Icon Composer, glass panes)

iOS 26 / macOS 26 render a layered `.icon` with the Liquid Glass material. Rather
than fighting the glow, the speaker cabinets are authored as **translucent glass
panes**. `tool/gen_assets.sh` exports the layer art (`design/assets/layers/`:
`layer-back` + `layer-front` — both plain **white opaque** panes, each with its own
tweeter/woofer holes as alpha cut-outs, front stacked over back; the background is a
solid `#000000` fill set in Icon Composer, not a layer). Colour/opacity/glass (incl.
the back speakers' grey) are tuned
non-destructively in Icon Composer, not baked into the source. **Manual step** (Icon Composer.app,
ships with Xcode 26 — or `icon-composer-mcp`): import the layers (front > back),
apply the glass material with tuned opacity, set the **icon Background fill to solid
`#000000`** (NOT just a bg layer — the default is a blue gradient that bleeds
through the group translucency), preview Default/Dark/Tinted, export `Sonority.icon`.

The authored `Sonority.icon` is committed at **`ios/Runner/Sonority.icon`** and
**`macos/Runner/Sonority.icon`**, wired via `ASSETCATALOG_COMPILER_APPICON_NAME =
Sonority` in each Runner target (actool compiles the layered icon + its raster
fallbacks). **To update it:** re-export from Icon Composer over both copies and
rebuild — no pbxproj change needed. Note: `flutter_launcher_icons` resets the iOS
`ASSETCATALOG_COMPILER_APPICON_NAME` back to `AppIcon`, so `tool/gen_assets.sh`
**re-asserts** `= Sonority` on both Runner targets at the end (the `.icon` file
references themselves are never removed).

The PNG `AppIcon.appiconset` is still generated (by `flutter_launcher_icons`) but is
**not** what ships: with `APPICON_NAME = Sonority`, actool compiles the `.icon`'s own
rasterised fallbacks even for pre-26 OSes, so `AppIcon` is unreferenced. It's kept as a
manual recovery path only — flip `APPICON_NAME` back to `AppIcon` (e.g. if a submission
ever rejects the `.icon`) and the PNG set takes over.

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
