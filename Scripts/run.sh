#!/bin/bash
# Build, then relaunch Summon. Pass --demo to run against a throwaway library.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/build-app.sh" "${CONFIG:-debug}"
pkill -x Summon 2>/dev/null || true
sleep 0.4
if [[ "${1:-}" == "--demo" ]]; then
  SUMMON_DEMO=1 open -n "$ROOT/dist/Summon.app"
else
  open "$ROOT/dist/Summon.app"
fi
