#!/bin/bash
# Regenerates the app icons in Apps/Shared/Assets.xcassets from Scripts/make-icon.swift.
# The Xcode targets need the PNGs checked in; build-app.sh still draws its own at
# build time. Run after changing the icon.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SET="$ROOT/Apps/Shared/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
swift "$ROOT/Scripts/make-icon.swift" "$SET" >/dev/null
rm -f "$SET/../summon-icon-1024.png"
swift "$ROOT/Scripts/make-icon.swift" --ios "$SET/icon_ios_1024.png" >/dev/null
swift "$ROOT/Scripts/make-icon.swift" --ios "$SET/icon_ios_1024_dark.png" --variant dark >/dev/null
swift "$ROOT/Scripts/make-icon.swift" --ios "$SET/icon_ios_1024_tinted.png" --variant tinted >/dev/null
echo "Icons written to $SET"
