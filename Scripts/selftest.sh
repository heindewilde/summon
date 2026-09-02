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

DEMO="$HOME/Library/Application Support/Summon-Demo"

if [[ "${1:-}" != "--keep" ]]; then
  echo "==> Resetting demo library"
  rm -rf "$DEMO"
fi

if [[ ! -x dist/Summon.app/Contents/MacOS/Summon ]]; then
  echo "==> Building"
  Scripts/build-app.sh >/dev/null
fi

SUMMON_DEMO=1 SUMMON_SELFTEST=1 ./dist/Summon.app/Contents/MacOS/Summon
