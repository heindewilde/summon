#!/bin/bash
# The wall-clock performance budgets, in a pass of their own.
#
# They are skipped by `swift test` on purpose, for the same reason they are skipped on
# CI: you cannot time code on a machine that is doing something else. Two things make
# a full `swift test` the wrong place for them —
#
#   * Swift Testing runs tests in parallel in-process, so a budget competes with the
#     rest of the suite, including the 14-second Vision extraction.
#   * Whatever else is running on the machine competes too, and that dominates.
#
# Asserting on the minimum does not rescue either case. That estimator assumes some
# sample lands in a quiet slot; under sustained load none does, so the floor itself
# moves. The index build reads 13.5ms on an idle machine and 37ms at load 24 — the
# measurement is not noisy, it is measuring the wrong machine.
#
# So this script refuses to report rather than reporting something untrue. That is the
# same call `Harness.refuseIfPointedAtARealLibrary()` makes: a check that quietly
# produces a wrong answer is worse than one that declines.
#
# Release, because the numeric loops run 5-20x slower unoptimised and a budget
# calibrated for debug asserts nothing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

CORES=$(sysctl -n hw.ncpu)
LOAD=$(sysctl -n vm.loadavg | awk '{print $2}')
# Half the core count. Benchmarking wants meaningful spare capacity, not merely a
# machine that is not thrashing.
LIMIT=$(awk -v c="$CORES" 'BEGIN { printf "%.1f", c / 2 }')

if [[ $FORCE -eq 0 ]] && awk -v l="$LOAD" -v m="$LIMIT" 'BEGIN { exit !(l > m) }'; then
  echo "==> Refusing to measure: load average ${LOAD} on ${CORES} cores (limit ${LIMIT})."
  echo
  echo "    Wall-clock budgets on a loaded machine measure the scheduler. The busiest"
  echo "    processes right now:"
  ps -Ao %cpu,comm -r | sed -n '2,4p' | awk '{ printf "      %6s%%  %s\n", $1, $2 }'
  echo
  echo "    Quieten the machine and re-run, or ./Scripts/perf.sh --force to measure anyway."
  exit 1
fi

echo "==> Performance budgets (isolated, release) — load ${LOAD} on ${CORES} cores"
SUMMON_PERF_ISOLATED=1 swift test -c release --filter PerfBudgetTests
