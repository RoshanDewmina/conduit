#!/usr/bin/env bash
# conduit-hook.sh — Claude Code PreToolUse hook for Conduit iOS approval
#
# Install on the remote server:
#   mkdir -p ~/.claude/hooks
#   cp conduit-hook.sh ~/.claude/hooks/conduit-hook.sh
#   chmod +x ~/.claude/hooks/conduit-hook.sh
#
# Wire in ~/.claude/settings.json — see docs/claude-settings-hook.json

CONDUITD="$HOME/.conduit/bin/conduitd"

# Read the hook payload from Claude Code
INPUT=$(cat)

# Parse tool name and the most relevant command/path string
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
cmd = (ti.get('command') or ti.get('file_path') or ti.get('path') or
       ti.get('description') or d.get('tool_name', 'unknown'))
print(str(cmd)[:500])
" 2>/dev/null || echo "$TOOL")

# Auto-approve read-only tools — no need to interrupt the user for these
case "$TOOL" in
  Read|Glob|Grep|LS|WebSearch|WebFetch|TodoRead|TodoWrite|NotebookRead)
    exit 0
    ;;
esac

# Map tool name to risk band and kind
case "$TOOL" in
  Bash)                   RISK="high";   KIND="command"  ;;
  Write|Edit|MultiEdit)   RISK="medium"; KIND="fileWrite" ;;
  Patch)                  RISK="medium"; KIND="patch"     ;;
  *)                      RISK="low";    KIND="command"   ;;
esac

# Send approval request to conduitd (which forwards it to the iOS app).
# If conduitd is not running (phone not connected), it auto-approves and exits 0.
# Exit 0 = Claude Code proceeds. Exit 2 = Claude Code sees the message and stops.

# Claude Code PreToolUse structured fields — use a bash array so values with
# spaces, quotes, or metacharacters in CLAUDE_TOOL_INPUT cannot inject extra flags.
EXTRA_ARGS=()
[ -n "${CLAUDE_TOOL_NAME:-}" ]   && EXTRA_ARGS+=(--tool-name="$CLAUDE_TOOL_NAME")
[ -n "${CLAUDE_TOOL_USE_ID:-}" ] && EXTRA_ARGS+=(--tool-use-id="$CLAUDE_TOOL_USE_ID")
[ -n "${CLAUDE_SESSION_ID:-}" ]  && EXTRA_ARGS+=(--session-id="$CLAUDE_SESSION_ID")
[ -n "${CLAUDE_TOOL_INPUT:-}" ]  && EXTRA_ARGS+=(--tool-input="$CLAUDE_TOOL_INPUT")

if "$CONDUITD" agent-hook \
  --agent "claudeCode" \
  --kind "$KIND" \
  --command "$COMMAND" \
  --cwd "$(pwd)" \
  --risk "$RISK" \
  "${EXTRA_ARGS[@]}"
then
  exit 0
else
  printf "Blocked by Conduit — action was rejected on the iOS app or timed out (120 s)."
  exit 2
fi
