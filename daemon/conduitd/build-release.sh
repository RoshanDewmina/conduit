#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

cd "$SCRIPT_DIR"

PLATFORMS=(
  "darwin/amd64"
  "darwin/arm64"
  "linux/amd64"
  "linux/arm64"
)

mkdir -p "$DIST_DIR"

BUILD_ARGS=()
if [[ -n "${VERSION:-}" ]]; then
  BUILD_ARGS+=("-ldflags=-X main.version=${VERSION}")
fi

for PLATFORM in "${PLATFORMS[@]}"; do
  OS="${PLATFORM%/*}"
  ARCH="${PLATFORM#*/}"
  OUTPUT="$DIST_DIR/conduitd_${OS}_${ARCH}"

  echo "  Building conduitd for ${OS}/${ARCH}..."
  GOOS="$OS" GOARCH="$ARCH" go build "${BUILD_ARGS[@]}" -o "$OUTPUT" .
done

echo ""
echo "Generating SHA256SUMS..."
(cd "$DIST_DIR" && shasum -a 256 conduitd_* > SHA256SUMS)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Build complete — dist/ contents:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh "$DIST_DIR"
