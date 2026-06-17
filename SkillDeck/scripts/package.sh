#!/bin/bash
# Builds SkillDeck.app and a distributable SkillDeck.dmg (unsigned).
#
# Usage:  ./scripts/package.sh
# Output: build/SkillDeck.app  and  build/SkillDeck.dmg
#
# NOTE: This produces an UNSIGNED app. Recipients must right-click → Open the
# first time to get past Gatekeeper (see README). Code signing + notarization
# (for a frictionless install) requires an Apple Developer account.

set -euo pipefail

# --- config -----------------------------------------------------------------
APP_NAME="SkillDeck"
EXECUTABLE="SkillDeckApp"           # SwiftPM product name
BUNDLE_ID="com.skilldeck.app"
VERSION="1.0.0"  # Keep in sync with UpdateChecker.fallbackVersion
MIN_MACOS="15.0"

# --- paths ------------------------------------------------------------------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Building release binary…"
cd "$ROOT"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# Copy the executable, named after the app.
cp "$BIN_PATH/$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

# (No SwiftPM resource bundle to copy — built-in commands are inlined in source,
# which avoids a Bundle.module lookup that crashes in a packaged .app.)

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSHumanReadableCopyright</key> <string>MIT License</string>
</dict>
</plist>
PLIST

# Optional icon: if Resources/AppIcon.icns exists in the repo, bundle it.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || true
fi

# Ad-hoc sign so the app at least has a stable code signature locally (helps
# Accessibility permission persist across launches on the build machine).
codesign --force --deep --sign - "$APP" 2>/dev/null \
  && echo "==> Ad-hoc signed." \
  || echo "==> (codesign skipped/failed; app is unsigned)"

echo "==> Built: $APP"

# --- DMG --------------------------------------------------------------------
echo "==> Creating $APP_NAME.dmg…"
DMG="$BUILD_DIR/$APP_NAME.dmg"
rm -f "$DMG"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install convenience

hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGING"
echo "==> Built: $DMG"
echo ""
echo "Done. Distribute build/$APP_NAME.dmg."
echo "Recipients: open the .dmg, drag $APP_NAME to Applications, then right-click"
echo "the app → Open the first time (unsigned app; Gatekeeper requires this)."
