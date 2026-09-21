#!/usr/bin/env bash
# Moves an existing library into the App Group container, where the sandboxed app
# and its extensions can both reach it.
#
# Sandboxing relocates Application Support into the app's container, so a sandboxed
# build finds no library and silently seeds a fresh one (docs/sandbox-spike.md). The
# group container is the right destination anyway: the share and action extensions
# need the same store, and the move is worth doing exactly once.
#
# Nothing is deleted. The source is left in place, plus a tar backup, until you say
# otherwise — see the last line it prints.
#
#   Scripts/relocate-library.sh [--force]
set -euo pipefail

TEAM="JV4MVRB77Q"
GROUP="$TEAM.group.com.heindewilde.summon"
BUNDLE_ID="com.heindewilde.summon"

SOURCE="$HOME/Library/Application Support/Summon"
GROUP_ROOT="$HOME/Library/Group Containers/$GROUP/Summon"
# The vault's key material and its record of wrong guesses stay device-local: never
# in the group container, so no extension can read them and nothing can sync them.
DEVICE_ROOT="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Summon"
BACKUP="$HOME/Library/Application Support/Summon-backup-$(date +%Y%m%d-%H%M%S).tar"
MARKER="$GROUP_ROOT/.relocated-from-application-support"

DEVICE_FILES=(vault.wrap vault.throttle.json)

say() { printf '==> %s\n' "$1"; }

if [[ ! -d "$SOURCE" ]]; then
  say "No library at $SOURCE — nothing to relocate."
  exit 0
fi

if [[ -f "$MARKER" && "${1:-}" != "--force" ]]; then
  say "Already relocated on $(cat "$MARKER"). Pass --force to do it again."
  exit 0
fi

if [[ -e "$GROUP_ROOT" && "${1:-}" != "--force" ]]; then
  say "$GROUP_ROOT already exists. Pass --force to overwrite it."
  exit 1
fi

say "Backing up to $BACKUP"
tar -cf "$BACKUP" -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")"
printf '    %s\n' "$(du -h "$BACKUP" | cut -f1)"

say "Copying the library to the group container"
mkdir -p "$(dirname "$GROUP_ROOT")"
rm -rf "$GROUP_ROOT"
# -c preserves everything ditto can, and unlike cp it will not follow a symlink out
# of the tree it is copying.
ditto "$SOURCE" "$GROUP_ROOT"

say "Moving the vault's device-local files out of the group container"
mkdir -p "$DEVICE_ROOT"
for file in "${DEVICE_FILES[@]}"; do
  if [[ -f "$GROUP_ROOT/$file" ]]; then
    mv "$GROUP_ROOT/$file" "$DEVICE_ROOT/$file"
    printf '    %s → %s\n' "$file" "$DEVICE_ROOT"
  fi
done

say "Verifying"
# Compare the two trees file by file, ignoring the files that moved on purpose and
# the macOS metadata ditto writes. A count is not enough: a truncated copy has the
# same names, and the store is the one file where a lost page is unrecoverable.
fail=0
while IFS= read -r -d '' file; do
  rel="${file#"$SOURCE"/}"
  case "$rel" in
    vault.wrap | vault.throttle.json | .DS_Store) continue ;;
  esac
  if [[ ! -f "$GROUP_ROOT/$rel" ]]; then
    printf '    MISSING %s\n' "$rel"
    fail=1
    continue
  fi
  a="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  b="$(shasum -a 256 "$GROUP_ROOT/$rel" | cut -d' ' -f1)"
  if [[ "$a" != "$b" ]]; then
    printf '    DIFFERS %s\n' "$rel"
    fail=1
  fi
done < <(find "$SOURCE" -type f -print0)

for file in "${DEVICE_FILES[@]}"; do
  if [[ -f "$SOURCE/$file" ]]; then
    a="$(shasum -a 256 "$SOURCE/$file" | cut -d' ' -f1)"
    b="$(shasum -a 256 "$DEVICE_ROOT/$file" 2>/dev/null | cut -d' ' -f1 || true)"
    if [[ "$a" != "$b" ]]; then
      printf '    DIFFERS %s (device-local)\n' "$file"
      fail=1
    fi
  fi
done

if [[ "$fail" -ne 0 ]]; then
  say "Verification FAILED. The original is untouched; the copy is incomplete."
  say "Restore with: tar -xf \"$BACKUP\" -C \"$HOME/Library/Application Support\""
  exit 1
fi

count=$(find "$GROUP_ROOT" -type f | wc -l | tr -d ' ')
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKER"
say "Verified — $count files match, byte for byte."
printf '\n    Library:      %s\n    Vault (local): %s\n    Backup:       %s\n\n' \
  "$GROUP_ROOT" "$DEVICE_ROOT" "$BACKUP"
say "The original is still at $SOURCE. Delete it once the app has run happily:"
printf '    rm -rf "%s"\n' "$SOURCE"
