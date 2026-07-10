#!/bin/bash
# Build release + signa amb Developer ID (hardened runtime) + notaritza + estapa + empaqueta.
# Requisits (fets un sol cop):
#   1) Certificat "Developer ID Application: MassiuSoft SL (YQYXYXUDWA)" instal·lat a la keychain.
#   2) Perfil de credencials notarytool guardat:  xcrun notarytool store-credentials "massiusoft" ...
set -e

cd "$(dirname "$0")"

SIGN_ID="Developer ID Application"          # coincidència parcial; agafa el de MassiuSoft
NOTARY_PROFILE="massiusoft"
BUILD_DIR=.build/arm64-apple-macosx/release
APP=iPhotoManager.app
APP_DIR="$APP/Contents"
ENTITLEMENTS="$APP_DIR/Resources/iPhotoManager.entitlements"
OUT="$HOME/Desktop/iPhotoManager-mac.zip"

echo "⚙️  Building (release)..."
swift build -c release

echo "📦 Copiant binari i recursos al bundle..."
cp "$BUILD_DIR/iPhotoManager" "$APP_DIR/MacOS/iPhotoManager"
rm -rf "$APP_DIR/Resources/iPhotoManager_iPhotoManager.bundle"
cp -R "$BUILD_DIR/iPhotoManager_iPhotoManager.bundle" "$APP_DIR/Resources/"

echo "🔏 Signant amb Developer ID + hardened runtime..."
codesign --force --options runtime --timestamp \
  --sign "$SIGN_ID" --entitlements "$ENTITLEMENTS" "$APP"
codesign -v --deep --strict "$APP" && echo "   signatura OK"

echo "🗜️  Empaquetant per notaritzar..."
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

echo "🍏 Notaritzant (pot trigar 1-5 min)..."
xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait

echo "📎 Estapant el tiquet a l'app..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP" && echo "   staple OK"

echo "🗜️  Re-empaquetant l'app ja notaritzada..."
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

echo "✅ Fet! $OUT — obre a qualsevol Mac sense treure quarantena."
