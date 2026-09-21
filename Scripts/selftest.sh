#!/usr/bin/env bash
# Runs the runtime self-test against a guaranteed-fresh demo library.
#
# The self-test configures a vault, marks items sensitive and edits snippets. Left in
# place, that state makes the *next* run report failures that are really leftovers —
# so the reset happens here, outside the process. It cannot be done inside the app:
# the SwiftData container is opened when the App struct initialises, which is before
# applicationDidFinishLaunching runs.
set -euo pipefail
cd "$(dirname "$0")/.."

# The demo library follows the real one into the App Group container.
GROUP="JV4MVRB77Q.group.com.heindewilde.summon"
DEMO="$HOME/Library/Group Containers/$GROUP/Summon-Demo"
# The vault's device-local files sit outside the group container — and for the
# sandboxed build, "outside" means inside the app's own container.
DEMO_DEVICE="$HOME/Library/Application Support/Summon-Demo"
DEMO_SANDBOXED="$HOME/Library/Containers/com.heindewilde.summon/Data/Library/Application Support/Summon-Demo"

if [[ "${1:-}" != "--keep" ]]; then
  echo "==> Resetting demo library"
  rm -rf "$DEMO" "$DEMO_DEVICE" "$DEMO_SANDBOXED"
fi

# Always rebuild. Building only when the binary is missing means editing a source
# file and re-running this silently tests the previous build — which cost me a
# confusing "the code is right but the check never ran" hunt. build-app.sh is
# incremental, so this is cheap.
echo "==> Building"
Scripts/build-app.sh >/dev/null

SUMMON_DEMO=1 SUMMON_SELFTEST=1 ./dist/Summon.app/Contents/MacOS/Summon
