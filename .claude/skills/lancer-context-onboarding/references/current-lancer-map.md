# Current Lancer Map

Use this compact map after reading the required live files. It is a navigation aid, not a substitute for current code.

## Canonical Rules

- Owner hub: `docs/STATUS_LEDGER.md`
- Agent index: `docs/AGENT_READ_FIRST.md`
- Repo engineering rules: `docs/agent-contract.md`
- Claude/OpenCode execution convention: `CLAUDE.md`
- General repo entrypoints: `README.md`, `ARCHITECTURE.md` §0.1 + §4.1
- Launch truth: `docs/PUBLISH_READINESS_CHECKLIST.md`
- Verified issues: `docs/KNOWN_ISSUES.md`
- Feature scope: `docs/product/2026-07-05-lancer-feature-master-plan.md`
- Implementation gaps: `docs/product/2026-07-06-feature-implementation-gap-matrix.md`
- Wireframes: `docs/design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md`
- Tier 0 screenshot evidence: `docs/test-runs/user-ready-tier0-2026-07-06/`, `docs/test-runs/composer-verify-2026-07-06/`

## Current Product Direction

- **Navigation:** Cursor-style **3-root IA** — Home / Workspaces / Settings (`AppFeature/CursorStyle/`).
- **Launch seams:** `LANCER_CURSOR_SHELL=1` (mock), `LANCER_CURSOR_SHELL_LIVE=1` (live bridge).
- Legacy sidebar / Command Home is **deprecated** — not current design.
- Phone steers and approves — not a phone IDE. Governance + cross-vendor dispatch is the moat.
- Tier 0 exit bar: pair → dispatch → approval → continue through live Cursor shell + real `lancerd`.

## Common Code Areas

- Cursor shell: `Packages/LancerKit/Sources/AppFeature/CursorStyle/` (`CursorAppShell`, live bridge)
- App root / routing: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`
- Chat transcript and artifacts: `Packages/LancerKit/Sources/SessionFeature/Chat/`
- Settings: `Packages/LancerKit/Sources/SettingsFeature/`
- Design system: `Packages/LancerKit/Sources/DesignSystem/`
- Relay bridge/router: `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`, `daemon/lancerd/e2e_router.go`
- Agent dispatch: `daemon/lancerd/dispatch.go`, `daemon/lancerd/server.go`

## Drift Checks

- `docs/LANCER_PROJECT_DOSSIER.md` is archived — do not cite.
- July-4 `docs/product/2026-07-04-*` (except `v1-paid-away-workflow-spec.md`) — historical only.
- Removed bundles (`docs/design-audit/workflows/`, `lancer-core-wireframes`, `proof-to-ship-wireframes`, `docs/lancer-ui-prototype/`, etc.) — do not link.
- `enum Tab` and legacy sidebar IA — vestigial; Cursor shell is canonical.
