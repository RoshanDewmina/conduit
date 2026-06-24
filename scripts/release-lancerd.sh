#!/usr/bin/env bash
set -euo pipefail

# Build portable lancerd tarballs for self-host distribution.
#
# Usage:
#   scripts/release-lancerd.sh [version]
#
# Example:
#   scripts/release-lancerd.sh v0.1.0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_DIR="$ROOT_DIR/daemon/lancerd"
DIST_DIR="$DAEMON_DIR/dist"
VERSION="${1:-$(date +%Y%m%d)}"

TARGETS=(
  "linux amd64"
  "linux arm64"
  "darwin arm64"
  "darwin amd64"
)

# Public GCS distribution bucket install.sh downloads from. Keep the bucket in
# sync with DEFAULT_RELEASE_BASE in daemon/lancerd/install.sh.
DIST_BUCKET="${LANCER_DIST_BUCKET:-gs://conduit-dist-f1c2466d}"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for target in "${TARGETS[@]}"; do
  read -r GOOS GOARCH <<<"$target"
  OUT_BASENAME="lancerd-${VERSION}-${GOOS}-${GOARCH}"
  STAGE_DIR="$DIST_DIR/$OUT_BASENAME"
  mkdir -p "$STAGE_DIR"

  # Build from inside the module dir (the module's go.mod lives in $DAEMON_DIR;
  # modern Go rejects `go build <abs-dir>` run from a dir with no go.mod).
  ( cd "$DAEMON_DIR" && CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
      go build -ldflags "-s -w -X main.version=${VERSION#v}" \
      -o "$STAGE_DIR/lancerd" . )

  # Guard against ever shipping the stale Swift 0.1.0 daemon (which lacked the
  # policy engine + resident `daemon` command). The Go build's usage banner
  # lists `lancerd daemon`; verify it on any target we can execute on this host.
  if [[ "$GOOS" == "$(go env GOHOSTOS)" && "$GOARCH" == "$(go env GOHOSTARCH)" ]]; then
    # lancerd with no args prints usage to stderr and exits 1 — capture first
    # (a bare pipe would trip `set -o pipefail` on that expected non-zero exit).
    USAGE_OUT="$("$STAGE_DIR/lancerd" 2>&1 || true)"
    if ! grep -q "lancerd daemon" <<<"$USAGE_OUT"; then
      echo "FATAL: $OUT_BASENAME lacks the 'daemon' command (governance engine missing)" >&2
      exit 1
    fi
    echo "  verified $OUT_BASENAME exposes the daemon/policy surface (version $("$STAGE_DIR/lancerd" version))"
  fi

  cp "$DAEMON_DIR/README.md" "$STAGE_DIR/README.md"
  cp "$DAEMON_DIR/install.sh" "$STAGE_DIR/install.sh"
  cp "$ROOT_DIR/docs/lancer-hook.sh" "$STAGE_DIR/lancer-hook.sh"
  cp "$ROOT_DIR/docs/codex-lancer-hook.sh" "$STAGE_DIR/codex-lancer-hook.sh"
  cp "$ROOT_DIR/docs/codex-hooks.json" "$STAGE_DIR/codex-hooks.json"

  # Flat binary install.sh fetches directly: ${BASE}/lancerd_${GOOS}_${GOARCH}.
  # (install.sh consumes flat, unversioned, underscored names + SHA256SUMS — the
  # tarballs above are for manual/from-source installs only.)
  cp "$STAGE_DIR/lancerd" "$DIST_DIR/lancerd_${GOOS}_${GOARCH}"

  tar -C "$DIST_DIR" -czf "$DIST_DIR/${OUT_BASENAME}.tar.gz" "$OUT_BASENAME"
  rm -rf "$STAGE_DIR"
  echo "Built $DIST_DIR/${OUT_BASENAME}.tar.gz"
done

# SHA256SUMS over the flat binaries, with the exact names install.sh greps for
# (lancerd_${OS}_${ARCH}). Without this the installer refuses to install.
( cd "$DIST_DIR" && shasum -a 256 lancerd_* > SHA256SUMS )
cp "$DAEMON_DIR/install.sh" "$DIST_DIR/install.sh"
echo "Wrote $DIST_DIR/SHA256SUMS + install.sh"

echo "Release artifacts are in $DIST_DIR"
echo
echo "To publish (owner step — requires gcloud auth on the dist bucket):"
echo "  gsutil -m cp \"$DIST_DIR\"/lancerd_* \"$DIST_DIR/SHA256SUMS\" \"$DIST_DIR/install.sh\" $DIST_BUCKET/"
