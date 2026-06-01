#!/usr/bin/env bash
set -e
python -c "import app.settings, app.client"
python -m pytest -q
