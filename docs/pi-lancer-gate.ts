// Lancer approval gate for Pi (@earendil-works/pi-coding-agent).
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

    const lancerd = process.env.LANCERD || `${process.env.HOME}/.lancer/bin/lancerd`
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
