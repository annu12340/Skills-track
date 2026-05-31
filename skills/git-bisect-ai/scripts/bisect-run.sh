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
#     --setup-timeout <s>  Kill --setup after N seconds. Optional.
#     --log-dir <path>     Save setup/test logs per commit. Optional.
#     --build-is-bug       A failing --setup means BAD, not skip. Use when the
#                          regression you are hunting is a broken build/compile.
#     --invert             Swap the meaning: a PASSING test is "bad". Use to find
#                          the commit that made a failing test start to pass.
#     --allow-test-skip    If --test exits 125, return 125 (skip this commit).
#
# Everything runs through `bash -c`, so --test/--setup may be any shell snippet,
# including a headless-browser script for frontend checks.

set -u

SETUP=""
TEST=""
TIMEOUT=""
SETUP_TIMEOUT=""
LOG_DIR=""
BUILD_IS_BUG=0
INVERT=0
ALLOW_TEST_SKIP=0

need_val() { [ $# -ge 2 ] || { echo "bisect-run: $1 needs a value" >&2; exit 128; }; }
check_positive() {
  # $1 = value, $2 = option name
  [ -z "$1" ] && return 0
  case "$1" in
    *[!0-9]*|0)
      echo "bisect-run: $2 must be a positive integer (seconds)" >&2
      exit 128
      ;;
  esac
}

usage() {
  sed -n '2,29p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --setup)        need_val "$@"; SETUP="$2"; shift 2;;
    --test)         need_val "$@"; TEST="$2"; shift 2;;
    --timeout)      need_val "$@"; TIMEOUT="$2"; shift 2;;
    --setup-timeout) need_val "$@"; SETUP_TIMEOUT="$2"; shift 2;;
    --log-dir)      need_val "$@"; LOG_DIR="$2"; shift 2;;
    --build-is-bug) BUILD_IS_BUG=1; shift;;
    --invert)       INVERT=1; shift;;
    --allow-test-skip) ALLOW_TEST_SKIP=1; shift;;
    -h|--help)      usage; exit 0;;
    *) echo "bisect-run: unknown argument: $1" >&2; exit 128;;
  esac
done

[ -n "$TEST" ] || { echo "bisect-run: --test is required" >&2; exit 128; }
check_positive "$TIMEOUT" "--timeout"
check_positive "$SETUP_TIMEOUT" "--setup-timeout"

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

run_logged() {
  # $1 = label, $2 = seconds, $3 = command string, $4 = optional log path
  local label="$1" secs="$2" cmd="$3" log_file="$4" rc=0
  echo "--- $label: $cmd"
  if [ -n "$log_file" ]; then
    mkdir -p "$(dirname "$log_file")"
    run_with_timeout "$secs" "$cmd" >"$log_file" 2>&1
    rc=$?
    cat "$log_file"
    echo "--- $label log: $log_file"
    return "$rc"
  fi
  run_with_timeout "$secs" "$cmd"; return $?
}

commit=$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')
echo "=== bisect-run @ ${commit} ==="
setup_log=""
test_log=""
summary_file=""
setup_exit=""
test_exit=""
if [ -n "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR"
  setup_log="${LOG_DIR}/${commit}-setup.log"
  test_log="${LOG_DIR}/${commit}-test.log"
  summary_file="${LOG_DIR}/${commit}-summary.json"
fi

write_summary() {
  # $1 = verdict label
  [ -n "$summary_file" ] || return 0
  {
    printf '{\n'
    printf '  "commit": "%s",\n' "$commit"
    printf '  "setup_exit": "%s",\n' "$setup_exit"
    printf '  "test_exit": "%s",\n' "$test_exit"
    printf '  "verdict": "%s",\n' "$1"
    printf '  "setup_log": "%s",\n' "$setup_log"
    printf '  "test_log": "%s"\n' "$test_log"
    printf '}\n'
  } > "$summary_file"
  echo "--- summary: $summary_file"
}

# --- setup / build -----------------------------------------------------------
if [ -n "$SETUP" ]; then
  run_logged "setup" "$SETUP_TIMEOUT" "$SETUP" "$setup_log"; setup_exit=$?
  if [ "$setup_exit" -ne 0 ]; then
    if [ "$BUILD_IS_BUG" -eq 1 ]; then
      verdict=1
      [ "$INVERT" -eq 1 ] && verdict=0
      write_summary "$([ $verdict -eq 0 ] && echo good || echo bad)"
      echo "=== setup failed -> $([ $verdict -eq 0 ] && echo good || echo bad) (build is the bug) ==="
      exit "$verdict"
    fi
    write_summary "skip"
    echo "=== setup failed -> SKIP (125): cannot test this commit ==="
    exit 125
  fi
fi

# --- test --------------------------------------------------------------------
run_logged "test" "$TIMEOUT" "$TEST" "$test_log"; test_exit=$?
echo "--- test exit code: $test_exit"

if [ "$ALLOW_TEST_SKIP" -eq 1 ] && [ "$test_exit" -eq 125 ]; then
  write_summary "skip"
  echo "=== test returned 125 -> SKIP ==="
  exit 125
fi

if [ "$test_exit" -eq 124 ]; then
  verdict=1
elif [ "$INVERT" -eq 1 ]; then
  if [ "$test_exit" -eq 0 ]; then verdict=1; else verdict=0; fi
else
  verdict="$test_exit"
fi

# Collapse any nonzero (incl. 124 timeout, 125, 128) to plain "bad" so the test
# command can never accidentally trigger skip/abort in git bisect.
if [ "$verdict" -ne 0 ]; then
  verdict=1
fi

write_summary "$([ "$verdict" -eq 0 ] && echo good || echo bad)"

echo "=== verdict: $([ $verdict -eq 0 ] && echo good || echo bad) ($verdict) ==="
exit "$verdict"
