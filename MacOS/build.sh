#!/bin/bash
# Build release, copy to .app bundle, and re-sign with entitlements
set -e

cd "$(dirname "$0")"

BUILD_DIR=.build/arm64-apple-macosx/release
APP_DIR=iPhotoManager.app/Contents

echo "⚙️  Building (release)..."
swift build -c release

echo "📦 Copying binary and resources to .app bundle..."
cp "$BUILD_DIR/iPhotoManager" "$APP_DIR/MacOS/iPhotoManager"
cp -R "$BUILD_DIR/iPhotoManager_iPhotoManager.bundle" "$APP_DIR/Resources/"

echo "🔏 Re-signing with entitlements..."
codesign --force --sign "Developer ID Application" --entitlements "$APP_DIR/Resources/iPhotoManager.entitlements" iPhotoManager.app

echo "✅ Done! Open iPhotoManager.app"
