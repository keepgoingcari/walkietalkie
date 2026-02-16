#!/usr/bin/env bash
set -euo pipefail

# Sign, notarize, and staple a macOS app bundle.
# Usage:
#   scripts/release_notarize.sh /path/to/Walkietalkie.app
#
# Required env vars:
#   SIGN_IDENTITY         e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE        e.g. "walkietalkie-notary" (from notarytool store-credentials)
#
# Optional env vars:
#   OUTPUT_DIR            default: ./dist/notarized

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/Walkietalkie.app"
  exit 1
fi

APP_PATH="$1"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

: "${SIGN_IDENTITY:?Missing SIGN_IDENTITY}"
: "${NOTARY_PROFILE:?Missing NOTARY_PROFILE}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist/notarized}"
mkdir -p "$OUTPUT_DIR"

APP_NAME="$(basename "$APP_PATH" .app)"
WORK_APP="$OUTPUT_DIR/${APP_NAME}.app"
ZIP_PATH="$OUTPUT_DIR/${APP_NAME}.zip"

rm -rf "$WORK_APP" "$ZIP_PATH"
cp -R "$APP_PATH" "$WORK_APP"

echo "[1/5] Signing app bundle..."
codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$WORK_APP"

echo "[2/5] Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$WORK_APP"

echo "[3/5] Creating zip for notarization..."
ditto -c -k --keepParent "$WORK_APP" "$ZIP_PATH"

echo "[4/5] Submitting to Apple notarization..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "[5/5] Stapling notarization ticket..."
xcrun stapler staple "$WORK_APP"
xcrun stapler validate "$WORK_APP"
spctl -a -vv "$WORK_APP"

echo

echo "Done. Notarized app: $WORK_APP"
echo "Zip artifact: $ZIP_PATH"
