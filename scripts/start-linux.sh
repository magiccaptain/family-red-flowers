#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f artifacts/pg-connection.json ]]; then
  export RF_PG_CONFIG_FILE="${RF_PG_CONFIG_FILE:-$PWD/artifacts/pg-connection.json}"
fi
if [[ ! -x build/linux/x64/release/bundle/red_flowers ]]; then
  flutter build linux --release
fi
exec build/linux/x64/release/bundle/red_flowers "$@"
