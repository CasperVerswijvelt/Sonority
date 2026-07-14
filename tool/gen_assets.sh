#!/usr/bin/env bash
# Regenerate ALL app-icon / wordmark / splash / Icon-Composer-layer assets from the
# single source of truth `design/export.html`, then fan them out to the native
# platform trees. Reproducible replacement for the old hand-typed recipe — run this
# whenever the mark or wordmark changes so the assets can never drift again.
#
#   tool/gen_assets.sh
#   CHROME="/path/to/Chrome" tool/gen_assets.sh   # override the browser
#
# Requires: Google Chrome (headless) + fvm Flutter 3.35.2. macOS-oriented (sips/magick
# available), same as the rest of tool/.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
FLUTTER="$HOME/fvm/versions/3.35.2/bin/flutter"
DART="$HOME/fvm/versions/3.35.2/bin/dart"
BASE="file://$PWD/design/export.html"

# shot <query> <w> <h> <out> — render one export.html mode to a PNG. The SVG fills
# the window (viewBox scaling), so W:H MUST match the mode's viewBox aspect or it
# stretches. Chrome bg is transparent; opaque modes (icon/icontext) paint their own.
shot(){
  "$CHROME" --headless=new --disable-gpu --force-device-scale-factor=1 \
    --hide-scrollbars --window-size="$2,$3" --virtual-time-budget=2500 \
    --default-background-color=00000000 --screenshot="$4" "$BASE?$1" >/dev/null 2>&1
  echo "  ✓ $4 (${2}x${3})"
}

echo "==> Rendering assets from design/export.html"
mkdir -p design/assets/layers design/play

# Icons (square, 1:1 windows)
shot "mode=icon"       1024 1024 design/assets/icon.png            # iOS/macOS/Android-legacy + splash image
shot "mode=iconfg"     1024 1024 design/assets/icon_fg.png         # Android adaptive foreground (transparent)
shot "mode=iconmono"   1024 1024 design/assets/icon_mono.png       # Android 13+ themed/monochrome layer
shot "mode=icon-macos" 1024 1024 design/assets/icon_macos.png      # macOS squircle fallback (rounded + margin)
shot "mode=icon-a12"   1152 1152 design/assets/icon_android12.png  # Android 12 splash icon (fits 768 circle)
shot "mode=icon"        512  512 design/play/play-icon-512.png     # Play store icon

# Wordmark — Futura Medium, white glyphs on transparent alpha. High-res so it never
# upscales on device (aspect MUST stay 1000:260). Then TRIM to the glyph bbox: the
# in-app appbar draws it at a fixed height, so any surrounding padding would shrink
# the letters. -trim only removes transparent margin (never clips the glyphs).
shot "mode=wordmark"       2500 650 assets/brand/sonority_wordmark.png   # in-app appbar + marketing (Flutter scales it down; keep hi-res)
magick assets/brand/sonority_wordmark.png -trim +repage assets/brand/sonority_wordmark.png
# Splash branding (iOS storyboard + Android-legacy launch_background). flutter_native_splash
# maps source RESOLUTION → point size (@1x ≈ source/4), so render a moderate ~600px-wide
# wordmark (~150pt on device). Render it FRESH from the vector (a small Chrome shot, like
# wordmark-a12) then trim — NOT a downscale of the hi-res raster, which fattens the strokes
# and makes the iOS wordmark look heavier than Android's vector-rendered one.
shot "mode=wordmark"        764 199 design/assets/wordmark_splash.png
magick design/assets/wordmark_splash.png -trim +repage design/assets/wordmark_splash.png
# Android 12 branding stays LETTERBOXED (do NOT trim) — the OS renders it into a
# fixed 2.5:1 region and would stretch a tight image.
shot "mode=wordmark-a12"    800 320 design/assets/wordmark_android12.png

# README header lockup (mark + wordmark, rounded, transparent)
shot "mode=icontext&round" 512 512 docs/icon.png

# Icon Composer layers for the iOS/macOS glass-pane .icon (front > back > bg).
# Each pane carries its own cone holes as cut-outs; front occludes back.
shot "mode=layer-bg"    1024 1024 design/assets/layers/layer-bg.png
shot "mode=layer-back"  1024 1024 design/assets/layers/layer-back.png
shot "mode=layer-front" 1024 1024 design/assets/layers/layer-front.png

echo "==> Regenerating native icon sets + splash"
"$DART" run flutter_launcher_icons
"$DART" run flutter_native_splash:create

# The splash generator overreaches: it strips android:screenOrientation="portrait"
# from the manifest (portrait-only is required) and injects a web splash (web is
# screenshot-only here). Revert both.
git checkout -- android/app/src/main/AndroidManifest.xml
git checkout -- web/index.html 2>/dev/null || true
rm -rf web/splash

# flutter_launcher_icons resets the iOS Runner's ASSETCATALOG_COMPILER_APPICON_NAME
# back to "AppIcon" — which clobbers the layered glass Sonority.icon. Re-assert it on
# both platforms (the .icon file refs already live in the committed pbxproj).
if ruby -e 'require "xcodeproj"' 2>/dev/null; then
  for PROJ in ios/Runner.xcodeproj macos/Runner.xcodeproj; do
    ruby -e 'require "xcodeproj"; p=Xcodeproj::Project.open(ARGV[0]); t=p.targets.find{|t|t.name=="Runner"}; t.build_configurations.each{|c| c.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"]="Sonority"}; p.save' "$PROJ"
    echo "  ✓ re-asserted Sonority app icon in $PROJ"
  done
else
  echo "  ⚠ ruby/xcodeproj not found — set ASSETCATALOG_COMPILER_APPICON_NAME=Sonority manually in ios/macos Runner targets"
fi

# flutter_native_splash downscales the iOS branding with a nearest-neighbour filter →
# hard, aliased edges, which iOS shows ~1:1 on the splash. Regenerate the three scales
# from the crisp hi-res wordmark with a high-quality (Lanczos) reduction: smooth AA,
# matched stroke weight. @1x width = 150 sets the storyboard's ~150pt display size.
IMS=ios/Runner/Assets.xcassets/BrandingImage.imageset
magick assets/brand/sonority_wordmark.png -filter Lanczos -resize 150x "$IMS/BrandingImage.png"
magick assets/brand/sonority_wordmark.png -filter Lanczos -resize 300x "$IMS/BrandingImage@2x.png"
magick assets/brand/sonority_wordmark.png -filter Lanczos -resize 450x "$IMS/BrandingImage@3x.png"
echo "  ✓ re-rendered iOS BrandingImage @1x/2x/3x (crisp, anti-aliased)"

echo "==> Done. Review 'git diff --stat' — expect only intended asset churn."
