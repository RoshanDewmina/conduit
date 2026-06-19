# AGENTS.md — Conduit (root agent contract)

> The entry point for **any** AI agent (Codex, OpenCode, Kimi, Claude Code) working in this repo.
> Claude Code also reads `CLAUDE.md`. Keep this file short; it points at the canonical sources
> rather than duplicating them. Scoped `AGENTS.md` files exist under `web/`, `marketing/`, and
> `docs/conduit-ui-prototype/` and apply **only** within those directories.

## What Conduit is

iOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi) running on the
developer's own machines/servers. The phone **steers and approves**; it is not a phone IDE.
Three layers: the **iOS app** (`Packages/ConduitKit/`), the **`conduitd`** resident daemon
(`daemon/conduitd/`), and the **`push-backend` + `agent-runner`** hosted-cloud control plane
(`daemon/push-backend/`, `daemon/agent-runner/`).

## Read these first (source of truth)

1. **`ARCHITECTURE.md` §0.1** — current-state snapshot (implemented / partial / planned / deprecated / priorities). **Start here.**
2. **`ARCHITECTURE.md` §4.1** — navigation. The home is a **sidebar / New Chat shell** (durable chat threads), **not** a tab bar. `enum Tab` in `AppRoot.swift` is vestigial; do not reintroduce a tab bar or a `Control`/`Activity` root.
3. **`docs/agent-contract.md`** — architecture invariants you must not regress (module discipline, terminal/PTY rules, security/TOFU, testing).
4. **`docs/KNOWN_ISSUES.md`** (issue tracker) and **`docs/PUBLISH_READINESS_CHECKLIST.md`** (launch state).
5. **`docs/LIVE_LOOP_RUNBOOK.md`** — step-by-step bring-up + proof of the governed-approval loop and push notifications. The #1 priority for V1 is closing this loop on a real device.
6. **`docs/LAUNCH_AUDIT-2026-06-18.md`** — current readiness scorecard + prioritized P0/P1/P2 plan + V1 scope decisions.
7. `docs/CONDUIT_PROJECT_DOSSIER.md` is **archived** (`docs/_archive/`) — do not cite it.

## Working rules

- **Treat the working code + recent verified commits as source of truth** over any older doc, plan, or conversation. When code and a doc disagree, fix one of them in the same change.
- **`git status` changes are other agents' / the owner's work** — do not revert them unless asked.
- **Verify before claiming done.** ConduitKit Swift change → `cd Packages/ConduitKit && swift build` (+ `swift test` if behavior changed). iOS UI / app-shell / strict-concurrency risk → the **XcodeBuildMCP app-target** build (plain `swift build` skips `#if os(iOS)` code). Daemon change → `go test ./...` **from `daemon/conduitd`** (not the repo root). See the `conduit-verification-gate` skill.
- **No dead code / back-compat shims / speculative abstractions** (`agent-contract.md` §3). Delete cleanly.
- **Security is fail-closed.** Keep the TOFU host-key prompt on production paths; keys stay in Keychain behind `BiometricGate`; never log secrets. Hooks default to hold-on-unreachable.
- **Vendor CLI adapters drift fast** — before changing `daemon/conduitd/dispatch.go`, re-verify `which`/`--version`/`--help` and run the `vendor-cli-adapter-audit` skill. Never `sh -c` an interpolated prompt; build explicit argv.

## Project skills

Claude Code: `.claude/skills/` (see `.claude/skills/README.md`). Codex: `~/.codex/skills/` (`$name`).
Both ported from the same set: `conduit-context-onboarding`, `conduit-verification-gate`,
`conduit-parallel-handoff`, `vendor-cli-adapter-audit`, `agent-session-history-reader`,
`conduit-ia-board-workflow`.

## Local workflow conventions

The owner's canonical local rules live at `~/.hermes/knowledge-base/AGENTS.md` (durable reports → files;
personal/PII only via the `personal-kb` MCP; never the IBKR trade tools). Honor them when running locally.
