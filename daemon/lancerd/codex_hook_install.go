package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Codex supports the same hooks.json + PreToolUse-command shape Claude Code
// does (verified 2026-07-18 against codex-cli 0.135.0 and re-checked against
// 0.144.6: ~/.codex/hooks.json already contains a working conduit-hook.sh
// PreToolUse entry). Unlike Claude, Codex also gates on a separate, persisted
// "hook trust" record in ~/.codex/config.toml under [hooks.state] — an
// untrusted hook entry is silently skipped by Codex even though it is present
// in hooks.json, so codexHookWired below must check BOTH. Canonical copies:
// docs/codex-hooks.json and docs/codex-lancer-hook.sh.
//
// Live-verified 2026-07-18 against codex-cli 0.144.6 in an isolated
// CODEX_HOME/HOME (never touched the owner's real ~/.codex):
//   - With the Lancer entry present in hooks.json but NO config.toml trust
//     record (codexHookWired = false), `codex exec --json -s workspace-write
//     "create a file named probe.txt containing hi"` completed the file
//     write directly — the hook script never ran (no line appended to
//     ~/.lancer/codex-hook-events.jsonl). Confirms an untrusted hook is
//     silently skipped, exactly as this file assumes.
//   - Re-run with `--dangerously-bypass-hook-trust` (verification only —
//     never used outside this test, per the hard constraint against using it
//     on production paths): the hook DID fire, logged the apply_patch event
//     correctly, resolved $LANCERD to the installed shim, dialed the
//     (non-running) daemon socket, and — because it couldn't reach it — held
//     the mutating action fail-closed ("Blocked by Lancer: Codex action was
//     rejected on the iOS app or timed out."), exactly matching
//     docs/lancer-hook.sh's (Claude) fail-closed behavior. This is the
//     strongest available evidence that the fail-open regression removed
//     from docs/codex-lancer-hook.sh (the old "lancerd missing -> exit 0"
//     branch) would otherwise have auto-approved a mutating action.

// codexHookCommand is the command string Lancer registers in the Codex
// PreToolUse hook block. Must match docs/codex-hooks.json verbatim.
const codexHookCommand = "bash ~/.codex/hooks/lancer-hook.sh"

// codexHookMatcher scopes the hook to the tool set that can mutate state or
// touch the network, mirroring docs/codex-hooks.json. Unlike Claude's empty
// ("") matcher (which fires on every tool), Codex's PreToolUse config expects
// a matcher regex.
const codexHookMatcher = "Bash|apply_patch|Edit|Write|mcp__.*"

// codexHookTimeoutSeconds/codexHookStatusMessage mirror the extra fields
// docs/codex-hooks.json sets on the hook entry (Codex-specific; Claude's
// hooks.json shape has no equivalent).
const codexHookTimeoutSeconds = 150
const codexHookStatusMessage = "Waiting for Lancer approval"

// codexHookScript is the PreToolUse hook `lancerd install` drops to
// ~/.codex/hooks/lancer-hook.sh. Keep the body (from the LANCER_GATE guard
// onward) byte-for-byte in sync with docs/codex-lancer-hook.sh — only the
// header comment differs, same convention as claudeHookScript vs
// docs/lancer-hook.sh.
const codexHookScript = `#!/usr/bin/env bash
# lancer-hook.sh — Codex PreToolUse hook for Lancer iOS approval
#
# Installed by ` + "`lancerd install`" + ` and configured into ~/.codex/hooks.json.
# Canonical copy: docs/codex-lancer-hook.sh

# This hook is registered globally, but only runs when launched by lancerd
# opt-in. Never route an owner's ordinary interactive Codex session through
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
    with open(os.path.join(log_dir, "codex-hook-events.jsonl"), "a", encoding="utf-8") as f:
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
# Codex delivers all PreToolUse data on stdin as JSON — never via env vars.
EXTRA_ARGS=()
[ -n "$TOOL_NAME" ]                              && EXTRA_ARGS+=(--tool-name="$TOOL_NAME")
[ -n "$TOOL_USE_ID" ]                            && EXTRA_ARGS+=(--tool-use-id="$TOOL_USE_ID")
[ -n "$SESSION_ID" ]                             && EXTRA_ARGS+=(--session-id="$SESSION_ID")
[ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "{}" ] && EXTRA_ARGS+=(--tool-input="$TOOL_INPUT")

# No "lancerd missing/unreachable" short-circuit here: if $LANCERD is not
# executable, the call below fails naturally (command not found) and falls
# into the ` + "`printf ... ; exit 2`" + ` branch below — fail-closed, matching
# docs/lancer-hook.sh (Claude) exactly. An earlier draft of this script
# auto-approved when lancerd was missing; that was a fail-open regression
# and has been removed.
if "$LANCERD" agent-hook \
  --agent codex \
  --kind "$KIND" \
  --command "$COMMAND" \
  --cwd "$CWD" \
  --risk "$RISK" \
  "${EXTRA_ARGS[@]}"
then
  exit 0
fi

printf '%s\n' "Blocked by Lancer: Codex action was rejected on the iOS app or timed out." >&2
exit 2
`

