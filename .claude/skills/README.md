# Lancer project skills (Claude Code)

Project-scoped skills for `/Users/roshansilva/Documents/command-center`. These were ported
from the Codex skill set (`~/.codex/skills/`) on 2026-06-18 and corrected to the current
**Cursor shell** IA (Home / Workspaces / Settings). Claude Code auto-discovers them; invoke with the `Skill` tool.

| Skill | Invoke when | Loads |
|---|---|---|
| **lancer-context-onboarding** | Starting any non-trivial Lancer task — planning, review, implementation, triage. Builds a repo-grounded mental model before editing. | `references/current-lancer-map.md` |
| **lancer-verification-gate** | Before calling Lancer work done, after code edits, or diagnosing build/test failures. Picks the verification that matches blast radius (`swift build` is *not* enough for iOS UI / app-target). | `references/verification-commands.md` |
| **lancer-parallel-handoff** | Splitting/dispatching Lancer work across agents (Claude + opencode/deepseek executors). Enforces exclusive file ownership + hot-file serialization. | `references/handoff-template.md` |
| **vendor-cli-adapter-audit** | Changing/reviewing agent-CLI adapter behavior (Claude Code, Codex, OpenCode, Kimi) in `daemon/lancerd/dispatch.go` — launch/continue argv, stream parsing, hooks, gates. | `references/vendor-cli-matrix.md` |
| **agent-session-history-reader** | Mining/summarizing prior local agent conversations (Claude/Codex/OpenCode/Kimi/Cursor) read-only before plans/reports. Shared canonical copy: `~/.agents/skills/agent-session-history-reader`. | `references/session-stores.md`, `scripts/list-agent-sessions.sh` |
| **lancer-ia-board-workflow** | Editing/verifying wireframes in `docs/design-audit/lancer-workflows-2026-07-05/`. | `references/board-map.md` |
| **lancer-design-handoff** | Generating/regenerating the design handoff or screen inventory from current code (not a stale doc), screenshotting real-app/debug-seam routes, writing per-page descriptions. | — |
| **lancer-dead-view-sweep** | "Delete the old-design swift files, keep what the app uses now" — reachability-based detection of orphaned views + stale assets, delete on one confirm. | — |
| **lancer-onboarding-smoke** | Live on-device first-run / onboarding / approval-loop / push smoke test. Encodes the ordered checklist (run lancerd *before* pairing). | — |
| **prompt-crafting** *(global)* | Optimize/trim prompts or produce a paste-ready next-agent brief. Use `agent-brief` mode for “what’s next?”. | `~/.agents/skills/prompt-crafting/references/` |
| **agent-feature-loop** | New/fuzzy feature: enforce Plan.md → approve → new implement session → milestone verify → PR. Blocks plan+code in the same chat. | `references/loop-templates.md` |
| **agent-session-handoff** | Context full, tool hop, or “continue later” — write Status.md so the next session doesn’t need transcript archaeology. | `references/status-template.md` |
| **agent-oracle-harness** | Non-trivial feature closure, publish miss-scans, live Sim/device proof, or systemic-failure re-audits. | `references/bun-lessons.md`, `adversarial-review.md`, `feature-contract.md`, `oracle-matrix.md`, `iou-protocol.md` |

## Notes
- **Source of truth always wins over a skill reference.** Skills point you at the right files; the
  code (`ARCHITECTURE.md`, `AppRoot.swift`, `daemon/lancerd/`) is authoritative. CLI flags and
  IA drift fast — re-verify before trusting any embedded claim.
- Project-only skills live here. Cross-runtime personal skills live canonically under
  `~/.agents/skills/` and are symlinked into `~/.claude/skills/` and `~/.codex/skills/`.
- `agent-session-history-reader` replaces the retired `conversation-history` skill.
