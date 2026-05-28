#!/usr/bin/env bash
#
# bisect-run.sh — the wrapper you hand to `git bisect run`.
#
# git bisect interprets the wrapper's exit code per commit:
#   0          -> good   (test passed)
#   125        -> skip   (commit can't be tested, e.g. it won't build)
#   1..124,126 -> bad    (test failed)
#   128..255   -> abort the whole bisect
#
# This wrapper runs an optional setup/build step and then a test command,
# and translates their exit codes into the values git bisect expects, so a
# single command can drive the entire binary search unattended.
#
# Usage:
#   bisect-run.sh --test "<cmd>" [options]
#     --test "<cmd>"       Command whose exit code defines good/bad. REQUIRED.
#     --setup "<cmd>"      Run before --test (install deps, compile). Optional.
#     --timeout <seconds>  Kill --test after N seconds; a hang counts as bad.
#     --build-is-bug       A failing --setup means BAD, not skip. Use when the
#                          regression you are hunting is a broken build/compile.
#     --invert             Swap the meaning: a PASSING test is "bad". Use to find
#                          the commit that made a failing test start to pass.
#
# Everything runs through `bash -c`, so --test/--setup may be any shell snippet,
# including a headless-browser script for frontend checks.

set -u

SETUP=""
TEST=""
TIMEOUT=""
BUILD_IS_BUG=0
INVERT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --setup)        SETUP="$2"; shift 2;;
    --test)         TEST="$2"; shift 2;;
    --timeout)      TIMEOUT="$2"; shift 2;;
    --build-is-bug) BUILD_IS_BUG=1; shift;;
    --invert)       INVERT=1; shift;;
    *) echo "bisect-run: unknown argument: $1" >&2; exit 128;;
  esac
done

if [ -z "$TEST" ]; then
  echo "bisect-run: --test is required" >&2
  exit 128
fi

run_with_timeout() {
  # $1 = seconds (may be empty), $2 = command string
  local secs="$1" cmd="$2" to=""
  if [ -z "$secs" ]; then
    bash -c "$cmd"; return $?
  fi
  if command -v timeout  >/dev/null 2>&1; then to="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then to="gtimeout"
  fi
  if [ -n "$to" ]; then
    "$to" --foreground "$secs" bash -c "$cmd"; return $?
  fi
  echo "bisect-run: no timeout binary found; running without a timeout" >&2
  bash -c "$cmd"; return $?
}

commit=$(git rev-parse --short HEAD 2>/dev/null)
echo "=== bisect-run @ ${commit} ==="

# --- setup / build -----------------------------------------------------------
if [ -n "$SETUP" ]; then
  echo "--- setup: $SETUP"
  if ! bash -c "$SETUP"; then
    if [ "$BUILD_IS_BUG" -eq 1 ]; then
      verdict=1
      [ "$INVERT" -eq 1 ] && verdict=0
      echo "=== setup failed -> $([ $verdict -eq 0 ] && echo good || echo bad) (build is the bug) ==="
      exit "$verdict"
    fi
    echo "=== setup failed -> SKIP (125): cannot test this commit ==="
    exit 125
  fi
fi

# --- test --------------------------------------------------------------------
echo "--- test: $TEST"
run_with_timeout "$TIMEOUT" "$TEST"; rc=$?
echo "--- test exit code: $rc"

if [ "$INVERT" -eq 1 ]; then
  if [ "$rc" -eq 0 ]; then verdict=1; else verdict=0; fi
else
  verdict="$rc"
fi

# Collapse any nonzero (incl. 124 timeout, 125, 128) to plain "bad" so the test
# command can never accidentally trigger skip/abort in git bisect.
if [ "$verdict" -ne 0 ]; then
  verdict=1
fi

echo "=== verdict: $([ $verdict -eq 0 ] && echo good || echo bad) ($verdict) ==="
exit "$verdict"
