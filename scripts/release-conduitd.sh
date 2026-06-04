#!/usr/bin/env bash
set -euo pipefail

# Build portable conduitd tarballs for self-host distribution.
#
# Usage:
#   scripts/release-conduitd.sh [version]
#
# Example:
#   scripts/release-conduitd.sh v0.1.0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_DIR="$ROOT_DIR/daemon/conduitd"
DIST_DIR="$DAEMON_DIR/dist"
VERSION="${1:-$(date +%Y%m%d)}"

TARGETS=(
  "linux amd64"
  "linux arm64"
  "darwin arm64"
)

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for target in "${TARGETS[@]}"; do
  read -r GOOS GOARCH <<<"$target"
  OUT_BASENAME="conduitd-${VERSION}-${GOOS}-${GOARCH}"
  STAGE_DIR="$DIST_DIR/$OUT_BASENAME"
  mkdir -p "$STAGE_DIR"

  CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
    go build -o "$STAGE_DIR/conduitd" "$DAEMON_DIR"

  cp "$DAEMON_DIR/README.md" "$STAGE_DIR/README.md"
  cp "$DAEMON_DIR/install.sh" "$STAGE_DIR/install.sh"
  cp "$ROOT_DIR/docs/conduit-hook.sh" "$STAGE_DIR/conduit-hook.sh"
  cp "$ROOT_DIR/docs/codex-conduit-hook.sh" "$STAGE_DIR/codex-conduit-hook.sh"
  cp "$ROOT_DIR/docs/codex-hooks.json" "$STAGE_DIR/codex-hooks.json"

  tar -C "$DIST_DIR" -czf "$DIST_DIR/${OUT_BASENAME}.tar.gz" "$OUT_BASENAME"
  rm -rf "$STAGE_DIR"
  echo "Built $DIST_DIR/${OUT_BASENAME}.tar.gz"
done

echo "Release artifacts are in $DIST_DIR"
