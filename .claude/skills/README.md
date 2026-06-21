# Conduit project skills (Claude Code)

Project-scoped skills for `/Users/roshansilva/Documents/command-center`. These were ported
from the Codex skill set (`~/.codex/skills/`) on 2026-06-18 and corrected to the current
**sidebar / New Chat** IA. Claude Code auto-discovers them; invoke with the `Skill` tool.

| Skill | Invoke when | Loads |
|---|---|---|
| **conduit-context-onboarding** | Starting any non-trivial Conduit task — planning, review, implementation, triage. Builds a repo-grounded mental model before editing. | `references/current-conduit-map.md` |
| **conduit-verification-gate** | Before calling Conduit work done, after code edits, or diagnosing build/test failures. Picks the verification that matches blast radius (`swift build` is *not* enough for iOS UI / app-target). | `references/verification-commands.md` |
| **conduit-parallel-handoff** | Splitting/dispatching Conduit work across agents (Claude + opencode/deepseek executors). Enforces exclusive file ownership + hot-file serialization. | `references/handoff-template.md` |
| **vendor-cli-adapter-audit** | Changing/reviewing agent-CLI adapter behavior (Claude Code, Codex, OpenCode, Kimi) in `daemon/conduitd/dispatch.go` — launch/continue argv, stream parsing, hooks, gates. | `references/vendor-cli-matrix.md` |
| **agent-session-history-reader** | Mining/summarizing prior local agent conversations (Claude/Codex/OpenCode/Kimi) read-only before plans/reports. | `references/session-stores.md`, `scripts/list-agent-sessions.sh` |
| **conduit-ia-board-workflow** | Editing/verifying the IA design board or `docs/conduit-ui-prototype/`. **Lower priority** — the board is a design reference; the shipped sidebar/New Chat IA in code is canonical. | `references/board-map.md` |

## Notes
- **Source of truth always wins over a skill reference.** Skills point you at the right files; the
  code (`ARCHITECTURE.md`, `AppRoot.swift`, `daemon/conduitd/`) is authoritative. CLI flags and
  IA drift fast — re-verify before trusting any embedded claim.
- These are the **Claude-native** copies. The Codex originals live at `~/.codex/skills/` and are
  invoked there with `$skill-name`. Keep the two in sync when you materially change one.
- The global `conversation-history` skill overlaps `agent-session-history-reader`; prefer the
  project one here because it's tuned to this Mac's session stores.
