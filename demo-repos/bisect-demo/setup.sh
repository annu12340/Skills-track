#!/usr/bin/env bash
# Materializes a throwaway git repo with a regression planted mid-history,
# so you can demo the git-bisect-ai skill. Re-run to reset.
set -euo pipefail
cd "$(dirname "$0")"

# --- reset any previous run -------------------------------------------------
rm -rf .git mathlib tests README.md

git init -q
git config user.name  "Demo Author"
git config user.email "demo@example.com"
git config commit.gpgsign false

mkdir -p mathlib tests
: > mathlib/__init__.py

# commit <date> <message>; stages everything and commits with a fixed date
commit() {
  local date="$1"; shift
  git add -A
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git commit -q -m "$*"
}

# --- 1: initial calc with add/subtract -------------------------------------
cat > mathlib/calc.py <<'PY'
def add(a, b):
    return a + b


def subtract(a, b):
    return a - b
PY
commit "2026-05-18T09:00:00" "Initial mathlib: add, subtract"

# --- 2: add multiply (CORRECT) + a test ------------------------------------
cat >> mathlib/calc.py <<'PY'


def multiply(a, b):
    return a * b
PY
cat > tests/test_calc.py <<'PY'
from mathlib.calc import add, multiply


def test_add():
    assert add(2, 3) == 5


def test_multiply():
    assert multiply(4, 5) == 20
PY
commit "2026-05-20T11:30:00" "Add multiply() and tests"

# --- 3: add divide ---------------------------------------------------------
cat >> mathlib/calc.py <<'PY'


def divide(a, b):
    return a / b
PY
commit "2026-05-22T14:15:00" "Add divide()"

# --- 4: add power, tag v1.0 (last known-good) ------------------------------
cat >> mathlib/calc.py <<'PY'


def power(a, b):
    return a ** b
PY
commit "2026-05-26T10:00:00" "Add power(); cut v1.0 release"
git tag v1.0

# --- 5: THE REGRESSION — "optimize" multiply, drops the * for a + ----------
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("mathlib/calc.py")
src = p.read_text()
src = src.replace("def multiply(a, b):\n    return a * b",
                  "def multiply(a, b):\n    return a + b")
p.write_text(src)
PY
commit "2026-05-27T16:45:00" "Optimize multiply for readability"

# --- 6: add modulo (innocent, after the bug) -------------------------------
cat >> mathlib/calc.py <<'PY'


def modulo(a, b):
    return a % b
PY
commit "2026-05-28T09:20:00" "Add modulo()"

# --- 7: docs ---------------------------------------------------------------
cat > README.md <<'MD'
# mathlib

A tiny arithmetic library: `add`, `subtract`, `multiply`, `divide`, `power`,
`modulo`, `average`.
MD
commit "2026-05-28T13:00:00" "Add README"

# --- 8: add average (HEAD, still has the multiply bug) ----------------------
cat >> mathlib/calc.py <<'PY'


def average(values):
    return sum(values) / len(values)
PY
commit "2026-05-29T15:10:00" "Add average()"

cat <<'EOF'

==================================================================
  bisect-demo ready.
==================================================================
The bug:  multiply(4, 5) should be 20 but returns 9 — a commit
          "optimized" `a * b` into `a + b`.

  good (works): v1.0          bad (broken): HEAD

Reproduction (no deps; exit 0 = good, nonzero = bug present):
  python3 -c "from mathlib.calc import multiply; import sys; \
sys.exit(0 if multiply(4,5)==20 else 1)"

Ask the agent:
  "multiply broke since the v1.0 release — bisect and find the commit."

It should land on "Optimize multiply for readability" and explain the
* -> + change.

Drive it yourself:
  git bisect start HEAD v1.0
  git bisect run bash -c 'python3 -c "from mathlib.calc import multiply; \
import sys; sys.exit(0 if multiply(4,5)==20 else 1)"'
  git bisect reset

Reset this demo:  bash setup.sh
==================================================================
EOF
