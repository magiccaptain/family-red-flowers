#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/install-linux-launcher.py
if [[ -f artifacts/pg-connection.json ]]; then
  export RF_PG_CONFIG_FILE="${RF_PG_CONFIG_FILE:-$PWD/artifacts/pg-connection.json}"
fi
exec flutter run -d linux "$@"
