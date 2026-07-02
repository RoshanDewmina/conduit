// Lancer approval gate for OpenCode.
//
// OpenCode's `hooks.json` + PreToolUse-command config (the Claude-Code-style
// mechanism the old ~/.config/opencode/hooks/*.sh scripts assumed) is not a
// real OpenCode 1.17.x mechanism -- the current extension point is a plugin's
// `tool.execute.before` hook (see docs/handoff-2026-07-01-relay-decision-return-path.md
// sibling investigation notes, 2026-07-01/02). This plugin re-implements the
// same gating docs/opencode-lancer-hook.sh performed, calling straight into
// `lancerd agent-hook` so audit/policy/phone-escalation stays in one place.
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
      const lancerd = process.env.LANCERD || `${process.env.HOME}/.lancer/bin/lancerd`

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
        await $`${argv}`.quiet()
      } catch (err) {
        throw new Error("Blocked by Lancer: OpenCode action was rejected on the iOS app or timed out.")
      }
    },
  }
}