// codexHooksJSONPath returns ~/.codex/hooks.json for the given home.
func codexHooksJSONPath(home string) string {
	return filepath.Join(home, ".codex", "hooks.json")
}

// codexHookScriptPath returns ~/.codex/hooks/lancer-hook.sh for the given home.
func codexHookScriptPath(home string) string {
	return filepath.Join(home, ".codex", "hooks", "lancer-hook.sh")
}

// codexConfigTomlPath returns ~/.codex/config.toml for the given home, where
// Codex persists per-hook trust state under [hooks.state].
func codexConfigTomlPath(home string) string {
	return filepath.Join(home, ".codex", "config.toml")
}

// codexHookHooksBlock is the JSON shape of a single Codex PreToolUse matcher
// entry (mirrors Claude's shape plus Codex-specific timeout/statusMessage
// fields — see docs/codex-hooks.json).
type codexHookEntry struct {
	Type          string `json:"type"`
	Command       string `json:"command"`
	Timeout       int    `json:"timeout,omitempty"`
	StatusMessage string `json:"statusMessage,omitempty"`
}

type codexHookMatcherBlock struct {
	Matcher string           `json:"matcher"`
	Hooks   []codexHookEntry `json:"hooks"`
}

// findCodexHookIndex locates the Lancer hook command inside a parsed
// hooks.json PreToolUse array, returning its (matcher, hook) position. Codex
// records trust per-position (see codexHookTrustKey), so the caller needs the
// exact index the entry currently lives at — not just presence/absence.
func findCodexHookIndex(matchers []codexHookMatcherBlock, cmd string) (matcherIdx, hookIdx int, found bool) {
	for mi, m := range matchers {
		for hi, h := range m.Hooks {
			if h.Command == cmd {
				return mi, hi, true
			}
		}
	}
	return 0, 0, false
}

// parseCodexHooksJSON reads and decodes ~/.codex/hooks.json. A missing or
// empty file reads as "no matchers" so callers treat it as not-yet-wired
// rather than erroring.
func parseCodexHooksJSON(path string) ([]codexHookMatcherBlock, map[string]json.RawMessage, error) {
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
	var matchers []codexHookMatcherBlock
	if hooks != nil {
		if raw, ok := hooks["PreToolUse"]; ok {
			_ = json.Unmarshal(raw, &matchers)
		}
	}
	return matchers, root, nil
}

