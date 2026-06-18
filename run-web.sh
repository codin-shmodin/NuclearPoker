#!/usr/bin/env bash
#
# run-web.sh — run NuclearPoker in the browser.
#
# Launches the Flutter app on Chrome (Flutter opens the browser for you) with
# hot reload. Just run:
#
#   ./run-web.sh
#
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter isn't on your PATH. Install it: https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

echo "Starting NuclearPoker in Chrome (hot reload on; press 'q' to quit)…"
exec flutter run -d chrome "$@"
