# Lancer project skills (Claude Code)

Project-scoped skills for `/Users/roshansilva/Documents/command-center`. These were ported
from the Codex skill set (`~/.codex/skills/`) on 2026-06-18 and corrected to the current
**sidebar / New Chat** IA. Claude Code auto-discovers them; invoke with the `Skill` tool.

| Skill | Invoke when | Loads |
|---|---|---|
| **lancer-context-onboarding** | Starting any non-trivial Lancer task — planning, review, implementation, triage. Builds a repo-grounded mental model before editing. | `references/current-lancer-map.md` |
| **lancer-verification-gate** | Before calling Lancer work done, after code edits, or diagnosing build/test failures. Picks the verification that matches blast radius (`swift build` is *not* enough for iOS UI / app-target). | `references/verification-commands.md` |
| **lancer-parallel-handoff** | Splitting/dispatching Lancer work across agents (Claude + opencode/deepseek executors). Enforces exclusive file ownership + hot-file serialization. | `references/handoff-template.md` |
| **vendor-cli-adapter-audit** | Changing/reviewing agent-CLI adapter behavior (Claude Code, Codex, OpenCode, Kimi) in `daemon/lancerd/dispatch.go` — launch/continue argv, stream parsing, hooks, gates. | `references/vendor-cli-matrix.md` |
| **agent-session-history-reader** | Mining/summarizing prior local agent conversations (Claude/Codex/OpenCode/Kimi) read-only before plans/reports. | `references/session-stores.md`, `scripts/list-agent-sessions.sh` |
| **lancer-ia-board-workflow** | Editing/verifying the IA design board or `docs/lancer-ui-prototype/`. **Lower priority** — the board is a design reference; the shipped sidebar/New Chat IA in code is canonical. | `references/board-map.md` |
| **lancer-design-handoff** | Generating/regenerating the design handoff or screen inventory from current code (not a stale doc), screenshotting real-app/debug-seam routes, writing per-page descriptions. | — |
| **lancer-dead-view-sweep** | "Delete the old-design swift files, keep what the app uses now" — reachability-based detection of orphaned views + stale assets, delete on one confirm. | — |
| **lancer-onboarding-smoke** | Live on-device first-run / onboarding / approval-loop / push smoke test. Encodes the ordered checklist (run lancerd *before* pairing). | — |

## Notes
- **Source of truth always wins over a skill reference.** Skills point you at the right files; the
  code (`ARCHITECTURE.md`, `AppRoot.swift`, `daemon/lancerd/`) is authoritative. CLI flags and
  IA drift fast — re-verify before trusting any embedded claim.
- These are the **Claude-native** copies. The Codex originals live at `~/.codex/skills/` and are
  invoked there with `$skill-name`. Keep the two in sync when you materially change one.
- The global `conversation-history` skill overlaps `agent-session-history-reader`; prefer the
  project one here because it's tuned to this Mac's session stores.
