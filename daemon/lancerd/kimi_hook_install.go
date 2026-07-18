package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Kimi 0.18.0's ~/.kimi-code/hooks.json already contains a working
// conduit-hook.sh PreToolUse entry, using the same shape Claude Code and
// Codex use (verified 2026-07-18). Live-firing the Lancer hook could not be
// smoke-tested this session: `kimi --prompt ... --output-format stream-json`
// returns provider.api_error: 402 (membership) — an account/billing issue,
// not something this code can fix. This file lands the install/wiring
// machinery and lets `doctor` report state, but deliberately does NOT plug
// kimiHookWired into hookWiredForAgent (server.go keeps kimi in the
// `default: false` branch) until a live-fire proof exists. Canonical copies:
// docs/kimi-hooks.json and docs/kimi-lancer-hook.sh.

// kimiHookCommand is the command string Lancer registers in the Kimi
// PreToolUse hook block. Must match docs/kimi-hooks.json verbatim.
const kimiHookCommand = "bash ~/.kimi-code/hooks/lancer-hook.sh"

// kimiHookMatcher mirrors codexHookMatcher — see docs/kimi-hooks.json.
const kimiHookMatcher = "Bash|apply_patch|Edit|Write|mcp__.*"

const kimiHookTimeoutSeconds = 150
const kimiHookStatusMessage = "Waiting for Lancer approval"

// kimiHookScript is the PreToolUse hook `lancerd install` drops to
// ~/.kimi-code/hooks/lancer-hook.sh. Keep the body (from the LANCER_GATE
// guard onward) byte-for-byte in sync with docs/kimi-lancer-hook.sh — same
// convention as codexHookScript vs docs/codex-lancer-hook.sh.
const kimiHookScript = `#!/usr/bin/env bash
# lancer-hook.sh — Kimi PreToolUse hook for Lancer iOS approval
#
# Installed by ` + "`lancerd install`" + ` and configured into ~/.kimi-code/hooks.json.
# Canonical copy: docs/kimi-lancer-hook.sh
#
# Kimi's hook-trust UX (if any) has not been live-verified — kimiHookWired is
# intentionally NOT wired into hookWiredForAgent, so relaxLaunchEscalation
# never trusts Kimi regardless of what this script or hooks.json say.

# This hook is registered globally, but only runs when launched by lancerd
# opt-in. Never route an owner's ordinary interactive Kimi session through
# Lancer.
if [[ "${LANCER_GATE:-}" != "1" ]]; then
  exit 0
fi

set -u

LANCERD="${LANCERD:-$HOME/.lancer/bin/lancerd}"
if [ ! -x "$LANCERD" ] && [ -x "$HOME/lancerd" ]; then
  LANCERD="$HOME/lancerd"
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
    log_dir = os.path.expanduser("~/.lancer")
    os.makedirs(log_dir, mode=0o700, exist_ok=True)
    with open(os.path.join(log_dir, "kimi-hook-events.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(log_event, separators=(",", ":"), sort_keys=True) + "\n")
except Exception:
    pass

tool_use_id = str(event.get("tool_use_id") or "")
session_id  = str(event.get("session_id") or "")
tool_input_json = json.dumps(tool_input, separators=(",", ":"), sort_keys=True)

print(json.dumps({
    "autoApprove": auto_approve,
    "tool": tool,
    "cwd": cwd,
    "kind": kind,
    "risk": risk,
    "command": command[:20000],
    "tool_use_id": tool_use_id,
    "session_id": session_id,
    "tool_input_json": tool_input_json,
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

KIND="$(json_get kind)"
RISK="$(json_get risk)"
CWD="$(json_get cwd)"
COMMAND="$(json_get command)"
TOOL_NAME="$(json_get tool)"
TOOL_USE_ID="$(json_get tool_use_id)"
SESSION_ID="$(json_get session_id)"
TOOL_INPUT="$(json_get tool_input_json)"

# Build structured-field args from stdin-parsed values (bash array prevents
# injection of extra flags by values containing spaces, quotes, or metacharacters).
# Kimi delivers all PreToolUse data on stdin as JSON — never via env vars.
EXTRA_ARGS=()
[ -n "$TOOL_NAME" ]                              && EXTRA_ARGS+=(--tool-name="$TOOL_NAME")
[ -n "$TOOL_USE_ID" ]                            && EXTRA_ARGS+=(--tool-use-id="$TOOL_USE_ID")
[ -n "$SESSION_ID" ]                             && EXTRA_ARGS+=(--session-id="$SESSION_ID")
[ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "{}" ] && EXTRA_ARGS+=(--tool-input="$TOOL_INPUT")

# No "lancerd missing/unreachable" short-circuit here — fail-closed, matching
# docs/lancer-hook.sh (Claude) and docs/codex-lancer-hook.sh exactly.
if "$LANCERD" agent-hook \
  --agent kimi \
  --kind "$KIND" \
  --command "$COMMAND" \
  --cwd "$CWD" \
  --risk "$RISK" \
  "${EXTRA_ARGS[@]}"
then
  exit 0
fi

printf '%s\n' "Blocked by Lancer: Kimi action was rejected on the iOS app or timed out." >&2
exit 2
`

// kimiHooksJSONPath returns ~/.kimi-code/hooks.json for the given home.
func kimiHooksJSONPath(home string) string {
	return filepath.Join(home, ".kimi-code", "hooks.json")
}

// kimiHookScriptPath returns ~/.kimi-code/hooks/lancer-hook.sh for the given home.
func kimiHookScriptPath(home string) string {
	return filepath.Join(home, ".kimi-code", "hooks", "lancer-hook.sh")
}

