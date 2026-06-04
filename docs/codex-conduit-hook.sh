#!/usr/bin/env bash
# Codex PreToolUse hook for Conduit approval cards.
#
# Install:
#   mkdir -p ~/.codex/hooks
#   cp docs/codex-conduit-hook.sh ~/.codex/hooks/conduit-hook.sh
#   chmod 700 ~/.codex/hooks/conduit-hook.sh
#
# Configure:
#   cp docs/codex-hooks.json ~/.codex/hooks.json
#   Run /hooks in Codex and trust the hook definition.

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
from datetime import datetime, timezone

payload = sys.stdin.read()
try:
    event = json.loads(payload or "{}")
except Exception:
    event = {}

tool = str(event.get("tool_name") or "")
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
    if tool == "Bash":
        return str(tool_input.get("command") or "")
    if tool == "apply_patch":
        return str(tool_input.get("command") or tool_input.get("patch") or compact(tool_input))
    if tool in {"Edit", "Write", "MultiEdit"}:
        return str(tool_input.get("command") or tool_input.get("file_path") or tool_input.get("path") or compact(tool_input))
    if tool.startswith("mcp__"):
        return compact(tool_input)
    return str(tool_input.get("command") or tool_input.get("file_path") or tool_input.get("path") or tool or "unknown")

command = tool_command()
tool_l = tool.lower()
mcp_leaf = tool_l.split("__")[-1] if tool_l.startswith("mcp__") else tool_l

read_only_tools = {
    "read", "glob", "grep", "ls", "notebookread", "todowrite", "todoread",
    "websearch", "webfetch", "view_image"
}
read_only_mcp = (
    "read", "get", "list", "search", "find", "stat", "describe",
    "screenshot", "query", "inspect", "show"
)
write_mcp = (
    "write", "edit", "create", "mkdir", "move", "rename", "delete",
    "remove", "patch", "upload", "insert", "update", "replace"
)

auto_approve = tool_l in {t.lower() for t in read_only_tools}
if tool_l.startswith("mcp__") and mcp_leaf.startswith(read_only_mcp):
    auto_approve = True

kind = "command"
if tool == "Bash":
    kind = "command"
elif tool in {"apply_patch", "Edit", "Write", "MultiEdit"}:
    kind = "patch"
elif tool_l.startswith("mcp__"):
    if mcp_leaf.startswith(("delete", "remove", "unlink")):
        kind = "fileDelete"
    elif mcp_leaf.startswith(write_mcp):
        kind = "fileWrite"
    elif any(part in mcp_leaf for part in ("browser", "tap", "click", "type", "press", "navigate")):
        kind = "browser"
    elif any(part in mcp_leaf for part in ("http", "network", "fetch", "request", "url")):
        kind = "network"

danger = re.compile(r"(?i)(rm\s+-rf|sudo\s+|chmod\s+-R|chown\s+-R|mkfs|dd\s+if=|curl\b.*\|\s*(sh|bash)|wget\b.*\|\s*(sh|bash))")
risk = "low"
if kind == "command":
    risk = "high" if tool == "Bash" else "medium"
if kind in {"patch", "fileWrite", "fileDelete"}:
    risk = "medium"
if kind == "browser":
    risk = "medium"
if danger.search(command):
    risk = "critical"

def redact(text):
    text = re.sub(r"sk-[A-Za-z0-9_-]{16,}", "sk-REDACTED", text)
    text = re.sub(
        r"(?i)(api[_-]?key|token|secret|password)([\"'"'"'=: ]+)([^\"'"'"'\s,}]+)",
        r"\1\2REDACTED",
        text,
    )
    return text[:2000]

log_event = {
    "captured_at": datetime.now(timezone.utc).isoformat(),
    "hook_event_name": event.get("hook_event_name"),
    "permission_mode": event.get("permission_mode"),
    "tool_name": tool,
    "tool_use_id": event.get("tool_use_id"),
    "cwd": cwd,
    "kind": kind,
    "risk": risk,
    "command": redact(command),
}
try:
    log_dir = os.path.expanduser("~/.conduit")
    os.makedirs(log_dir, mode=0o700, exist_ok=True)
    with open(os.path.join(log_dir, "codex-hook-events.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(log_event, separators=(",", ":"), sort_keys=True) + "\n")
except Exception:
    pass

print(json.dumps({
    "autoApprove": auto_approve,
    "tool": tool,
    "cwd": cwd,
    "kind": kind,
    "risk": risk,
    "command": command[:20000],
}, separators=(",", ":")))
' <<<"$INPUT"
)"

json_get() {
  python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1" <<<"$PARSED"
}

AUTO_APPROVE="$(json_get autoApprove)"
if [ "$AUTO_APPROVE" = "True" ] || [ "$AUTO_APPROVE" = "true" ]; then
  exit 0
fi

if [ ! -x "$CONDUITD" ]; then
  printf '%s\n' "Conduit daemon not installed at ~/.conduit/bin/conduitd; auto-approving Codex tool call." >&2
  exit 0
fi

KIND="$(json_get kind)"
RISK="$(json_get risk)"
CWD="$(json_get cwd)"
COMMAND="$(json_get command)"

# Codex PreToolUse hook env vars (present when running inside Codex)
TOOL_NAME_ARG=""
TOOL_USE_ID_ARG=""
SESSION_ID_ARG=""
TOOL_INPUT_ARG=""
[ -n "${CODEX_TOOL_NAME:-}" ]   && TOOL_NAME_ARG="--tool-name=$CODEX_TOOL_NAME"
[ -n "${CODEX_TOOL_USE_ID:-}" ] && TOOL_USE_ID_ARG="--tool-use-id=$CODEX_TOOL_USE_ID"
[ -n "${CODEX_SESSION_ID:-}" ]  && SESSION_ID_ARG="--session-id=$CODEX_SESSION_ID"
[ -n "${CODEX_TOOL_INPUT:-}" ]  && TOOL_INPUT_ARG="--tool-input=$CODEX_TOOL_INPUT"

if "$CONDUITD" agent-hook \
  --agent codex \
  --kind "$KIND" \
  --command "$COMMAND" \
  --cwd "$CWD" \
  --risk "$RISK" \
  $TOOL_NAME_ARG $TOOL_USE_ID_ARG $SESSION_ID_ARG $TOOL_INPUT_ARG
then
  exit 0
fi

printf '%s\n' "Blocked by Conduit: Codex action was rejected on the iOS app or timed out." >&2
exit 2
