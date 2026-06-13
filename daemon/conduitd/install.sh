#!/usr/bin/env bash
set -euo pipefail

# install.sh — local/self-host installer for conduitd
#
# Usage:
#   ./install.sh
#   ./install.sh --hooks claude
#   ./install.sh --hooks codex
#   ./install.sh --hooks both
#   ./install.sh --from-source

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.conduit/bin}"
HOOKS_MODE="none"
FROM_SOURCE="false"

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

if [[ "$FROM_SOURCE" == "true" ]]; then
  command -v go >/dev/null 2>&1 || { echo "go is required for --from-source" >&2; exit 1; }
  (cd "$SCRIPT_DIR" && go build -o "$TARGET" .)
elif [[ -x "$SCRIPT_DIR/conduitd" ]]; then
  cp "$SCRIPT_DIR/conduitd" "$TARGET"
else
  command -v go >/dev/null 2>&1 || { echo "No local binary found and go is unavailable" >&2; exit 1; }
  (cd "$SCRIPT_DIR" && go build -o "$TARGET" .)
fi

chmod 755 "$TARGET"

# Fail closed if we just installed a stale/incompatible binary. The pre-built
# copy path (cp $SCRIPT_DIR/conduitd) trusts whatever is on disk; an old Swift
# 0.1.0 build lacks the policy engine + resident `daemon` command, which would
# silently ship governance disabled. The Go build's usage banner lists it.
# conduitd with no args prints usage to stderr and exits 1 — capture the output
# first so the expected non-zero exit doesn't trip `set -o pipefail`.
USAGE_OUT="$("$TARGET" 2>&1 || true)"
if ! grep -q "conduitd daemon" <<<"$USAGE_OUT"; then
  echo "ERROR: installed conduitd lacks the 'daemon' command — it is a stale or" >&2
  echo "       incompatible build (no policy engine). Reinstall with --from-source." >&2
  rm -f "$TARGET"
  exit 1
fi

echo "Installed conduitd at $TARGET"
"$TARGET" version || true

install_claude_hook() {
  mkdir -p "$HOME/.claude/hooks"
  cp "$REPO_ROOT/docs/conduit-hook.sh" "$HOME/.claude/hooks/conduit-hook.sh"
  chmod 700 "$HOME/.claude/hooks/conduit-hook.sh"
  echo "Installed Claude hook: ~/.claude/hooks/conduit-hook.sh"
}

install_codex_hook() {
  mkdir -p "$HOME/.codex/hooks"
  cp "$REPO_ROOT/docs/codex-conduit-hook.sh" "$HOME/.codex/hooks/conduit-hook.sh"
  chmod 700 "$HOME/.codex/hooks/conduit-hook.sh"
  cp "$REPO_ROOT/docs/codex-hooks.json" "$HOME/.codex/hooks.json"
  chmod 600 "$HOME/.codex/hooks.json"
  echo "Installed Codex hook: ~/.codex/hooks/conduit-hook.sh"
}

case "$HOOKS_MODE" in
  none)
    ;;
  claude)
    install_claude_hook
    ;;
  codex)
    install_codex_hook
    ;;
  both)
    install_claude_hook
    install_codex_hook
    ;;
  *)
    echo "Invalid --hooks mode: $HOOKS_MODE (expected none|claude|codex|both)" >&2
    exit 1
    ;;
esac
