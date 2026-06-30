#!/usr/bin/env bash
set -euo pipefail

# install.sh — lancerd installer (one command, fresh VPS to paired)
#
# On a fresh Hetzner / DigitalOcean / any linux box (run as the user that will
# own the agents; root is fine), this single command installs and pairs:
#   curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh
#   curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh -s -- --hooks claude
#
# Downloads a prebuilt lancerd binary for linux/macOS × amd64/arm64 from the
# public GCS distribution bucket (the source repo is private, so this is the
# canonical channel — NOT GitHub Releases), verifies SHA256, installs to
# ~/.lancer/bin/lancerd, registers the background service, and starts pairing.
# (Once a custom domain is set, https://get.<domain>/install.sh can redirect here.)
#
# Flags:
#   --hooks <mode>      Install agent hooks (none|claude|codex|both). Default: none
#   --from-source       Build from Go source instead of downloading a binary
#   --download-base <url>  Base URL for prebuilt binaries (dev/testing)
#
# Environment:
#   LANCER_RELEASE_BASE   Base URL for prebuilt-binary downloads (default: see below)

# Tolerate being piped to `sh` (no BASH_SOURCE) under `set -u`; fall back to $0.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo .)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd 2>/dev/null || echo "$SCRIPT_DIR")"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.lancer/bin}"
HOOKS_MODE="none"
FROM_SOURCE="false"

# Public GCS distribution bucket (source repo is private, so release assets are
# hosted on a public Cloud Storage bucket rather than GitHub Releases).
DEFAULT_RELEASE_BASE="https://storage.googleapis.com/conduit-dist-f1c2466d"
DOWNLOAD_BASE="${LANCER_RELEASE_BASE:-$DEFAULT_RELEASE_BASE}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hooks)
      HOOKS_MODE="${2:-none}"
      shift 2
      ;;
    --from-source)
      FROM_SOURCE="true"
      shift
      ;;
    --download-base)
      DOWNLOAD_BASE="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/lancerd"

fail_checksum() {
  local expected="$1" actual="$2" name="$3"
  echo "ERROR: checksum mismatch for ${name}" >&2
  echo "  Expected: ${expected}" >&2
  echo "  Actual:   ${actual}" >&2
  rm -f "$TARGET"
  exit 1
}

download_file() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$out" "$url"
  else
    echo "ERROR: neither curl nor wget found" >&2
    exit 1
  fi
}

# Portable SHA-256: sha256sum (Linux/coreutils) or shasum (macOS). A minimal
# Hetzner/Ubuntu image ships sha256sum but not always shasum.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: neither sha256sum nor shasum found — cannot verify download" >&2
    exit 1
  fi
}

if [[ "$FROM_SOURCE" == "true" ]]; then
  command -v go >/dev/null 2>&1 || { echo "ERROR: go is required for --from-source" >&2; exit 1; }
  echo "Building lancerd from source..."
  (cd "$SCRIPT_DIR" && go build -o "$TARGET" .)
elif [[ -x "$SCRIPT_DIR/lancerd" ]]; then
  cp "$SCRIPT_DIR/lancerd" "$TARGET"
else
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "ERROR: unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac
  case "$OS" in
    linux|darwin) ;;
    *) echo "ERROR: unsupported OS: $OS" >&2; exit 1 ;;
  esac

  BINARY_URL="${DOWNLOAD_BASE}/lancerd_${OS}_${ARCH}"
  echo "Downloading lancerd for ${OS}/${ARCH}..."
  download_file "$BINARY_URL" "$TARGET"

  SHA256_URL="${DOWNLOAD_BASE}/SHA256SUMS"
  SHA256_CONTENT=""
  if command -v curl >/dev/null 2>&1; then
    SHA256_CONTENT="$(curl -fsSL "$SHA256_URL" 2>/dev/null || true)"
  elif command -v wget >/dev/null 2>&1; then
    SHA256_CONTENT="$(wget -q -O - "$SHA256_URL" 2>/dev/null || true)"
  fi

  if [[ -z "$SHA256_CONTENT" ]]; then
    echo "ERROR: SHA256SUMS not reachable at ${SHA256_URL} — refusing to install unsigned binary" >&2
    rm -f "$TARGET"
    exit 1
  fi

  EXPECTED="$(echo "$SHA256_CONTENT" | grep "lancerd_${OS}_${ARCH}" | awk '{print $1}')"
  if [[ -z "$EXPECTED" ]]; then
    echo "ERROR: no SHA256 entry for lancerd_${OS}_${ARCH} in SHA256SUMS" >&2
    rm -f "$TARGET"
    exit 1
  fi

  ACTUAL="$(sha256_of "$TARGET")"
  if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    fail_checksum "$EXPECTED" "$ACTUAL" "lancerd_${OS}_${ARCH}"
  fi
  echo "Checksum verified"
fi

chmod 755 "$TARGET"

USAGE_OUT="$("$TARGET" 2>&1 || true)"
if ! grep -q "lancerd daemon" <<<"$USAGE_OUT"; then
  echo "ERROR: installed lancerd lacks the 'daemon' command — stale/incompatible build." >&2
  rm -f "$TARGET"
  exit 1
fi

