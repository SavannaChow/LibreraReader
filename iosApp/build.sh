#!/bin/bash

set -e

APP_NAME="iosApp"
PROJECT_NAME="iosApp"
BUILD_DIR="build"
DIST_DIR="dist"
SCHEME="${SCHEME:-$APP_NAME}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"
EXPORT_DIR="${EXPORT_DIR:-$PWD}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_DIR}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

# Extract version from project.pbxproj
VERSION=$(grep -m 1 "MARKETING_VERSION" "$PROJECT_NAME.xcodeproj/project.pbxproj" | cut -d'=' -f2 | tr -d ' ;')
DMG_NAME="$APP_NAME v$VERSION.dmg"

echo "🚀 Starting build process for $APP_NAME..."
echo "   Scheme: $SCHEME"
echo "   Configuration: $CONFIGURATION"
echo "   Destination: $DESTINATION"
echo "   Export directory: $EXPORT_DIR"

# 1. Clean up previous builds
echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR"
rm -rf "$DIST_DIR"
rm -f "$DMG_NAME"
mkdir -p "$EXPORT_DIR"

# 2. Build the app
echo "🏗️ Building $APP_NAME (Release)..."
xcodebuild -project "$PROJECT_NAME.xcodeproj" \
           -scheme "$SCHEME" \
           -configuration "$CONFIGURATION" \
           -destination "$DESTINATION" \
           -derivedDataPath "$DERIVED_DATA_PATH" \
           CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
           build

# 3. Prepare DMG content
echo "📦 Preparing DMG content..."
mkdir -p "$DIST_DIR/dmg_content"

# Find the .app bundle
APP_BUNDLE=$(find "$DERIVED_DATA_PATH" -name "Librera5.app" -type d | head -n 1)

if [ -z "$APP_BUNDLE" ]; then
    echo "❌ Error: Could not find $APP_NAME.app bundle."
    exit 1
fi

cp -R "$APP_BUNDLE" "$DIST_DIR/dmg_content/"
ln -s /Applications "$DIST_DIR/dmg_content/Applications"

# 4. Create DMG
echo "💿 Creating $DMG_NAME..."
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$DIST_DIR/dmg_content" \
               -ov -format UDZO \
               "$DMG_NAME"

# 5. Cleanup
echo "🧹 Final cleanup..."
rm -rf "$BUILD_DIR"
rm -rf "$DIST_DIR"

if [ "$EXPORT_DIR" != "$PWD" ]; then
    mv "$DMG_NAME" "$EXPORT_DIR/"
fi

echo "✅ Done! $DMG_NAME is ready in $EXPORT_DIR"
