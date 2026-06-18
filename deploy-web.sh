#!/usr/bin/env bash
#
# deploy-web.sh — build NuclearPoker for the web and deploy to Firebase Hosting.
#
# One-time setup (do these once):
#   npm install -g firebase-tools   # install the CLI
#   firebase login                  # opens a browser to authenticate
#
# Then ship anytime with:
#   ./deploy-web.sh
#
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter isn't on your PATH. Install it: https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "Firebase CLI not found. Install it: npm install -g firebase-tools" >&2
  exit 1
fi

echo "Building web release…"
flutter build web

echo "Deploying to Firebase Hosting…"
firebase deploy --only hosting

echo "Done. Your app is live (see the Hosting URL above)."
