#!/usr/bin/env bash
# Runs the CCParityScreenshots UITest suite (docs/product/2026-07-16-claude-code-app-parity-spec.md)
# on a Simurgh-leased simulator and extracts the captured screenshots into
# docs/test-runs/2026-07-16-cc-parity/lancer/.
#
# NEVER runs bare xcodebuild against a leased simulator -- always through
# `simurgh exec <lease-id> -- ...` so isolation flags (derived data, result
# bundle, -destination) are injected and the lease is renewed for the run.
# NEVER touches ~/.lancer (production daemon state).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="docs/test-runs/2026-07-16-cc-parity/lancer"
mkdir -p "$OUT_DIR"

echo "==> xcodegen generate"
xcodegen generate

echo "==> Acquiring Simurgh lease"
LEASE_JSON="$(simurgh acquire --model 'iPhone 17 Pro' --rm --json)"
echo "$LEASE_JSON"
LEASE_ID="$(echo "$LEASE_JSON" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("lease", d)["id"])')"
UDID="$(echo "$LEASE_JSON" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); l=d.get("lease", d); print(l.get("device", {}).get("udid") or l["udid"])')"
echo "Lease: $LEASE_ID  UDID: $UDID"

cleanup() {
  echo "==> Releasing Simurgh lease $LEASE_ID"
  simurgh release "$LEASE_ID" --json || true
}
trap cleanup EXIT

echo "==> Running CCParityScreenshots via simurgh exec"
set +e
simurgh exec "$LEASE_ID" -- xcodebuild test \
  -project Lancer.xcodeproj \
  -scheme Lancer \
  -only-testing:LancerUITests/CCParityScreenshots \
  | tee "$OUT_DIR/xcodebuild-test.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e

echo "==> Locating result bundle"
RESULTS_DIR="$HOME/.simurgh/leases/$LEASE_ID/Results"
XCRESULT="$(find "$RESULTS_DIR" -maxdepth 1 -name '*.xcresult' -print0 2>/dev/null | xargs -0 ls -td 2>/dev/null | head -1 || true)"

if [ -n "${XCRESULT:-}" ] && [ -e "$XCRESULT" ]; then
  echo "Result bundle: $XCRESULT"
  cp -R "$XCRESULT" "$OUT_DIR/CCParityScreenshots.xcresult" 2>/dev/null || true
  echo "==> Exporting attachments from xcresult (backup path; tests also write PNGs directly)"
  ATTACH_DIR="$(mktemp -d)"
  xcrun xcresulttool export attachments \
    --path "$XCRESULT" \
    --output-path "$ATTACH_DIR" 2>/dev/null || true
  for f in "$ATTACH_DIR"/*cc-[0-9]-*.png; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    name="$(echo "$base" | grep -oE 'cc-[0-9]+-[a-z]+' | head -1)"
    [ -n "$name" ] && cp "$f" "$OUT_DIR/${name}-xcresult.png" || true
  done
else
  echo "WARNING: no .xcresult found under $RESULTS_DIR"
fi

echo "==> Screenshots captured directly by the test process:"
ls -la "$OUT_DIR" || true

if [ "$TEST_STATUS" -ne 0 ]; then
  echo "CCParityScreenshots exited non-zero ($TEST_STATUS) -- inspect $OUT_DIR/xcodebuild-test.log"
fi
exit "$TEST_STATUS"