echo "Installed lancerd at ${TARGET}"
"$TARGET" version || true

install_claude_hook() {
  if [[ ! -f "$REPO_ROOT/docs/lancer-hook.sh" ]]; then
    echo "Skipping Claude hook: lancer-hook.sh not found at ${REPO_ROOT}/docs/lancer-hook.sh" >&2
    return
  fi
  mkdir -p "$HOME/.claude/hooks"
  cp "$REPO_ROOT/docs/lancer-hook.sh" "$HOME/.claude/hooks/lancer-hook.sh"
  chmod 700 "$HOME/.claude/hooks/lancer-hook.sh"
  echo "Installed Claude hook: ~/.claude/hooks/lancer-hook.sh"
}

install_codex_hook() {
  HOOK_SRC="$REPO_ROOT/docs/codex-lancer-hook.sh"
  HOOK_JSON="$REPO_ROOT/docs/codex-hooks.json"
  if [[ ! -f "$HOOK_SRC" ]]; then
    echo "Skipping Codex hook: codex-lancer-hook.sh not found at ${HOOK_SRC}" >&2
    return
  fi
  mkdir -p "$HOME/.codex/hooks"
  cp "$HOOK_SRC" "$HOME/.codex/hooks/lancer-hook.sh"
  chmod 700 "$HOME/.codex/hooks/lancer-hook.sh"
  if [[ -f "$HOOK_JSON" ]]; then
    cp "$HOOK_JSON" "$HOME/.codex/hooks.json"
    chmod 600 "$HOME/.codex/hooks.json"
  fi
  echo "Installed Codex hook: ~/.codex/hooks/lancer-hook.sh"
}

install_shim() {
  # Resolve the real claude binary BEFORE the shim shadows it (skip INSTALL_DIR).
  real_claude=""
  OLD_IFS="$IFS"
  IFS=':'
  for p in $PATH; do
    if [ "$p" != "$INSTALL_DIR" ] && [ -x "$p/claude" ]; then
      real_claude="$p/claude"
      break
    fi
  done
  IFS="$OLD_IFS"

  mkdir -p "$HOME/.lancer"
  printf 'export LANCER_REAL_claude=%s\n' "$real_claude" > "$HOME/.lancer/shim.env"

  # PATH-level shim launcher. Sources shim.env so LANCER_REAL_claude is set even
  # in non-interactive shells that never sourced the rc snippet (fail-open).
  cat > "$INSTALL_DIR/claude" <<'LAUNCH'
#!/bin/sh
[ -z "${LANCER_REAL_claude:-}" ] && [ -f "$HOME/.lancer/shim.env" ] && . "$HOME/.lancer/shim.env"
export LANCER_REAL_claude
exec "$HOME/.lancer/bin/lancerd" shim claude "$@"
LAUNCH
  chmod 755 "$INSTALL_DIR/claude"

  # Shell-integration snippet (function + env shadowing).
  cp "$SCRIPT_DIR/shim/lancer-shim.sh" "$HOME/.lancer/lancer-shim.sh"

  # Idempotent managed block in rc files.
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -e "$rc" ] || continue
    if ! grep -q '>>> lancer shim >>>' "$rc" 2>/dev/null; then
      {
        echo ''
        echo '# >>> lancer shim >>>'
        echo 'export PATH="$HOME/.lancer/bin:$PATH"'
        echo '[ -f "$HOME/.lancer/lancer-shim.sh" ] && . "$HOME/.lancer/lancer-shim.sh"'
        echo '# <<< lancer shim <<<'
      } >> "$rc"
    fi
  done
  echo "Installed Lancer shim: ~/.lancer/bin/claude (real: ${real_claude:-not found})"
}

case "$HOOKS_MODE" in
  none) ;;
  claude) install_claude_hook ;;
  codex) install_codex_hook ;;
  both) install_claude_hook; install_codex_hook ;;
  *) echo "Invalid --hooks mode: $HOOKS_MODE" >&2; exit 1 ;;
esac

# Opt-in three-layer claude shim (PATH launcher + shell function + env). Off by
# default because it edits the user's shell rc files; enable with LANCER_INSTALL_SHIM=1.
if [ "${LANCER_INSTALL_SHIM:-}" = "1" ]; then
  install_shim
fi

# Start the resident daemon as a background service (launchd/systemd) so it's
# running and ready to pair. Tolerate failure — the user can re-run it manually.
echo ""
echo "Starting the Lancer background service…"
"$TARGET" install 2>&1 | sed 's/^/  /' || echo "  (could not auto-start the service — run '$TARGET install' manually)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Lancer daemon installed and running."
echo ""
echo "  Pair your phone — scan the QR below (or type the code):"
echo "    1. Open Lancer on your iPhone"
echo "    2. Tap  Settings → Relay Pairing"
echo "    3. Scan the QR, or enter the 6-digit code"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "${LANCER_SKIP_PAIR:-}" != "1" ]]; then
  "$TARGET" pair 2>&1 || true
fi

echo ""
echo "  Re-pair anytime:          $TARGET pair"
echo "  Diagnose the daemon:      $TARGET doctor"
echo "  Self-host your own relay: daemon/push-backend/SELF_HOST.md"
echo ""