#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x database/.venv/bin/python ]]; then
  python3 -m venv database/.venv
  database/.venv/bin/python -m pip install --disable-pip-version-check -r database/requirements.txt
fi
database/.venv/bin/python -m unittest discover -s database -p 'test_*.py' -v
exec database/.venv/bin/python database/run_dart_integration.py
