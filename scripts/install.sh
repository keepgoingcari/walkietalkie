#!/usr/bin/env bash
set -euo pipefail

TAP="keepgoingcari/walkietalkie"
CASK="walkietalkie"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install from https://brew.sh"
  exit 1
fi

brew tap "$TAP"
brew install --cask "$CASK"

BIN_PATH="$(brew --prefix)/bin/walkietalkie"
if command -v xattr >/dev/null 2>&1 && [[ -e "$BIN_PATH" ]]; then
  xattr -dr com.apple.quarantine "$BIN_PATH" 2>/dev/null || true
fi

echo
echo "Installed. Run onboarding next:"
echo "  walkietalkie setup"
