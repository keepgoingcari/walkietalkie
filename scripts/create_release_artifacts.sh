#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version> (example: 0.1.0)"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TAG="v${VERSION}"
ARTIFACT="walkietalkie-${VERSION}.tar.gz"

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG does not exist. Create and push it first."
  exit 1
fi

git archive --format=tar.gz --prefix="walkietalkie-${VERSION}/" "$TAG" -o "$ARTIFACT"
SHA256="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"

echo "Created $ARTIFACT"
echo "SHA256: $SHA256"

echo "Next:"
echo "  gh release create $TAG --title '$TAG' --notes 'Release $TAG' $ARTIFACT"
