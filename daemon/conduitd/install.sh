#!/usr/bin/env bash
set -euo pipefail

# install.sh — conduitd installer
#
# Intended to be run via curl | sh:
#   curl -fsSL https://conduit.dev/install.sh | sh
#
# Downloads a prebuilt conduitd binary for linux/macOS × amd64/arm64,
# installs it to ~/.conduit/bin, optionally installs agent hooks, and
# prints the pairing QR for the phone to scan.
#
# Usage:
#   curl -fsSL https://conduit.dev/install.sh | sh
#   curl -fsSL https://conduit.dev/install.sh | sh -s -- --hooks claude
#
# Flags:
#   --hooks <mode>   Install agent hooks (none|claude|codex|both). Default: none
#   --from-source    Build from Go source instead of downloading a binary
#   --download-base <url>  Base URL for prebuilt binaries (dev/testing)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.conduit/bin}"
HOOKS_MODE="none"
FROM_SOURCE="false"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://conduit.dev/releases/latest}"

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
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/conduitd"

# Download or build the binary.
if [[ "$FROM_SOURCE" == "true" ]]; then
  command -v go >/dev/null 2>&1 || { echo "go is required for --from-source" >&2; exit 1; }
  echo "Building conduitd from source..."
  (cd "$SCRIPT_DIR" && go build -o "$TARGET" .)
elif [[ -x "$SCRIPT_DIR/conduitd" ]]; then
  # Local dev path: use the pre-built binary next to this script.
  cp "$SCRIPT_DIR/conduitd" "$TARGET"
else
  # curl | sh path: detect platform/arch and download a prebuilt binary.
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac
  case "$OS" in
    linux|darwin) ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
  esac

  BINARY_URL="${DOWNLOAD_BASE}/conduitd_${OS}_${ARCH}"
  echo "Downloading conduitd for ${OS}/${ARCH} from ${BINARY_URL}..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$TARGET" "$BINARY_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TARGET" "$BINARY_URL"
  else
    echo "Neither curl nor wget found" >&2
    exit 1
  fi

  # Checksum verification (optional — warn on failure, don't hard-fail).
  SHA256_URL="${DOWNLOAD_BASE}/SHA256SUMS"
  SHA256_CONTENT=""
  if command -v curl >/dev/null 2>&1; then
    SHA256_CONTENT="$(curl -fsSL "$SHA256_URL" 2>/dev/null || true)"
  elif command -v wget >/dev/null 2>&1; then
    SHA256_CONTENT="$(wget -q -O - "$SHA256_URL" 2>/dev/null || true)"
  fi
  if [[ -n "$SHA256_CONTENT" ]]; then
    EXPECTED="$(echo "$SHA256_CONTENT" | grep "conduitd_${OS}_${ARCH}" | awk '{print $1}')"
    if [[ -n "$EXPECTED" ]]; then
      ACTUAL="$(shasum -a 256 "$TARGET" | awk '{print $1}')"
      if [[ "$ACTUAL" != "$EXPECTED" ]]; then
        echo "ERROR: checksum mismatch for conduitd_${OS}_${ARCH}" >&2
        echo "  Expected: $EXPECTED" >&2
        echo "  Actual:   $ACTUAL" >&2
        rm -f "$TARGET"
        exit 1
      fi
      echo "Checksum verified ✓"
    else
      echo "WARNING: no SHA256 entry for conduitd_${OS}_${ARCH} in SHA256SUMS" >&2
    fi
  else
    echo "WARNING: SHA256SUMS not reachable at $SHA256_URL — skipping checksum verification" >&2
  fi
fi

chmod 755 "$TARGET"

# Fail closed guard: verify the binary has the expected daemon command.
USAGE_OUT="$("$TARGET" 2>&1 || true)"
if ! grep -q "conduitd daemon" <<<"$USAGE_OUT"; then
  echo "ERROR: installed conduitd lacks the 'daemon' command — stale/incompatible build." >&2
  rm -f "$TARGET"
  exit 1
fi

echo "Installed conduitd at $TARGET"
"$TARGET" version || true

install_claude_hook() {
  HOOK_SRC="$REPO_ROOT/docs/conduit-hook.sh"
  if [[ ! -f "$HOOK_SRC" ]]; then
    echo "Skipping Claude hook: conduit-hook.sh not found at $HOOK_SRC" >&2
    return
  fi
  mkdir -p "$HOME/.claude/hooks"
  cp "$HOOK_SRC" "$HOME/.claude/hooks/conduit-hook.sh"
  chmod 700 "$HOME/.claude/hooks/conduit-hook.sh"
  echo "Installed Claude hook: ~/.claude/hooks/conduit-hook.sh"
}

install_codex_hook() {
  HOOK_SRC="$REPO_ROOT/docs/codex-conduit-hook.sh"
  HOOK_JSON="$REPO_ROOT/docs/codex-hooks.json"
  if [[ ! -f "$HOOK_SRC" ]]; then
    echo "Skipping Codex hook: codex-conduit-hook.sh not found at $HOOK_SRC" >&2
    return
  fi
  mkdir -p "$HOME/.codex/hooks"
  cp "$HOOK_SRC" "$HOME/.codex/hooks/conduit-hook.sh"
  chmod 700 "$HOME/.codex/hooks/conduit-hook.sh"
  if [[ -f "$HOOK_JSON" ]]; then
    cp "$HOOK_JSON" "$HOME/.codex/hooks.json"
    chmod 600 "$HOME/.codex/hooks.json"
  fi
  echo "Installed Codex hook: ~/.codex/hooks/conduit-hook.sh"
}

case "$HOOKS_MODE" in
  none) ;;
  claude) install_claude_hook ;;
  codex) install_codex_hook ;;
  both) install_claude_hook; install_codex_hook ;;
  *) echo "Invalid --hooks mode: $HOOKS_MODE" >&2; exit 1 ;;
esac

# Print pairing QR so the user can scan with Conduit immediately.
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  conduitd installed! Starting pairing..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
"$TARGET" pair
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Scan the QR above with Conduit on your phone"
echo "  to pair this host."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"