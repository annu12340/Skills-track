#!/usr/bin/env bash
# Materializes a repo with a CLEAN committed baseline and a STAGED diff that
# the semantic-commit-guard skill should block. Re-run to reset.
set -euo pipefail
cd "$(dirname "$0")"

# --- reset any previous run -------------------------------------------------
rm -rf .git app README.md .semantic-guard.md

git init -q
git config user.name  "Demo Author"
git config user.email "demo@example.com"
git config commit.gpgsign false
mkdir -p app

# ===========================================================================
# CLEAN BASELINE (committed) — nothing wrong here yet.
# ===========================================================================
cat > .semantic-guard.md <<'MD'
# Project policy (read by the semantic commit guard)

## Architecture
- `app/handlers.py` is the thin HTTP layer. It must NOT contain business logic,
  raw SQL, or direct DB access. It delegates to `app/service.py`.
- Only `app/service.py` may talk to the database.

## Secrets
- No credentials, API keys, tokens, or passwords in source. Read them from the
  environment (`os.environ`).

## Hygiene
- No debug prints or commented-out code on the request path.
MD

: > app/__init__.py

cat > app/config.py <<'PY'
import os

API_KEY = os.environ["SHOP_API_KEY"]
DB_PASSWORD = os.environ["SHOP_DB_PASSWORD"]
PY

cat > app/service.py <<'PY'
def get_user(user_id):
    # (pretend this reads from the database)
    return {"id": user_id, "name": "demo"}
PY

cat > app/handlers.py <<'PY'
from app import service


def handle_get_user(user_id):
    return service.get_user(user_id)
PY

cat > README.md <<'MD'
# shop-api

A tiny example service.

## Configuration
Set `SHOP_API_KEY` and `SHOP_DB_PASSWORD` in the environment before running.
MD

git add -A
GIT_AUTHOR_DATE="2026-05-25T10:00:00" GIT_COMMITTER_DATE="2026-05-25T10:00:00" \
  git commit -q -m "Initial shop-api: handlers, service, config"

# ===========================================================================
# THE BAD CHANGE (staged, NOT committed) — this is what the guard must catch.
# ===========================================================================

# 1. Hardcoded live-looking secrets instead of env vars.
cat > app/config.py <<'PY'
API_KEY = "sk-live-9f2c4b7a1e8d4f0a9c3b6e5d2a1f8c7b"
DB_PASSWORD = "Sup3rSecret!prod-db"
PY

# 2. Business logic + raw SQL + a debug print smuggled into the thin layer.
cat > app/handlers.py <<'PY'
import sqlite3


def handle_get_user(user_id):
    # TODO: move this back into the service layer someday
    conn = sqlite3.connect("prod.db")
    cur = conn.execute("SELECT * FROM users WHERE id = " + str(user_id))
    row = cur.fetchone()
    print("DEBUG fetched user:", row)
    if row and row[3] > 0:
        discount = row[3] * 0.1
    else:
        discount = 0
    return {"id": row[0], "name": row[1], "discount": discount}
PY

# 3. A docs claim that directly contradicts the code being committed.
cat >> README.md <<'MD'

## Security
No secrets are stored in this repository. All credentials are injected at
runtime, so this codebase is safe to make public.
MD

git add -A

cat <<'EOF'

==================================================================
  commit-guard-demo ready.
==================================================================
A clean baseline is committed. A BAD change is now STAGED (not
committed). `git diff --cached` shows three planted problems:

  - app/config.py    hardcoded live-looking API_KEY + DB_PASSWORD  (BLOCK)
  - app/handlers.py  raw SQL injection + business logic + debug
                     print in the thin layer (policy violation)    (BLOCK/WARN)
  - README.md        "No secrets are stored" — contradicts the code (WARN)

Ask the agent:
  "Run the semantic commit guard on my staged changes — is this safe
   to commit?"

It should BLOCK, cite each file:line, and explain the docs-vs-code lie.

Inspect the staged diff yourself:
  git diff --cached

Reset this demo:  bash setup.sh
==================================================================
EOF
