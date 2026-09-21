#!/usr/bin/env bash
# Archives both apps, uploads them to App Store Connect, and promotes the CloudKit
# schema to production.
#
#   Scripts/ship.sh archive          # build both archives (no credentials needed)
#   Scripts/ship.sh upload           # export and upload both (needs an API key)
#   Scripts/ship.sh promote-schema   # development schema → production (needs a token)
#
# Credentials, neither of which is read or printed here:
#
#   App Store Connect API key — the .p8 in ~/.appstoreconnect/private_keys/, with
#   SUMMON_ASC_KEY_ID and SUMMON_ASC_ISSUER_ID set. Create one at
#   appstoreconnect.apple.com → Users and Access → Integrations.
#
#   CloudKit management token — saved once with `xcrun cktool save-token --type
#   management`, which puts it in the keychain. Create one at
#   icloud.developer.apple.com → the container → Settings → Tokens.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEAM="JV4MVRB77Q"
CONTAINER="iCloud.com.heindewilde.summon"
BUILD_DIR="$ROOT/.build/ship"
KEY_DIR="$HOME/.appstoreconnect/private_keys"

say() { printf '==> %s\n' "$1"; }

archive() {
  mkdir -p "$BUILD_DIR"
  for scheme in SummonMac SummonPhone; do
    local destination
    destination=$([ "$scheme" = "SummonMac" ] && echo 'generic/platform=macOS' || echo 'generic/platform=iOS')
    say "Archiving $scheme"
    xcodebuild -project Summon.xcodeproj -scheme "$scheme" \
      -destination "$destination" \
      -archivePath "$BUILD_DIR/$scheme.xcarchive" \
      -allowProvisioningUpdates archive | tail -3
  done
}

# The archives are signed for development while they sit on disk; the distribution
# profile is applied here, at export, which is also where `production` push takes
# effect. See Apps/*/*-Release.entitlements.
upload() {
  local key_id="${SUMMON_ASC_KEY_ID:-}" issuer="${SUMMON_ASC_ISSUER_ID:-}"
  if [[ -z "$key_id" || -z "$issuer" ]]; then
    echo "Set SUMMON_ASC_KEY_ID and SUMMON_ASC_ISSUER_ID first." >&2
    echo "The key itself belongs in $KEY_DIR/AuthKey_<KEY_ID>.p8" >&2
    exit 1
  fi
  local key_path="$KEY_DIR/AuthKey_$key_id.p8"
  if [[ ! -f "$key_path" ]]; then
    echo "No key at $key_path — Apple only lets you download it once, so check Downloads." >&2
    exit 1
  fi

  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$TEAM</string>
    <key>destination</key><string>upload</string>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

  for scheme in SummonMac SummonPhone; do
    [[ -d "$BUILD_DIR/$scheme.xcarchive" ]] || { echo "No archive for $scheme — run 'archive' first." >&2; exit 1; }
    say "Uploading $scheme"
    xcodebuild -exportArchive \
      -archivePath "$BUILD_DIR/$scheme.xcarchive" \
      -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
      -exportPath "$BUILD_DIR/export-$scheme" \
      -allowProvisioningUpdates \
      -authenticationKeyPath "$key_path" \
      -authenticationKeyID "$key_id" \
      -authenticationKeyIssuerID "$issuer" | tail -5
  done
  say "Uploaded. Processing takes a few minutes before the build appears in TestFlight."
}

# One way: production accepts additions, never removals or renames. Everything about
# the model should be settled before this runs.
promote_schema() {
  mkdir -p "$BUILD_DIR"
  local schema="$BUILD_DIR/schema.ckdb"
  say "Exporting the development schema"
  xcrun cktool export-schema --team-id "$TEAM" --container-id "$CONTAINER" \
    --environment development --output-file "$schema"
  say "Validating it against production"
  xcrun cktool validate-schema --team-id "$TEAM" --container-id "$CONTAINER" \
    --environment production --file "$schema"
  printf '\n    This is one way: production accepts additions, never removals.\n'
  printf '    Continue? [y/N] '
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { say "Left alone."; return; }
  xcrun cktool import-schema --team-id "$TEAM" --container-id "$CONTAINER" \
    --environment production --file "$schema"
  say "Production now matches development."
}

case "${1:-}" in
  archive) archive ;;
  upload) upload ;;
  promote-schema) promote_schema ;;
  *) sed -n '2,20p' "$0" >&2; exit 1 ;;
esac
