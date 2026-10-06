#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter run -d chrome --web-port 7357 "$@"
