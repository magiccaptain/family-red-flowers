#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x database/.venv/bin/python ]]; then
  python3 -m venv database/.venv
fi
database/.venv/bin/python -m pip install --disable-pip-version-check -r database/requirements.txt
exec database/.venv/bin/python database/initialize.py
