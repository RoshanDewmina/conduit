# AGENTS.md — Lancer (root agent contract)

> The shared contract for AI agents in this repo. **Codex** and **OpenCode** read this file
> natively; **Claude Code** imports it from `CLAUDE.md` (via `@AGENTS.md`) and adds Claude-specific
> tooling there. **Kimi Code** reads its own global `~/.kimi-code/KIMI.md`, **not** this file —
> mirror the rules below there if you drive Kimi in this repo. Keep this file short; it points at
> canonical sources rather than duplicating them. Scoped `AGENTS.md` files under `web/`,
> `marketing/`, and `docs/lancer-ui-prototype/` apply **only** within those directories.

## What Lancer is

iOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi) running on the
developer's own machines/servers. The phone **steers and approves**; it is not a phone IDE.
Three layers: the **iOS app** (`Packages/LancerKit/`), the **`lancerd`** resident daemon
(`daemon/lancerd/`), and the **`push-backend` + `agent-runner`** hosted-cloud control plane
(`daemon/push-backend/`, `daemon/agent-runner/`).

## Read these first (source of truth)

1. **`ARCHITECTURE.md` §0.1** — current-state snapshot (implemented / partial / planned / deprecated / priorities). **Start here.**
2. **`ARCHITECTURE.md` §4.1** — navigation. The home is a **sidebar / New Chat shell** (durable chat threads), **not** a tab bar. `enum Tab` in `AppRoot.swift` is vestigial; do not reintroduce a tab bar or a `Control`/`Activity` root.
3. **`docs/agent-contract.md`** — architecture invariants you must not regress (module discipline, terminal/PTY rules, security/TOFU, testing).
4. **`docs/KNOWN_ISSUES.md`** (issue tracker) and **`docs/PUBLISH_READINESS_CHECKLIST.md`** (launch state).
5. **`docs/LIVE_LOOP_RUNBOOK.md`** — step-by-step bring-up + proof of the governed-approval loop and push notifications. The #1 priority for V1 is closing this loop on a real device.
6. **`docs/LAUNCH_AUDIT-2026-06-18.md`** — current readiness scorecard + prioritized P0/P1/P2 plan + V1 scope decisions.
7. `docs/LANCER_PROJECT_DOSSIER.md` is **archived** (`docs/_archive/`) — do not cite it.

## Working rules

- **Treat the working code + recent verified commits as source of truth** over any older doc, plan, or conversation. When code and a doc disagree, fix one of them in the same change.
- **`git status` changes are other agents' / the owner's work** — do not revert them unless asked.
- **Verify before claiming done.** LancerKit Swift change → `cd Packages/LancerKit && swift build` (+ `swift test` if behavior changed). iOS UI / app-shell / strict-concurrency risk → the **XcodeBuildMCP app-target** build (plain `swift build` skips `#if os(iOS)` code). Daemon change → `go test ./...` **from `daemon/lancerd`** (not the repo root). See the `lancer-verification-gate` skill.
- **No dead code / back-compat shims / speculative abstractions** (`agent-contract.md` §3). Delete cleanly.
- **Security is fail-closed.** Keep the TOFU host-key prompt on production paths; keys stay in Keychain behind `BiometricGate`; never log secrets. Hooks default to hold-on-unreachable. Full threat model: `docs/legal/SECURITY_ARCHITECTURE.md`.
- **Vendor CLI adapters drift fast** — before changing `daemon/lancerd/dispatch.go`, re-verify `which`/`--version`/`--help` and run the `vendor-cli-adapter-audit` skill. Never `sh -c` an interpolated prompt; build explicit argv.

## Project skills

Claude Code: `.claude/skills/` (see `.claude/skills/README.md`). Codex: `~/.codex/skills/` (`$name`).
Both ported from the same set: `lancer-context-onboarding`, `lancer-verification-gate`,
`lancer-parallel-handoff`, `vendor-cli-adapter-audit`, `agent-session-history-reader`,
`lancer-ia-board-workflow`. Claude-only (not yet ported to Codex): `lancer-design-handoff`,
`lancer-dead-view-sweep`, `lancer-onboarding-smoke`.

## Local workflow conventions

The owner's canonical local rules live at `~/.hermes/knowledge-base/AGENTS.md` (durable reports → files;
personal/PII only via the `personal-kb` MCP; never the IBKR trade tools). Honor them when running locally.
