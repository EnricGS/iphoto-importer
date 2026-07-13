#!/bin/bash
# Regenera totes les icones de l'app (Windows .ico + macOS .icns) des de brand/icon.svg.
# Requereix: rsvg-convert (librsvg), magick (ImageMagick), iconutil (macOS).
set -euo pipefail

cd "$(dirname "$0")/.."   # arrel del repo
SVG="brand/icon.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "🎨 Renderitzant PNGs des de $SVG"

# --- Windows app.ico (multi-mida) ---
ICO_SIZES="16 24 32 48 64 128 256"
ICO_PNGS=()
for s in $ICO_SIZES; do
  rsvg-convert -w "$s" -h "$s" "$SVG" -o "$TMP/ico-$s.png"
  ICO_PNGS+=("$TMP/ico-$s.png")
done
magick "${ICO_PNGS[@]}" app.ico
echo "🪟 app.ico ($ICO_SIZES)"

# --- macOS .icns (iconset estàndard) ---
ISET="$TMP/icon.iconset"
mkdir -p "$ISET"
r(){ rsvg-convert -w "$1" -h "$1" "$SVG" -o "$ISET/$2"; }
r 16   icon_16x16.png
r 32   icon_16x16@2x.png
r 32   icon_32x32.png
r 64   icon_32x32@2x.png
r 128  icon_128x128.png
r 256  icon_128x128@2x.png
r 256  icon_256x256.png
r 512  icon_256x256@2x.png
r 512  icon_512x512.png
r 1024 icon_512x512@2x.png
iconutil -c icns "$ISET" -o "$TMP/AppIcon.icns"
echo "🍎 AppIcon.icns (16→1024)"

# --- Col·loca els .icns a totes les ubicacions ---
ICNS_TARGETS=(
  "MacOS/iPhotoManager/Resources/AppIcon.icns"
  "MacOS/iPhotoManager/Resources/iPhotoManager.icns"
  "MacOS/iPhotoManager.app/Contents/Resources/AppIcon.icns"
  "MacOS/iPhotoManager.app/Contents/Resources/iPhotoManager.icns"
  "MacOS/iPhotoManager.app/Contents/Resources/iPhotoManager_iPhotoManager.bundle/AppIcon.icns"
  "MacOS/iPhotoManager.app/Contents/Resources/iPhotoManager_iPhotoManager.bundle/iPhotoManager.icns"
)
for t in "${ICNS_TARGETS[@]}"; do
  if [ -d "$(dirname "$t")" ]; then cp "$TMP/AppIcon.icns" "$t"; echo "   → $t"; fi
done

echo "✅ Icones regenerades."
