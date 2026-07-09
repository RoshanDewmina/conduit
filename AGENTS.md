# AGENTS.md — Lancer (root agent contract)

> The shared contract for AI agents in this repo. **Codex** and **OpenCode** read this file
> natively; **Claude Code** imports it from `CLAUDE.md` (via `@AGENTS.md`) and adds Claude-specific
> tooling there. **Kimi Code** reads its own global `~/.kimi-code/KIMI.md`, **not** this file —
> mirror the rules below there if you drive Kimi in this repo. Keep this file short; it points at
> canonical sources rather than duplicating them. Scoped `AGENTS.md` files under `web/` and
> `marketing/` apply **only** within those directories.

## What Lancer is

iOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi) running on the
developer's own machines/servers. The phone **steers and approves**; it is not a phone IDE.
Three layers: the **iOS app** (`Packages/LancerKit/`), the **`lancerd`** resident daemon
(`daemon/lancerd/`), and the **`push-backend` + `agent-runner`** hosted-cloud control plane
(`daemon/push-backend/`, `daemon/agent-runner/`).

## Read these first (source of truth)

0. **`docs/STATUS_LEDGER.md`** — owner hub: current priority, branches, deadlines, canonical doc map. **Humans start here.**
0. **`docs/AGENT_READ_FIRST.md`** — agent index: read order by task type, standing instructions, Codex session chain. **Agents start here.**
1. **`ARCHITECTURE.md` §0.1** — current-state snapshot (implemented / partial / planned / deprecated / priorities). **Start here for code.**
2. **`ARCHITECTURE.md` §4.1** — navigation. The app shell is the **Cursor-style 3-root IA** (Home / Workspaces / Settings) under `Packages/LancerKit/Sources/AppFeature/CursorStyle/`. `LANCER_CURSOR_SHELL=1` (mock) and `LANCER_CURSOR_SHELL_LIVE=1` (live bridge) are the DEBUG launch seams. Legacy sidebar / Command Home is **deprecated** — not current design. `enum Tab` in `AppRoot.swift` is vestigial; do not reintroduce a tab bar or a `Control`/`Activity` root.
3. **`docs/agent-contract.md`** — architecture invariants you must not regress (module discipline, terminal/PTY rules, security/TOFU, testing).
4. **`docs/KNOWN_ISSUES.md`** (issue tracker) and **`docs/PUBLISH_READINESS_CHECKLIST.md`** (launch state).
5. **`docs/LIVE_LOOP_RUNBOOK.md`** — step-by-step bring-up + proof of the governed-approval loop and push notifications. The #1 priority for V1 is closing this loop on a real device.
6. Launch readiness and P0/P1 gates → **`docs/STATUS_LEDGER.md`** (owner hub) + **`docs/PUBLISH_READINESS_CHECKLIST.md`** (engineering checklist). Feature scope → **`docs/product/2026-07-05-lancer-feature-master-plan.md`** + **`docs/product/FEATURE_BACKLOG.md`**.
7. Point-in-time docs (`docs/LANCER_PROJECT_DOSSIER.md`, `docs/_archive/`, `docs/audit/`, `docs/superpowers/`, `docs/design-questions/`) were **purged 2026-07-06** — do not cite or recreate them. Use **`ARCHITECTURE.md` §0.1** + **`docs/STATUS_LEDGER.md`** for current state.

## Working rules

- **Treat the working code + recent verified commits as source of truth** over any older doc, plan, or conversation. When code and a doc disagree, fix one of them in the same change.
- **`git status` changes are other agents' / the owner's work** — do not revert them unless asked.
- **Verify before claiming done.** LancerKit Swift change → `cd Packages/LancerKit && swift build` (+ `swift test` if behavior changed). iOS UI / app-shell / strict-concurrency risk → the **XcodeBuildMCP app-target** build (plain `swift build` skips `#if os(iOS)` code). Daemon change → `go test ./...` **from `daemon/lancerd`** (not the repo root). See the `lancer-verification-gate` skill.
- **Distrust another agent's or tool's self-report by default, not just your own.** A prior transcript, PR description, or doc saying "done"/"merged"/"verified" is a claim, not a fact — re-check it against the live repo (`git log`, `git status`, `gh pr list`, the actual file) before relying on it or repeating it forward into a new session. The 2026-07-06 cross-platform conversation audit found this was the single most repeated, most expensive failure mode across Claude Code, Codex, and Cursor this week — including inside the audit's own first draft, which repeated a stale claim across three sessions before an independent pass caught it.
- **Worktree/branch merges must diff or rebase against the current tip, never whole-file `cp`.** A whole-file copy across worktrees silently destroyed an uncommitted edit that existed only on `main` (2026-07-03).
- **No dead code / back-compat shims / speculative abstractions** (`agent-contract.md` §3). Delete cleanly.
- **Security is fail-closed.** Keep the TOFU host-key prompt on production paths; never log secrets. Hooks default to hold-on-unreachable. Face ID/biometric gating was removed from the app entirely (2026-07-07, permanent) — don't reintroduce `BiometricGate` or a per-decision/per-key-load auth prompt. Full threat model: `docs/legal/SECURITY_ARCHITECTURE.md`.
- **Vendor CLI adapters drift fast** — before changing `daemon/lancerd/dispatch.go`, re-verify `which`/`--version`/`--help` and run the `vendor-cli-adapter-audit` skill. Never `sh -c` an interpolated prompt; build explicit argv.
- **New feature? Study the competitors first — borrow, don't reinvent** (owner directive 2026-07-09).
  Before designing any user-facing feature from scratch, check the local competitor clones under
  `research-repos/` (gitignored; restore with `git clone --depth 1` of `stablyai/orca`,
  `happier-dev/happier`, `omnara-ai/omnara` if absent) for a shipped implementation of the same
  problem, and mine it with file:line evidence before writing a design. Precedent + method:
  `docs/product/2026-07-09-chat-ui-port-map.md` (gap → per-competitor approach → "Port to Lancer").
  License discipline is mandatory: read each clone's LICENSE/LICENCE first — MIT/Apache-2.0 code is
  portable with an attribution comment (repo + source file); no license means patterns only, never
  verbatim code. These are React Native/web apps: port protocols, state machines, and policy logic
  directly; re-implement UI in SwiftUI informed by their patterns. Never commit competitor code
  or clones into the repo history.

## Project skills

Claude Code: `.claude/skills/` (see `.claude/skills/README.md`). Codex: `~/.codex/skills/` (`$name`).
Both ported from the same set: `lancer-context-onboarding`, `lancer-verification-gate`,
`lancer-parallel-handoff`, `vendor-cli-adapter-audit`, `agent-session-history-reader`,
`lancer-ia-board-workflow`. Claude-only (not yet ported to Codex): `lancer-design-handoff`,
`lancer-dead-view-sweep`, `lancer-onboarding-smoke`.

## Local workflow conventions

The owner's canonical local rules live at `~/.hermes/knowledge-base/AGENTS.md` (durable reports → files;
personal/PII only via the `personal-kb` MCP; never the IBKR trade tools). Honor them when running locally.
