package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// Pi's per-action approval gate is an extension file, loaded explicitly per
// run via `-e <path>` (dispatch.go's pi cases in agentArgv/continueArgv/
// resumeArgv) — NOT `--mode rpc`, and NOT dropped into a discovery directory.
// This mirrors OpenCode's in-process-plugin → `lancerd agent-hook` pattern
// (opencode_plugin_install.go), and passing `-e` only on lancerd-launched
// runs gives the LANCER_GATE opt-in property for free: the owner's
// interactive `pi` sessions in a terminal never pass this flag, so the
// extension file is simply never loaded for them — no runtime env-var check
// needed inside the extension itself (unlike opencode's plugin, which is
// GLOBALLY auto-discovered and must gate on LANCER_GATE=1 at runtime).
//
// The pi.on("tool_call", ...) handler shape and the {block:true, reason}
// veto contract are confirmed against research-repos/pi (MIT License,
// Copyright 2025 Mario Zechner) packages/coding-agent/examples/extensions/
// permission-gate.ts — patterns only, no verbatim code copied (see that
// file's own doc comment below for the specific lines this mirrors).

// piExtensionScript is the tool_call extension `lancerd install` drops to
// piExtensionPath. Keep in sync with docs/pi-lancer-gate.ts.
const piExtensionScript = `// Lancer approval gate for Pi (@earendil-works/pi-coding-agent).
//
// Loaded ONLY when lancerd launches pi with "-e <this file>" (dispatch.go's
// pi cases in agentArgv/continueArgv/resumeArgv) — the owner's ordinary
// interactive pi sessions never pass -e, so this file is never loaded for
// them. Fail-closed: any tool call that isn't in the read-only allowlist is
// blocked unless lancerd approves it; lancerd unreachable or a hook error
// also blocks (never silently allows).
//
// Handler shape and the {block:true, reason} veto contract adapted from
// research-repos/pi (MIT License, Copyright 2025 Mario Zechner)
// packages/coding-agent/examples/extensions/permission-gate.ts — patterns
// only, no verbatim code copied.

import { spawnSync } from "node:child_process"

// Pi's built-in tool names (pi --help: "read, bash, edit, write" + grep/find/ls
// per packages/coding-agent/src/core/extensions/types.ts's ToolCallEvent union)
// that never mutate anything — auto-approved without a round-trip to lancerd.
const READ_ONLY = new Set(["read", "grep", "find", "ls"])

function classify(toolName, input) {
  if (toolName === "bash") {
    return { kind: "command", command: String(input?.command || "") }
  }
  if (toolName === "edit" || toolName === "write") {
    return { kind: "patch", command: String(input?.path || JSON.stringify(input || {})) }
  }
  // Unknown/custom tool — treat as a generic command so it still gates.
  return { kind: "command", command: String(input?.command || input?.path || toolName || "unknown") }
}

const DANGER_PATTERN = /(rm\s+-rf|sudo\s+|chmod\s+-R|chown\s+-R|mkfs|dd\s+if=|curl\b.*\|\s*(sh|bash)|wget\b.*\|\s*(sh|bash))/i

export default function (pi) {
  pi.on("tool_call", async (event, ctx) => {
    if (READ_ONLY.has(event.toolName)) return undefined

    const classified = classify(event.toolName, event.input)
    let risk = classified.kind === "command" ? "high" : "medium"
    if (DANGER_PATTERN.test(classified.command)) risk = "critical"

    const lancerd = process.env.LANCERD || ` + "`${process.env.HOME}/.lancer/bin/lancerd`" + `
    const argv = [
      "agent-hook",
      "--agent", "pi",
      "--kind", classified.kind,
      "--command", classified.command.slice(0, 20000),
      "--cwd", ctx.cwd,
      "--risk", risk,
      "--tool-name", event.toolName,
      "--tool-use-id", event.toolCallId,
    ]
    const sessionId = ctx.sessionManager?.getSessionId?.()
    if (sessionId) argv.push("--session-id", String(sessionId))

    const result = spawnSync(lancerd, argv, { stdio: ["ignore", "ignore", "ignore"] })
    if (result.error || result.status !== 0) {
      return { block: true, reason: "Blocked by Lancer: pi action was rejected on the iOS app, timed out, or lancerd was unreachable." }
    }
    return undefined
  })
}
`

// piExtensionDir returns ~/.lancer/pi-extensions, the daemon-owned directory
// this extension is dropped into (never a pi-auto-discovered location — see
// this file's module doc comment for why that matters).
func piExtensionDir(home string) string {
	return filepath.Join(home, ".lancer", "pi-extensions")
}

// piExtensionPath returns ~/.lancer/pi-extensions/lancer-gate.pi.ts — the
// exact path dispatch.go's pi argv builders append after "-e" when it exists.
func piExtensionPath(home string) string {
	return filepath.Join(piExtensionDir(home), "lancer-gate.pi.ts")
}

// piExtensionInstalled reports whether the extension file is present. File
// presence is the whole check — pi loads any path handed to -e directly, no
// separate settings-merge step (unlike Claude's hooks.json or Codex's
// hooks.json + trust record).
func piExtensionInstalled(home string) bool {
	_, err := os.Stat(piExtensionPath(home))
	return err == nil
}

// appendPiExtension inserts "-e <path>" immediately after argv[0] for pi
// launches when the Lancer gate extension is installed. Non-pi argv passes
// through untouched. A home-resolution failure or missing extension file
// means no injection — and hookWiredForAgent's pi case (which checks the
// same file) then reports unwired, so launch escalation stays fail-closed
// rather than assuming a gate that isn't riding the run. Called from
// realLauncher, the single exec choke point.
func appendPiExtension(argv []string) []string {
	if len(argv) == 0 || argv[0] != "pi" {
		return argv
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return argv
	}
	return appendPiExtensionForHome(argv, home)
}

// appendPiExtensionForHome is appendPiExtension with an injectable home for
// tests. The flag pair goes right after argv[0] so it always precedes the
// trailing "-p <prompt>" pair the argv builders end with.
func appendPiExtensionForHome(argv []string, home string) []string {
	if len(argv) == 0 || argv[0] != "pi" || !piExtensionInstalled(home) {
		return argv
	}
	out := make([]string, 0, len(argv)+2)
	out = append(out, argv[0], "-e", piExtensionPath(home))
	return append(out, argv[1:]...)
}

// installPiExtension writes the tool_call extension. Idempotent — re-running
// install just overwrites with the current script, same as
// installOpencodeGate/installClaudeHook.
func installPiExtension(home string) error {
	path := piExtensionPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(piExtensionScript), 0644); err != nil {
		return fmt.Errorf("write pi extension: %w", err)
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\n", path)
	return nil
}
