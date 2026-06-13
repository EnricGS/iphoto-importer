#!/bin/bash
# Build release, copy to .app bundle, and re-sign with entitlements
set -e

cd "$(dirname "$0")"

BUILD_DIR=.build/arm64-apple-macosx/debug
APP_DIR=iPhotoManager.app/Contents

echo "⚙️  Building (debug)..."
swift build

echo "📦 Copying binary and resources to .app bundle..."
cp "$BUILD_DIR/iPhotoManager" "$APP_DIR/MacOS/iPhotoManager"
cp -R "$BUILD_DIR/iPhotoManager_iPhotoManager.bundle" "$APP_DIR/Resources/"

echo "🔏 Re-signing with entitlements..."
# Cert de MassiuSoft SL (team YQYXYXUDWA). És un "Apple Development" → val per
# executar localment. Per distribuir a altres Macs caldria un "Developer ID
# Application: MassiuSoft SL" (notarització), que avui no està instal·lat.
codesign --force --sign "Apple Development: Enric Garcia Sirera (W3W5SLCY8K)" --entitlements "$APP_DIR/Resources/iPhotoManager.entitlements" iPhotoManager.app

echo "✅ Done! Open iPhotoManager.app"
