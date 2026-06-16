#!/usr/bin/env bash
set -euo pipefail

# release.sh — Build and upload conduitd release binaries to GitHub
#
# Prerequisites:
#   - gh CLI installed and authenticated: https://cli.github.com
#   - Write access to the repository
#
# Usage:
#   ./release.sh v0.2.0
#
# Dry-run (builds locally, does NOT create/upload release):
#   DRY_RUN=1 ./release.sh v0.2.0
#
# Environment:
#   DRY_RUN     Set to "1" to skip GitHub upload (local build only). Default: 0
#   GH_REPO     GitHub repo (owner/name). Default: REPLACE_ME/conduit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version> [--dry-run]"
  echo ""
  echo "  version   Tag to release (e.g. v0.2.0)"
  echo "  --dry-run Build only, skip GitHub upload"
  exit 1
fi

VERSION="$1"
shift

DRY_RUN="${DRY_RUN:-0}"
GH_REPO="${GH_REPO:-REPLACE_ME/conduit}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

if [[ "$DRY_RUN" == "0" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found. Install it from https://cli.github.com" >&2
    echo "  brew install gh  # on macOS" >&2
    echo "  or set DRY_RUN=1 for a local-only build" >&2
    exit 1
  fi

  if ! gh auth status 2>/dev/null; then
    echo "ERROR: gh CLI is not authenticated. Run 'gh auth login' first." >&2
    exit 1
  fi
fi

export VERSION
echo "Building conduitd ${VERSION}..."

"${SCRIPT_DIR}/build-release.sh"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  dist/ contents:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
(cd "$DIST_DIR" && shasum -a 256 conduitd_*) || true

if [[ "$DRY_RUN" == "1" ]]; then
  echo ""
  echo "[DRY RUN] Would run: gh release create ${VERSION} ${DIST_DIR}/* --title '${VERSION}' --notes 'See changelog'"
  echo "  Dry-run complete. Upload manually with:"
  echo "    gh release upload ${VERSION} ${DIST_DIR}/*"
  exit 0
fi

echo ""
echo "Creating GitHub release ${VERSION} for ${GH_REPO}..."

gh release create "$VERSION" \
  --repo "$GH_REPO" \
  --title "$VERSION" \
  --notes "See [CHANGELOG](CHANGELOG.md) for details." \
  --verify-tag 2>/dev/null || {
    echo "NOTE: Release ${VERSION} may already exist. Attempting upload only..."
  }

echo "Uploading assets..."
gh release upload "$VERSION" "$DIST_DIR"/* --repo "$GH_REPO" --clobber

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Release ${VERSION} published!"
echo "  https://github.com/${GH_REPO}/releases/tag/${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"