#!/usr/bin/env bash
# OpenCode PreToolUse hook for Conduit iOS approval cards.
#
# OpenCode accepts Claude-compatible hook JSON on stdin (tool_name, tool_input,
# cwd, session_id). See docs/opencode-hooks.json.
#
# Install:
#   mkdir -p ~/.config/opencode/hooks
#   cp docs/opencode-conduit-hook.sh ~/.config/opencode/hooks/conduit-hook.sh
#   chmod 700 ~/.config/opencode/hooks/conduit-hook.sh
#
# Configure:
#   cp docs/opencode-hooks.json ~/.config/opencode/hooks.json

set -u

CONDUITD="${CONDUITD:-$HOME/.conduit/bin/conduitd}"
if [ ! -x "$CONDUITD" ] && [ -x "$HOME/conduitd" ]; then
  CONDUITD="$HOME/conduitd"
fi

INPUT="$(cat)"

PARSED="$(
  python3 -c '
import json
import os
import re
import sys

try:
    event = json.loads(sys.stdin.read() or "{}")
except Exception:
    event = {}

tool = str(event.get("tool_name") or event.get("tool") or "")
cwd = str(event.get("cwd") or os.getcwd())
tool_input = event.get("tool_input") or {}
if not isinstance(tool_input, dict):
    tool_input = {"value": tool_input}

def compact(value):
    try:
        return json.dumps(value, separators=(",", ":"), sort_keys=True)
    except Exception:
        return str(value)

def tool_command():
    if tool in {"Bash", "bash"}:
        return str(tool_input.get("command") or "")
    if tool in {"apply_patch", "Patch", "patch"}:
        return str(tool_input.get("command") or tool_input.get("patch") or compact(tool_input))
    if tool in {"Edit", "Write", "MultiEdit", "edit", "write", "multiedit"}:
        return str(
            tool_input.get("command")
            or tool_input.get("file_path")
            or tool_input.get("path")
            or compact(tool_input)
        )
    return str(
        tool_input.get("command")
        or tool_input.get("file_path")
        or tool_input.get("path")
        or tool
        or "unknown"
    )

command = tool_command()
tool_l = tool.lower()

read_only = {
    "read", "glob", "grep", "ls", "notebookread", "todowrite", "todoread",
    "websearch", "webfetch", "view_image",
}
if tool_l in read_only:
    print(json.dumps({"autoApprove": True}, separators=(",", ":")))
    sys.exit(0)

kind = "command"
if tool in {"Bash", "bash"}:
    kind = "command"
elif tool in {"apply_patch", "Patch", "patch", "Edit", "Write", "MultiEdit", "edit", "write", "multiedit"}:
    kind = "patch"

risk = "low"
if kind == "command" and tool in {"Bash", "bash"}:
    risk = "high"
elif kind == "patch":
    risk = "medium"

danger = re.compile(
    r"(?i)(rm\s+-rf|sudo\s+|chmod\s+-R|chown\s+-R|mkfs|dd\s+if=|curl\b.*\|\s*(sh|bash)|wget\b.*\|\s*(sh|bash))"
)
if danger.search(command):
    risk = "critical"

print(json.dumps({
    "tool": tool,
    "cwd": cwd,
    "kind": kind,
    "risk": risk,
    "command": command[:20000],
    "sessionId": str(event.get("session_id") or event.get("sessionId") or ""),
    "toolUseId": str(event.get("tool_use_id") or event.get("toolUseId") or ""),
    "toolInput": compact(tool_input),
}, separators=(",", ":")))
' <<<"$INPUT"
)"

json_get() {
  python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1" <<<"$PARSED"
}

if [ ! -x "$CONDUITD" ]; then
  printf '%s\n' "Conduit daemon not installed; auto-approving OpenCode tool call." >&2
  exit 0
fi

KIND="$(json_get kind)"
RISK="$(json_get risk)"
CWD="$(json_get cwd)"
COMMAND="$(json_get command)"
SESSION_ID="$(json_get sessionId)"
TOOL_USE_ID="$(json_get toolUseId)"
TOOL_INPUT="$(json_get toolInput)"

EXTRA=()
if [ -n "$SESSION_ID" ]; then
  EXTRA+=(--session-id "$SESSION_ID")
fi
TOOL_NAME="$(json_get tool)"
if [ -n "$TOOL_USE_ID" ]; then
  EXTRA+=(--tool-use-id "$TOOL_USE_ID")
fi
if [ -n "$TOOL_INPUT" ]; then
  EXTRA+=(--tool-input "$TOOL_INPUT")
fi
if [ -n "$TOOL_NAME" ]; then
  EXTRA+=(--tool-name "$TOOL_NAME")
fi

if "$CONDUITD" agent-hook \
  --agent opencode \
  --kind "$KIND" \
  --command "$COMMAND" \
  --cwd "$CWD" \
  --risk "$RISK" \
  "${EXTRA[@]}"
then
  exit 0
fi

printf '%s\n' "Blocked by Conduit: OpenCode action was rejected on the iOS app or timed out." >&2
exit 2
