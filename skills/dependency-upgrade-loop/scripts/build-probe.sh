#!/usr/bin/env bash
#
# build-probe.sh — run a project's build/verify command, capture the full log,
# and surface the part that matters: the FIRST root error.
#
# The upgrade loop calls this after each dependency bump. It gives the agent a
# clean exit code plus a saved, tailable log so it can read the earliest failure
# instead of scrolling a wall of cascade errors.
#
# Usage:
#   build-probe.sh --cmd "<build/verify command>" [options]
#     --cmd "<cmd>"        Build/test/typecheck command. REQUIRED. Exit 0 = healthy.
#     --log <path>         Where to write the full output. Default: $TMPDIR/build-probe.log
#     --timeout <seconds>  Kill the command after N seconds (a hang counts as failure).
#     --grep "<regex>"     Extra regex of error lines to highlight (case-insensitive),
#                          on top of the built-in error patterns.
#     --summary-lines <n>  Number of matching error lines to print. Default: 15.
#     --quiet-pass         On success, save output to --log without echoing it.
#
# Exit codes:
#   0   build/verify succeeded
#   1   build/verify failed (see the highlighted root error + log path)
#   124 timed out
#   2   usage error

set -u

CMD=""
LOG="${TMPDIR:-/tmp}/build-probe.log"
TIMEOUT=""
EXTRA_GREP=""
SUMMARY_LINES=15
QUIET_PASS=0
TIMEOUT_UNAVAILABLE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --cmd)     [ $# -ge 2 ] || { echo "build-probe: --cmd needs a value" >&2; exit 2; }; CMD="$2"; shift 2;;
    --log)     [ $# -ge 2 ] || { echo "build-probe: --log needs a value" >&2; exit 2; }; LOG="$2"; shift 2;;
    --timeout) [ $# -ge 2 ] || { echo "build-probe: --timeout needs a value" >&2; exit 2; }; TIMEOUT="$2"; shift 2;;
    --grep)    [ $# -ge 2 ] || { echo "build-probe: --grep needs a value" >&2; exit 2; }; EXTRA_GREP="$2"; shift 2;;
    --summary-lines) [ $# -ge 2 ] || { echo "build-probe: --summary-lines needs a value" >&2; exit 2; }; SUMMARY_LINES="$2"; shift 2;;
    --quiet-pass) QUIET_PASS=1; shift;;
    -h|--help) sed -n '2,24p' "$0"; exit 0;;
    *) echo "build-probe: unknown argument: $1" >&2; exit 2;;
  esac
done

[ -n "$CMD" ] || { echo "build-probe: --cmd is required" >&2; exit 2; }
case "$TIMEOUT" in
  ""|*[!0-9]*|0) [ -z "$TIMEOUT" ] || { echo "build-probe: --timeout must be a positive integer" >&2; exit 2; };;
esac
case "$SUMMARY_LINES" in
  *[!0-9]*|0) echo "build-probe: --summary-lines must be a positive integer" >&2; exit 2;;
esac

mkdir -p "$(dirname "$LOG")"

run() {
  if [ -z "$TIMEOUT" ]; then
    bash -c "$CMD"; return $?
  fi
  local to=""
  if command -v timeout  >/dev/null 2>&1; then to="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then to="gtimeout"
  fi
  if [ -n "$to" ]; then
    "$to" --foreground "$TIMEOUT" bash -c "$CMD"; return $?
  fi
  TIMEOUT_UNAVAILABLE=1
  echo "build-probe: no timeout binary found (brew install coreutils); running untimed" >&2
  bash -c "$CMD"; return $?
}

if [ "$QUIET_PASS" -eq 1 ]; then
  echo "=== build-probe: $CMD ===" > "$LOG"
  run >> "$LOG" 2>&1
  rc=$?
else
  echo "=== build-probe: $CMD ===" | tee "$LOG"
  run 2>&1 | tee -a "$LOG"
  rc=${PIPESTATUS[0]}
fi

if [ "$rc" -eq 0 ]; then
  if [ "$QUIET_PASS" -eq 1 ]; then
    echo "=== build-probe: PASS (exit 0) — full log: $LOG ==="
  else
    echo "=== build-probe: PASS (exit 0) ==="
  fi
  exit 0
fi

if [ "$rc" -eq 124 ]; then
  echo "=== build-probe: TIMEOUT after ${TIMEOUT}s — full log: $LOG ===" >&2
  exit 124
fi

# Failure: pull out the first lines that look like a root error so the caller
# can fix the cause, not a downstream cascade.
ERR_RE='error|cannot find|not found|no module named|undefined|unresolved|incompatible|conflict|cannot resolve|peer dep|deprecated|removed|ModuleNotFound|TypeError|ImportError|failed'
[ -n "$EXTRA_GREP" ] && ERR_RE="$ERR_RE|$EXTRA_GREP"

echo "" >&2
echo "=== build-probe: FAIL (exit $rc) — full log: $LOG ===" >&2
if [ "$TIMEOUT_UNAVAILABLE" -eq 1 ]; then
  echo "build-probe: timeout was requested but unavailable; command ran untimed" >&2
fi
echo "--- first matching error lines (root cause is usually here) ---" >&2
grep -nEi -e "$ERR_RE" "$LOG" | grep -v ':=== build-probe:' | head -"$SUMMARY_LINES" >&2 \
  || echo "(no recognized error pattern; read $LOG)" >&2
exit 1
