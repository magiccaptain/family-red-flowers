#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --no-web-resources-cdn --no-wasm-dry-run
exec python3 -m http.server 7358 --bind 127.0.0.1 --directory build/web