// kimiHookMatcherBlock/kimiHookEntry mirror codex's hooks.json shape.
type kimiHookEntry struct {
	Type          string `json:"type"`
	Command       string `json:"command"`
	Timeout       int    `json:"timeout,omitempty"`
	StatusMessage string `json:"statusMessage,omitempty"`
}

type kimiHookMatcherBlock struct {
	Matcher string          `json:"matcher"`
	Hooks   []kimiHookEntry `json:"hooks"`
}

func findKimiHookIndex(matchers []kimiHookMatcherBlock, cmd string) (matcherIdx, hookIdx int, found bool) {
	for mi, m := range matchers {
		for hi, h := range m.Hooks {
			if h.Command == cmd {
				return mi, hi, true
			}
		}
	}
	return 0, 0, false
}

// parseKimiHooksJSON mirrors parseCodexHooksJSON: a missing/empty file reads
// as "no matchers" (not-yet-wired) rather than erroring.
func parseKimiHooksJSON(path string) ([]kimiHookMatcherBlock, map[string]json.RawMessage, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, map[string]json.RawMessage{}, nil
		}
		return nil, nil, err
	}
	if len(data) == 0 {
		return nil, map[string]json.RawMessage{}, nil
	}
	var root map[string]json.RawMessage
	if err := json.Unmarshal(data, &root); err != nil {
		return nil, nil, fmt.Errorf("parse %s: %w", path, err)
	}
	var hooks map[string]json.RawMessage
	if raw, ok := root["hooks"]; ok {
		_ = json.Unmarshal(raw, &hooks)
	}
	var matchers []kimiHookMatcherBlock
	if hooks != nil {
		if raw, ok := hooks["PreToolUse"]; ok {
			_ = json.Unmarshal(raw, &matchers)
		}
	}
	return matchers, root, nil
}

// mergeKimiHookEntry appends the Lancer PreToolUse matcher block, preserving
// every existing key and matcher (never clobbering the conduit-hook.sh
// entry). If the command is already registered, returns changed=false.
func mergeKimiHookEntry(root map[string]json.RawMessage, matchers []kimiHookMatcherBlock, cmd string) (map[string]json.RawMessage, bool) {
	if root == nil {
		root = map[string]json.RawMessage{}
	}
	if _, _, found := findKimiHookIndex(matchers, cmd); found {
		return root, false
	}

	matchers = append(matchers, kimiHookMatcherBlock{
		Matcher: kimiHookMatcher,
		Hooks: []kimiHookEntry{{
			Type:          "command",
			Command:       cmd,
			Timeout:       kimiHookTimeoutSeconds,
			StatusMessage: kimiHookStatusMessage,
		}},
	})

	hooks := map[string]json.RawMessage{}
	if raw, ok := root["hooks"]; ok {
		_ = json.Unmarshal(raw, &hooks)
		if hooks == nil {
			hooks = map[string]json.RawMessage{}
		}
	}
	preRaw, _ := json.Marshal(matchers)
	hooks["PreToolUse"] = preRaw
	hooksRaw, _ := json.Marshal(hooks)
	root["hooks"] = hooksRaw
	return root, true
}

// wireKimiHookJSON idempotently merges the Lancer PreToolUse hook into
// ~/.kimi-code/hooks.json, atomically (temp file + rename).
func wireKimiHookJSON(home string) (changed bool, err error) {
	path := kimiHooksJSONPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return false, err
	}

	matchers, root, err := parseKimiHooksJSON(path)
	if err != nil {
		return false, err
	}
	merged, changed := mergeKimiHookEntry(root, matchers, kimiHookCommand)
	if !changed {
		return false, nil
	}

	out, err := json.MarshalIndent(merged, "", "  ")
	if err != nil {
		return false, err
	}
	out = append(out, '\n')
	if err := atomicWriteFile(path, out, 0644); err != nil {
		return false, err
	}
	return true, nil
}

// installKimiHook drops the PreToolUse hook script to ~/.kimi-code/hooks and
// idempotently wires it into ~/.kimi-code/hooks.json. This is install-only:
// it does not, and cannot, grant kimiHookWired = true — see the package doc
// comment. `doctor` uses kimiHookWired to report "installed but UNVERIFIED".
func installKimiHook(home string) error {
	scriptPath := kimiHookScriptPath(home)
	if err := os.MkdirAll(filepath.Dir(scriptPath), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(scriptPath, []byte(kimiHookScript), 0755); err != nil {
		return fmt.Errorf("write kimi hook script: %w", err)
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\n", scriptPath)

	changed, err := wireKimiHookJSON(home)
	if err != nil {
		return err
	}
	if changed {
		fmt.Fprintf(os.Stderr, "Registered Lancer PreToolUse hook in %s\n", kimiHooksJSONPath(home))
		fmt.Fprintln(os.Stderr, "  Kimi launches still escalate through the coarse launch gate — per-action")
		fmt.Fprintln(os.Stderr, "  approval for Kimi has not been live-fire verified (see docs/CHANGELOG.md).")
	} else {
		fmt.Fprintf(os.Stderr, "Lancer PreToolUse hook already registered in %s\n", kimiHooksJSONPath(home))
	}
	return nil
}

// kimiHookInstalled reports whether the hook script AND hooks.json entry are
// both present, for doctor's "installed but unverified" status. This is
// deliberately weaker than codexHookWired's trust check — Kimi has no
// verified trust mechanism to check, and hookWiredForAgent never calls this;
// it exists only so doctor can distinguish "not installed" from "installed,
// still fail-closed by design".
func kimiHookInstalled(home string) bool {
	if _, err := os.Stat(kimiHookScriptPath(home)); err != nil {
		return false
	}
	matchers, _, err := parseKimiHooksJSON(kimiHooksJSONPath(home))
	if err != nil {
		return false
	}
	_, _, found := findKimiHookIndex(matchers, kimiHookCommand)
	return found
}
