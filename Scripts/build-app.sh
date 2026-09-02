#!/bin/bash
# Assembles a real, launchable Summon.app from the SwiftPM build.
# Usage: Scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Stable output path: the TCC (Accessibility) grant is keyed to the bundle path
# plus code signature, so keeping this constant avoids re-granting on every build.
DIST="$ROOT/dist"
APP="$DIST/Summon.app"
CONTENTS="$APP/Contents"
BUNDLE_ID="com.heindewilde.summon"
VERSION="1.0"
BUILD="1"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Summon" "$CONTENTS/MacOS/Summon"

# SwiftPM resource bundles (if any target gains resources later).
for b in "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$CONTENTS/Resources/" || true
done

echo "==> Icon"
ICONSET="$ROOT/.build/Summon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

echo "==> Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Summon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Summon</string>
    <key>CFBundleDisplayName</key><string>Summon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>Summon</string>

    <key>NSAppleEventsUsageDescription</key>
    <string>Summon reads the current Finder selection so you can save files with a single keystroke.</string>

    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict><key>default</key><string>Add to Summon</string></dict>
            <key>NSMessage</key><string>addToSummon</string>
            <key>NSPortName</key><string>Summon</string>
            <key>NSSendTypes</key>
            <array>
                <string>public.utf8-plain-text</string>
                <string>public.rtf</string>
                <string>public.file-url</string>
                <string>public.png</string>
                <string>public.tiff</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

cat > "$DIST/Summon.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><false/>
    <key>com.apple.security.automation.apple-events</key><true/>
    <!-- No keychain-access-groups: without an Apple Team ID prefix the kernel
         rejects the entitlement outright and the app will not launch. That is why
         Touch ID unlock needs a Developer ID; see Vault.biometricStorageAvailable. -->
</dict>
</plist>
ENT

printf 'APPL????' > "$CONTENTS/PkgInfo"

# A stable signing identity matters more than it sounds: TCC grants (Accessibility)
# are bound to the code signature, and an ad-hoc signature is a hash of the binary,
# so every rebuild looks like a new app and silently loses the permission. Signing
# with a certificate keeps the grant across rebuilds.
# Create one with Scripts/create-signing-identity.sh.
SIGN_IDENTITY="${SUMMON_SIGN_IDENTITY:-Summon Local Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  echo "==> Signing as '$SIGN_IDENTITY'"
  codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements "$DIST/Summon.entitlements" \
    --identifier "$BUNDLE_ID" \
    "$APP"
else
  echo "==> Signing (ad-hoc — Accessibility will need re-granting after each build)"
  echo "    Run Scripts/create-signing-identity.sh once to avoid that."
  codesign --force --deep --sign - \
    --entitlements "$DIST/Summon.entitlements" \
    --identifier "$BUNDLE_ID" \
    "$APP"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

# Nudge Launch Services so the new bundle is registered.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1 || true

echo "==> Built $APP"