// mergeCodexHookEntry appends the Lancer PreToolUse matcher block to an
// existing Codex hooks.json root, preserving every existing key and matcher
// (never clobbering or reordering the conduit-hook.sh entry). If the command
// is already registered, the input is returned unchanged with changed=false.
func mergeCodexHookEntry(root map[string]json.RawMessage, matchers []codexHookMatcherBlock, cmd string) (map[string]json.RawMessage, bool) {
	if root == nil {
		root = map[string]json.RawMessage{}
	}
	if _, _, found := findCodexHookIndex(matchers, cmd); found {
		return root, false
	}

	matchers = append(matchers, codexHookMatcherBlock{
		Matcher: codexHookMatcher,
		Hooks: []codexHookEntry{{
			Type:          "command",
			Command:       cmd,
			Timeout:       codexHookTimeoutSeconds,
			StatusMessage: codexHookStatusMessage,
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

// wireCodexHookJSON idempotently merges the Lancer PreToolUse hook into
// ~/.codex/hooks.json. A missing or empty file is created; an existing file
// has all its keys and matchers preserved (in particular, the conduit-hook.sh
// entry). The write is atomic (temp file + rename), reusing the same
// atomicWriteFile helper as Claude's wireClaudeHookSettings.
func wireCodexHookJSON(home string) (changed bool, err error) {
	path := codexHooksJSONPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return false, err
	}

	matchers, root, err := parseCodexHooksJSON(path)
	if err != nil {
		return false, err
	}
	merged, changed := mergeCodexHookEntry(root, matchers, codexHookCommand)
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

// installCodexHook drops the PreToolUse hook script to ~/.codex/hooks and
// idempotently wires it into ~/.codex/hooks.json. It does NOT grant hook
// trust — Codex's trust model (see codexHookTrusted) is a persisted,
// owner-driven record in config.toml, and this repo never calls
// --dangerously-bypass-hook-trust or otherwise auto-trusts a hook. Until the
// owner runs Codex and trusts the entry (e.g. via /hooks), codexHookWired
// stays false and relaxLaunchEscalation keeps Codex on the coarse launch gate.
func installCodexHook(home string) error {
	scriptPath := codexHookScriptPath(home)
	if err := os.MkdirAll(filepath.Dir(scriptPath), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(scriptPath, []byte(codexHookScript), 0755); err != nil {
		return fmt.Errorf("write codex hook script: %w", err)
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\n", scriptPath)

	changed, err := wireCodexHookJSON(home)
	if err != nil {
		return err
	}
	if changed {
		fmt.Fprintf(os.Stderr, "Registered Lancer PreToolUse hook in %s\n", codexHooksJSONPath(home))
		fmt.Fprintln(os.Stderr, "  Owner step required: run codex, then /hooks, and trust the lancer-hook entry —")
		fmt.Fprintln(os.Stderr, "  until trusted, Codex dispatches still escalate through the coarse launch gate.")
	} else {
		fmt.Fprintf(os.Stderr, "Lancer PreToolUse hook already registered in %s\n", codexHooksJSONPath(home))
	}
	return nil
}

// codexHookTrustKeyPattern matches a [hooks.state."<key>"] TOML section
// header so codexHookTrusted can locate the trust record for a specific
// hooks.json entry without a full TOML parser (config.toml has no
// multi-line-array or nested-table content inside a hooks.state block, so a
// line-scoped scan is sufficient and avoids adding a TOML dependency for one
// narrow read).
var codexHookTrustKeyPattern = regexp.MustCompile(`^\[hooks\.state\."([^"]*)"\]\s*$`)

// codexHookTrustKey builds the exact [hooks.state."..."] key Codex persists
// for a given hooks.json path + PreToolUse matcher/hook index, matching the
// format observed live in ~/.codex/config.toml on 2026-07-18 (codex-cli
// 0.135.0, re-confirmed against 0.144.6):
//
//	[hooks.state."/Users/roshansilva/.codex/hooks.json:pre_tool_use:0:0"]
//	trusted_hash = "sha256:..."
//	enabled = false
func codexHookTrustKey(hooksJSONPath string, matcherIdx, hookIdx int) string {
	return fmt.Sprintf("%s:pre_tool_use:%d:%d", hooksJSONPath, matcherIdx, hookIdx)
}

// codexHookTrustEnabled scans config.toml text for the given [hooks.state]
// key and reports whether its "enabled" field is exactly "true". A missing
// key, missing file, or enabled=false all read as untrusted (fail-closed) —
// this deliberately does not attempt to validate trusted_hash, since its
// hash preimage/algorithm is a Codex internal not documented anywhere we
// found; presence of an enabled=true record for the exact key is the
// strongest signal available without one.
func codexHookTrustEnabled(configTomlPath, key string) bool {
	data, err := os.ReadFile(configTomlPath)
	if err != nil {
		return false
	}
	lines := strings.Split(string(data), "\n")
	inSection := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "[") {
			m := codexHookTrustKeyPattern.FindStringSubmatch(trimmed)
			inSection = m != nil && m[1] == key
			continue
		}
		if !inSection {
			continue
		}
		if eq := strings.Index(trimmed, "="); eq >= 0 {
			field := strings.TrimSpace(trimmed[:eq])
			value := strings.TrimSpace(trimmed[eq+1:])
			if field == "enabled" {
				return value == "true"
			}
		}
	}
	return false
}

// codexHookWired reports whether the Lancer PreToolUse hook is BOTH
// registered in hooks.json AND trusted (enabled=true) in config.toml. Only
// the JSON entry is something `lancerd install` can write; trust is a
// persisted, owner-driven Codex record this code never grants — see
// installCodexHook. An untrusted hook that Codex silently skips while Lancer
// relaxed launch escalation would be a security regression, so both signals
// are required before hookWiredForAgent treats codex as gated.
func codexHookWired(home string) bool {
	hooksPath := codexHooksJSONPath(home)
	matchers, _, err := parseCodexHooksJSON(hooksPath)
	if err != nil {
		return false
	}
	matcherIdx, hookIdx, found := findCodexHookIndex(matchers, codexHookCommand)
	if !found {
		return false
	}
	key := codexHookTrustKey(hooksPath, matcherIdx, hookIdx)
	return codexHookTrustEnabled(codexConfigTomlPath(home), key)
}
