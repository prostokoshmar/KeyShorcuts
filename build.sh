#!/usr/bin/env bash
set -euo pipefail

APP_NAME="KeyShortcuts"
DISPLAY_NAME="Key Shortcuts"
BUNDLE_ID="com.keyshortcuts.app"
# Read version from VERSION file, fall back to env var, then 1.0.0
VERSION="${VERSION:-}"
if [ -f "VERSION" ]; then
    VERSION=$(cat VERSION | tr -d '[:space:]')
fi
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="$(pwd)/.build"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building ${DISPLAY_NAME} v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Icon ────────────────────────────────
echo "→ Generating app icon..."
swift make_icon.swift
iconutil -c icns KeyShortcuts.iconset -o AppIcon.icns
rm -rf KeyShortcuts.iconset
echo "✅ AppIcon.icns"

# ── Swift build ─────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    SWIFT_ARCH="arm64-apple-macosx"
else
    SWIFT_ARCH="x86_64-apple-macosx"
fi

echo "→ Building Swift package (Release)..."
swift build -c release 2>&1 | tail -5

EXECUTABLE="${BUILD_DIR}/${SWIFT_ARCH}/release/${APP_NAME}"
if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Build failed: executable not found at $EXECUTABLE"
    exit 1
fi

# ── App bundle ──────────────────────────
echo "→ Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE"  "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp AppIcon.icns   "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Key Shortcuts needs Accessibility access to read keyboard shortcuts from other applications.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Use a stable local certificate if available (run setup_cert.sh once to create it).
# A stable identity means macOS keeps Accessibility/Input Monitoring grants between builds.
LOCAL_CERT="KeyShortcuts Local"
if security find-certificate -c "$LOCAL_CERT" ~/Library/Keychains/login.keychain-db &>/dev/null; then
    echo "→ Code signing (local cert: $LOCAL_CERT)..."
    codesign --force --deep --sign "$LOCAL_CERT" "$APP_BUNDLE" 2>/dev/null || \
        codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
else
    echo "→ Code signing (ad-hoc — run ./setup_cert.sh once to stop privacy re-prompts)..."
    codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
fi
echo "✅ App bundle: ${APP_BUNDLE}"

# ── DMG ─────────────────────────────────
echo "→ Creating DMG..."
STAGING="dmg_staging_tmp"
rm -rf "$STAGING" "$DMG_NAME"
mkdir -p "$STAGING"
cp -r "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "${DISPLAY_NAME}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_NAME" > /dev/null

rm -rf "$STAGING"

echo "✅ DMG: ${DMG_NAME}"

# ── ZIP for auto-update ──────────────────
echo "→ Creating ZIP for auto-update..."
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"
echo "✅ ZIP: ${ZIP_NAME}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done!"
echo ""
echo "  To install:"
echo "  1. open ${DMG_NAME}"
echo "  2. Drag Key Shortcuts → Applications"
echo "  3. Launch → grant Accessibility access"
echo "  4. Hold ⌘ for 0.5s to see shortcuts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
