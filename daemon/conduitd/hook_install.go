package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Hook wiring lives in each agent's settings.json under hooks.PreToolUse. The
// exact shape Conduit expects is documented in docs/claude-settings-hook.json
// (and docs/opencode-hooks.json for OpenCode).

// claudeHookCommand is the command string Conduit registers in the PreToolUse
// hook block. Must match docs/claude-settings-hook.json verbatim.
const claudeHookCommand = "bash ~/.claude/hooks/conduit-hook.sh"

// claudeHookScript is the PreToolUse hook `conduitd install` drops to
// ~/.claude/hooks/conduit-hook.sh. Keep it byte-for-byte in sync with
// docs/conduit-hook.sh (the canonical, human-readable copy).
const claudeHookScript = `#!/usr/bin/env bash
# conduit-hook.sh — Claude Code PreToolUse hook for Conduit iOS approval
#
# Installed by ` + "`conduitd install`" + ` and wired into ~/.claude/settings.json.
# Canonical copy: docs/conduit-hook.sh

CONDUITD="${CONDUITD:-$HOME/.conduit/bin/conduitd}"

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

# Build structured-field args from stdin-parsed values (bash array prevents
# injection of extra flags by values containing spaces, quotes, or metacharacters).
EXTRA_ARGS=()
[ -n "$TOOL_NAME" ]                              && EXTRA_ARGS+=(--tool-name="$TOOL_NAME")
[ -n "$TOOL_USE_ID" ]                            && EXTRA_ARGS+=(--tool-use-id="$TOOL_USE_ID")
[ -n "$SESSION_ID" ]                             && EXTRA_ARGS+=(--session-id="$SESSION_ID")
[ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "{}" ] && EXTRA_ARGS+=(--tool-input="$TOOL_INPUT")

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
`

// claudeSettingsPath returns ~/.claude/settings.json for the given home.
func claudeSettingsPath(home string) string {
	return filepath.Join(home, ".claude", "settings.json")
}

// claudeHookScriptPath returns ~/.claude/hooks/conduit-hook.sh for the given home.
func claudeHookScriptPath(home string) string {
	return filepath.Join(home, ".claude", "hooks", "conduit-hook.sh")
}

// settingsHasHookCommand reports whether settings JSON already registers a
// PreToolUse hook whose command equals cmd. A missing/empty/malformed hooks
// block reads as "not present" so the caller wires it (idempotent).
func settingsHasHookCommand(settings map[string]json.RawMessage, cmd string) bool {
	hooksRaw, ok := settings["hooks"]
	if !ok {
		return false
	}
	var hooks map[string]json.RawMessage
	if json.Unmarshal(hooksRaw, &hooks) != nil {
		return false
	}
	preRaw, ok := hooks["PreToolUse"]
	if !ok {
		return false
	}
	var matchers []struct {
		Hooks []struct {
			Command string `json:"command"`
		} `json:"hooks"`
	}
	if json.Unmarshal(preRaw, &matchers) != nil {
		return false
	}
	for _, m := range matchers {
		for _, h := range m.Hooks {
			if h.Command == cmd {
				return true
			}
		}
	}
	return false
}

// mergeClaudeHookEntry returns settings JSON with the Conduit PreToolUse hook
// merged in, preserving every existing key. It appends a new matcher block so a
// user's existing PreToolUse hooks are kept. If the equivalent command is
// already registered, the input is returned unchanged and changed=false.
func mergeClaudeHookEntry(existing map[string]json.RawMessage, cmd string) (map[string]json.RawMessage, bool) {
	if existing == nil {
		existing = map[string]json.RawMessage{}
	}
	if settingsHasHookCommand(existing, cmd) {
		return existing, false
	}

	hooks := map[string]json.RawMessage{}
	if raw, ok := existing["hooks"]; ok {
		// A malformed hooks block is replaced rather than crashing the install;
		// callers only reach here when the command is not already present.
		_ = json.Unmarshal(raw, &hooks)
		if hooks == nil {
			hooks = map[string]json.RawMessage{}
		}
	}

	var matchers []json.RawMessage
	if raw, ok := hooks["PreToolUse"]; ok {
		_ = json.Unmarshal(raw, &matchers)
	}
	entry, _ := json.Marshal(map[string]interface{}{
		"matcher": "",
		"hooks": []map[string]string{
			{"type": "command", "command": cmd},
		},
	})
	matchers = append(matchers, entry)

	preRaw, _ := json.Marshal(matchers)
	hooks["PreToolUse"] = preRaw
	hooksRaw, _ := json.Marshal(hooks)
	existing["hooks"] = hooksRaw
	return existing, true
}

// wireClaudeHookSettings idempotently merges the Conduit PreToolUse hook into
// ~/.claude/settings.json. A missing or empty file is created; an existing file
// has all its keys preserved. The write is atomic (temp file + rename).
func wireClaudeHookSettings(home string) (changed bool, err error) {
	path := claudeSettingsPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return false, err
	}

	settings := map[string]json.RawMessage{}
	data, readErr := os.ReadFile(path)
	switch {
	case readErr == nil:
		if len(data) > 0 {
			if err := json.Unmarshal(data, &settings); err != nil {
				return false, fmt.Errorf("parse %s: %w", path, err)
			}
		}
	case os.IsNotExist(readErr):
		// fall through with empty settings
	default:
		return false, readErr
	}

	merged, changed := mergeClaudeHookEntry(settings, claudeHookCommand)
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

// claudeHookWired reports whether the Conduit PreToolUse hook is registered in
// the given settings.json. Used by `doctor` to verify the wiring (not just the
// script file). A missing/unreadable/malformed file reads as "not wired".
func claudeHookWired(settingsPath string) bool {
	data, err := os.ReadFile(settingsPath)
	if err != nil || len(data) == 0 {
		return false
	}
	var settings map[string]json.RawMessage
	if json.Unmarshal(data, &settings) != nil {
		return false
	}
	return settingsHasHookCommand(settings, claudeHookCommand)
}

// atomicWriteFile writes data to path via a temp file in the same directory
// then renames it into place, so a crash mid-write never leaves a partial
// settings.json.
func atomicWriteFile(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".conduit-settings-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(perm); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}
