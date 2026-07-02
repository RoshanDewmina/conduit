package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// OpenCode's approval gating used to be wired the same way as Claude Code's:
// a hooks.json + PreToolUse-command bash script. That mechanism is not real
// OpenCode config (verified 2026-07-01/02 against OpenCode 1.17.11 + official
// docs) — hooks.json/PreToolUse was never read, so every opencode-dispatched
// tool call ran completely ungated regardless of policy. The real extension
// point is a plugin's `tool.execute.before` hook, auto-discovered from
// ~/.config/opencode/plugins/ (no settings-merge step needed, unlike Claude's
// hooks.json). Canonical copy: docs/opencode-lancer-gate-plugin.js.

// opencodeGatePluginScript is the tool.execute.before plugin `lancerd install`
// drops to ~/.config/opencode/plugins/lancer-gate.js. Keep it byte-for-byte in
// sync with docs/opencode-lancer-gate-plugin.js.
const opencodeGatePluginScript = `// Lancer approval gate for OpenCode.
//
// Only gates tool calls when LANCER_GATE=1 is set in the process environment
// (set by lancerd's realLauncher for every opencode process it spawns).
// Interactive opencode sessions started by the owner do not have this
// variable, so they pass through untouched.

const READ_ONLY = new Set([
  "read", "glob", "grep", "ls", "list", "notebookread", "todowrite", "todoread",
  "websearch", "webfetch", "view_image",
])

const DANGER_PATTERN = /(rm\s+-rf|sudo\s+|chmod\s+-R|chown\s+-R|mkfs|dd\s+if=|curl\b.*\|\s*(sh|bash)|wget\b.*\|\s*(sh|bash))/i

function classify(tool, args) {
  const toolL = String(tool || "").toLowerCase()
  if (READ_ONLY.has(toolL)) return null

  let kind = "command"
  let command = ""
  if (toolL === "bash") {
    kind = "command"
    command = String(args?.command || "")
  } else if (["patch", "apply_patch", "edit", "write", "multiedit"].includes(toolL)) {
    kind = "patch"
    command = String(args?.command || args?.filePath || args?.path || JSON.stringify(args || {}))
  } else {
    command = String(args?.command || args?.filePath || args?.path || tool || "unknown")
  }

  let risk = "low"
  if (kind === "command") risk = "high"
  else if (kind === "patch") risk = "medium"
  if (DANGER_PATTERN.test(command)) risk = "critical"

  return { kind, risk, command }
}

export const LancerGate = async ({ directory, $ }) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (process.env.LANCER_GATE !== "1") return

      const classified = classify(input.tool, output?.args)
      if (!classified) return

      const cwd = String(output?.args?.cwd || directory || process.cwd())
      const lancerd = process.env.LANCERD || ` + "`${process.env.HOME}/.lancer/bin/lancerd`" + `

      const argv = [
        lancerd, "agent-hook",
        "--agent", "opencode",
        "--kind", classified.kind,
        "--command", classified.command.slice(0, 20000),
        "--cwd", cwd,
        "--risk", classified.risk,
      ]
      if (input.sessionID) argv.push("--session-id", String(input.sessionID))
      if (input.callID) argv.push("--tool-use-id", String(input.callID))
      if (input.tool) argv.push("--tool-name", String(input.tool))

      try {
        await ` + "$`${argv}`.quiet()" + `
      } catch (err) {
        throw new Error("Blocked by Lancer: OpenCode action was rejected on the iOS app or timed out.")
      }
    },
  }
}
`

// opencodePluginPath returns ~/.config/opencode/plugins/lancer-gate.js.
func opencodePluginPath(home string) string {
	return filepath.Join(home, ".config", "opencode", "plugins", "lancer-gate.js")
}

// opencodeGateWired reports whether the tool.execute.before plugin is
// present. Unlike Claude's hooksHasHookCommand (which checks a JSON block),
// OpenCode auto-discovers any file dropped in the global plugins/ directory
// with no separate settings-merge step, so file presence is the whole check.
func opencodeGateWired(home string) bool {
	_, err := os.Stat(opencodePluginPath(home))
	return err == nil
}

// installOpencodeGate writes the tool.execute.before plugin. Idempotent —
// re-running install just overwrites with the current script, same as
// installClaudeHook. No settings-merge step: OpenCode auto-discovers any file
// dropped in the global plugins/ directory.
func installOpencodeGate(home string) error {
	pluginPath := opencodePluginPath(home)
	if err := os.MkdirAll(filepath.Dir(pluginPath), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(pluginPath, []byte(opencodeGatePluginScript), 0644); err != nil {
		return fmt.Errorf("write opencode gate plugin: %w", err)
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\n", pluginPath)
	return nil
}
