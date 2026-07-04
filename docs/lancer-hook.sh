#!/usr/bin/env bash
# lancer-hook.sh — Claude Code PreToolUse hook for Lancer iOS approval
#
# Install on the remote server:
#   mkdir -p ~/.claude/hooks
#   cp lancer-hook.sh ~/.claude/hooks/lancer-hook.sh
#   chmod +x ~/.claude/hooks/lancer-hook.sh
#
# Wire in ~/.claude/settings.json — see docs/claude-settings-hook.json

# This hook is registered globally, but only runs launched by lancerd opt in.
# Never route an owner's ordinary interactive Claude session through Lancer.
if [[ "${LANCER_GATE:-}" != "1" ]]; then
  exit 0
fi

LANCERD="${LANCERD:-$HOME/.lancer/bin/lancerd}"

# Read the hook payload from Claude Code
INPUT=$(cat)

# Parse tool name, structured fields, and the most relevant command/path string.
# Claude Code delivers all PreToolUse data on stdin as JSON — never via env vars.
IFS=$'\t' read -r TOOL_NAME TOOL_USE_ID SESSION_ID TOOL_INPUT COMMAND < <(
  echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input') or {}
if not isinstance(ti, dict):
    ti = {'value': ti}
tool_name   = str(d.get('tool_name', ''))
tool_use_id = str(d.get('tool_use_id', '') or '')
session_id  = str(d.get('session_id', '') or '')
tool_input  = json.dumps(ti, separators=(',', ':'))
cmd = (ti.get('command') or ti.get('file_path') or ti.get('path') or
       ti.get('description') or tool_name or 'unknown')
print('\t'.join([tool_name, tool_use_id, session_id, tool_input, str(cmd)[:500]]))
" 2>/dev/null || echo -e "\t\t\t{}\t${TOOL_NAME:-unknown}"
)
TOOL="$TOOL_NAME"

# Auto-approve read-only tools — no need to interrupt the user for these
case "$TOOL" in
  Read|Glob|Grep|LS|WebSearch|WebFetch|TodoRead|TodoWrite|NotebookRead)
    exit 0
    ;;
esac

# Agent question tools — escalate as askQuestion (not a mutating command).
case "$TOOL" in
  AskUserQuestion|AskQuestion|ask_user|question)
    QUESTION_ARGS=()
    [ -n "$TOOL_NAME" ]                              && QUESTION_ARGS+=(--tool-name="$TOOL_NAME")
    [ -n "$TOOL_USE_ID" ]                            && QUESTION_ARGS+=(--tool-use-id="$TOOL_USE_ID")
    [ -n "$SESSION_ID" ]                             && QUESTION_ARGS+=(--session-id="$SESSION_ID")
    [ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "{}" ] && QUESTION_ARGS+=(--tool-input="$TOOL_INPUT")
    if "$LANCERD" agent-hook \
      --agent "claudeCode" \
      --kind "askQuestion" \
      --command "$COMMAND" \
      --cwd "$(pwd)" \
      --risk "low" \
      --question "$COMMAND" \
      "${QUESTION_ARGS[@]}"
    then
      exit 0
    else
      printf "Blocked by Lancer — question was not answered on the iOS app."
      exit 2
    fi
    ;;
esac

# Map tool name to risk band and kind
case "$TOOL" in
  Bash)                   RISK="high";   KIND="command"  ;;
  Write|Edit|MultiEdit)   RISK="medium"; KIND="fileWrite" ;;
  Patch)                  RISK="medium"; KIND="patch"     ;;
  *)                      RISK="low";    KIND="command"   ;;
esac

# Send approval request to lancerd (which forwards it to the iOS app).
# If lancerd is not running (phone not connected), it auto-approves and exits 0.
# Exit 0 = Claude Code proceeds. Exit 2 = Claude Code sees the message and stops.

# Build structured-field args from stdin-parsed values (bash array prevents
# injection of extra flags by values containing spaces, quotes, or metacharacters).
EXTRA_ARGS=()
[ -n "$TOOL_NAME" ]                              && EXTRA_ARGS+=(--tool-name="$TOOL_NAME")
[ -n "$TOOL_USE_ID" ]                            && EXTRA_ARGS+=(--tool-use-id="$TOOL_USE_ID")
[ -n "$SESSION_ID" ]                             && EXTRA_ARGS+=(--session-id="$SESSION_ID")
[ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "{}" ] && EXTRA_ARGS+=(--tool-input="$TOOL_INPUT")

if "$LANCERD" agent-hook \
  --agent "claudeCode" \
  --kind "$KIND" \
  --command "$COMMAND" \
  --cwd "$(pwd)" \
  --risk "$RISK" \
  "${EXTRA_ARGS[@]}"
then
  exit 0
else
  printf "Blocked by Lancer — action was rejected on the iOS app or timed out (120 s)."
  exit 2
fi
