#!/usr/bin/env bash
# Run all skill evals and print an aggregate pass rate.
# Requires: ANTHROPIC_API_KEY, jq, curl.
# Usage: bash evals/run-all.sh [--report]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT="${1:-}"

total_pass=0; total_fail=0

run_skill() {
  local skill="$1"
  local runner="$SCRIPT_DIR/$skill/run.sh"
  [ -f "$runner" ] || { echo "No runner for $skill" >&2; return; }
  echo "=== $skill ==="
  if bash "$runner"; then
    total_pass=$((total_pass + 1))
  else
    total_fail=$((total_fail + 1))
  fi
  echo ""
}

[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "ANTHROPIC_API_KEY not set" >&2; exit 1; }

run_skill semantic-commit-guard
run_skill git-bisect-ai
run_skill dependency-upgrade-loop

echo "================================"
printf 'Total skills passing: %d / %d\n' "$total_pass" "$((total_pass + total_fail))"

if [ "$REPORT" = "--report" ]; then
  echo ""
  echo "To update the pass rates in evals/README.md, edit the table under '## Current pass rates'."
fi

[ "$total_fail" -eq 0 ]
