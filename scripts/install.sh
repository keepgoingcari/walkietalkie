#!/usr/bin/env bash
set -euo pipefail

TAP="keepgoingcari/walkietalkie"
CASK="walkietalkie"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install from https://brew.sh"
  exit 1
fi

brew tap "$TAP"
brew install --cask --no-quarantine "$CASK"

echo
echo "Installed. Run onboarding next:"
echo "  walkietalkie setup"
