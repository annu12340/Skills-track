#!/usr/bin/env bash
# Materializes a Python project pinned to ancient deps whose code won't build
# against modern versions — the dependency-upgrade-loop demo.
# Re-run to reset.
set -euo pipefail
cd "$(dirname "$0")"

# --- reset any previous run -------------------------------------------------
rm -rf .git app tests requirements.txt verify.sh README.md *.bak .venv

git init -q
git config user.name  "Demo Author"
git config user.email "demo@example.com"
git config commit.gpgsign false
mkdir -p app tests

# --- ancient, deliberately stale pins --------------------------------------
cat > requirements.txt <<'TXT'
flask==1.1.2
pydantic==1.10.2
requests==2.22.0
TXT

: > app/__init__.py

# pydantic v1 API: BaseSettings lives in `pydantic` and `.dict()` is the
# serializer. Both break in pydantic v2 (BaseSettings moved to the separate
# `pydantic-settings` package; `.dict()` -> `.model_dump()`).
cat > app/settings.py <<'PY'
from pydantic import BaseSettings


class Settings(BaseSettings):
    api_url: str = "https://example.com/api"
    timeout: int = 30


def as_dict():
    return Settings().dict()
PY

cat > app/client.py <<'PY'
import requests

from app.settings import Settings


def fetch(path):
    cfg = Settings()
    resp = requests.get(cfg.api_url + path, timeout=cfg.timeout)
    return resp.status_code
PY

cat > tests/test_settings.py <<'PY'
from app.settings import as_dict


def test_defaults():
    cfg = as_dict()
    assert cfg["timeout"] == 30
    assert cfg["api_url"].startswith("https://")
PY

# The build/verify oracle: exits 0 only when the project imports + tests pass.
cat > verify.sh <<'SH'
#!/usr/bin/env bash
set -e
python -c "import app.settings, app.client"
python -m pytest -q
SH
chmod +x verify.sh

cat > README.md <<'MD'
# legacy-fetcher

A small Flask-era service pinned to old dependencies. It no longer builds
against modern Python package versions.

## Verify
```bash
pip install -r requirements.txt
bash verify.sh   # must exit 0 when healthy
```
MD

git add -A
GIT_AUTHOR_DATE="2021-03-10T10:00:00" GIT_COMMITTER_DATE="2021-03-10T10:00:00" \
  git commit -q -m "legacy-fetcher pinned to flask 1.1 / pydantic 1.10"

cat <<'EOF'

==================================================================
  dependency-upgrade-loop-demo ready.
==================================================================
A project frozen on flask==1.1.2 / pydantic==1.10.2 / requests==2.22.0.
The code uses pydantic v1 APIs that were REMOVED in v2:

  - app/settings.py:  `from pydantic import BaseSettings`
                      (moved to the `pydantic-settings` package in v2)
  - app/settings.py:  `.dict()`  ->  `.model_dump()` in v2

Verify oracle (exit 0 = healthy):  bash verify.sh

Ask the agent:
  "This old repo won't build on modern packages — use dependency-upgrade-loop
   to bump everything to latest and fix what breaks until `bash verify.sh`
   passes."

It should branch, bump deps one at a time, migrate BaseSettings to
pydantic-settings, fix `.dict()`, and report the old->new table.

Reset this demo:  bash setup.sh
==================================================================
EOF
