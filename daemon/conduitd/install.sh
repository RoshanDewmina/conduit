#!/usr/bin/env bash
set -euo pipefail

# install.sh — conduitd installer
#
# Intended to be run via curl | sh:
#   curl -fsSL https://github.com/RoshanDewmina/conduit/releases/latest/download/install.sh | sh
#
# Downloads a prebuilt conduitd binary for linux/macOS × amd64/arm64 from
# GitHub Releases, verifies SHA256, installs to ~/.conduit/bin/conduitd,
# and starts the pairing flow.
#
# Usage (canonical GitHub Releases source):
#   curl -fsSL https://github.com/RoshanDewmina/conduit/releases/latest/download/install.sh | sh
#   curl -fsSL https://github.com/RoshanDewmina/conduit/releases/latest/download/install.sh | sh -s -- --hooks claude
# (Once a custom domain is set, a vanity URL like https://get.<domain>/install.sh can redirect here.)
#
# Flags:
#   --hooks <mode>      Install agent hooks (none|claude|codex|both). Default: none
#   --from-source       Build from Go source instead of downloading a binary
#   --download-base <url>  Base URL for prebuilt binaries (dev/testing)
#
# Environment:
#   CONDUIT_RELEASE_BASE   Base URL for GitHub Releases downloads (default: see below)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd 2>/dev/null || echo "$SCRIPT_DIR")"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.conduit/bin}"
HOOKS_MODE="none"
FROM_SOURCE="false"

DEFAULT_RELEASE_BASE="https://github.com/RoshanDewmina/conduit/releases/latest/download"
DOWNLOAD_BASE="${CONDUIT_RELEASE_BASE:-$DEFAULT_RELEASE_BASE}"

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
TARGET="$INSTALL_DIR/conduitd"

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

if [[ "$FROM_SOURCE" == "true" ]]; then
  command -v go >/dev/null 2>&1 || { echo "ERROR: go is required for --from-source" >&2; exit 1; }
  echo "Building conduitd from source..."
  (cd "$SCRIPT_DIR" && go build -o "$TARGET" .)
elif [[ -x "$SCRIPT_DIR/conduitd" ]]; then
  cp "$SCRIPT_DIR/conduitd" "$TARGET"
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

  BINARY_URL="${DOWNLOAD_BASE}/conduitd_${OS}_${ARCH}"
  echo "Downloading conduitd for ${OS}/${ARCH}..."
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

  EXPECTED="$(echo "$SHA256_CONTENT" | grep "conduitd_${OS}_${ARCH}" | awk '{print $1}')"
  if [[ -z "$EXPECTED" ]]; then
    echo "ERROR: no SHA256 entry for conduitd_${OS}_${ARCH} in SHA256SUMS" >&2
    rm -f "$TARGET"
    exit 1
  fi

  ACTUAL="$(shasum -a 256 "$TARGET" | awk '{print $1}')"
  if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    fail_checksum "$EXPECTED" "$ACTUAL" "conduitd_${OS}_${ARCH}"
  fi
  echo "Checksum verified"
fi

chmod 755 "$TARGET"

USAGE_OUT="$("$TARGET" 2>&1 || true)"
if ! grep -q "conduitd daemon" <<<"$USAGE_OUT"; then
  echo "ERROR: installed conduitd lacks the 'daemon' command — stale/incompatible build." >&2
  rm -f "$TARGET"
  exit 1
fi

echo "Installed conduitd at ${TARGET}"
"$TARGET" version || true

install_claude_hook() {
  if [[ ! -f "$REPO_ROOT/docs/conduit-hook.sh" ]]; then
    echo "Skipping Claude hook: conduit-hook.sh not found at ${REPO_ROOT}/docs/conduit-hook.sh" >&2
    return
  fi
  mkdir -p "$HOME/.claude/hooks"
  cp "$REPO_ROOT/docs/conduit-hook.sh" "$HOME/.claude/hooks/conduit-hook.sh"
  chmod 700 "$HOME/.claude/hooks/conduit-hook.sh"
  echo "Installed Claude hook: ~/.claude/hooks/conduit-hook.sh"
}

install_codex_hook() {
  HOOK_SRC="$REPO_ROOT/docs/codex-conduit-hook.sh"
  HOOK_JSON="$REPO_ROOT/docs/codex-hooks.json"
  if [[ ! -f "$HOOK_SRC" ]]; then
    echo "Skipping Codex hook: codex-conduit-hook.sh not found at ${HOOK_SRC}" >&2
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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  conduitd installed at ${TARGET}"
echo ""
echo "  Next steps:"
echo "  1. Run 'conduitd install' to set up launchd/systemd"
echo "  2. Run 'conduitd pair' to generate a pairing QR"
echo "  3. Open Conduit on your phone and scan the QR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "${CONDUIT_SKIP_PAIR:-}" != "1" ]]; then
  "$TARGET" pair 2>&1 || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  For self-host relay setup, see:"
echo "  daemon/push-backend/SELF_HOST.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"