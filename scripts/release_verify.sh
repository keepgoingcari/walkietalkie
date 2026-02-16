#!/usr/bin/env bash
set -euo pipefail

# Verify signature + notarization status of a macOS app bundle.
# Usage:
#   scripts/release_verify.sh /path/to/Walkietalkie.app

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/Walkietalkie.app"
  exit 1
fi

APP_PATH="$1"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

echo "[1/4] codesign verify"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "[2/4] spctl assessment"
spctl -a -vv "$APP_PATH"

echo "[3/4] stapler validate"
xcrun stapler validate "$APP_PATH"

echo "[4/4] Display signing identity"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | rg "Authority|TeamIdentifier|Timestamp|Identifier" || true

echo

echo "Verification complete."
