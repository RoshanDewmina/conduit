# Current Lancer Map

Use this compact map after reading the required live files. It is a navigation aid, not a substitute for current code.

## Canonical Rules

- Local wiki/workflow: `/Users/roshansilva/.hermes/knowledge-base/AGENTS.md`
- Repo engineering rules: `docs/agent-contract.md`
- Claude/OpenCode execution convention and app verification notes: `CLAUDE.md`
- General repo entrypoints: `README.md`, `ARCHITECTURE.md`
- Architecture source of truth: `ARCHITECTURE.md`
- Launch truth: `docs/PUBLISH_READINESS_CHECKLIST.md`
- Verified issues: `docs/KNOWN_ISSUES.md`
- Validation procedure: `docs/validation-playbook.md`
- Most recent V1 evidence snapshot: `docs/test-runs/2026-06-18-v1-verification.md`

## Active V1 Plans

Start at:

```text
docs/superpowers/plans/2026-06-18-v1-implementation-handoff-index.md
```

Important linked plans:

- `2026-06-18-chat-history-search-continuation-v1.md`
- `2026-06-18-sidebar-shell-swift-v1.md`
- `2026-06-18-chat-artifacts-approvals-v1.md`
- `2026-06-18-fleet-thread-routing-v1.md`
- `2026-06-18-v1-launch-hardening-testflight.md`
- `2026-06-18-session-resume-followup-mvp.md`

## Current Product Direction

- A new user should land in chat.
- Recent threads must survive app restart.
- Search should find prior prompts, assistant output, and artifacts.
- Follow-up continuation should create ordered turns rather than mutating old output streams.
- Fleet shows hosts/agents/status/spend/stop controls and opens related threads.
- Approvals appear in Inbox and inline with the related chat context.
- Activity/history is not a root destination.

## Common Code Areas

- App shell and navigation: `Packages/LancerKit/Sources/AppFeature/`
- Chat transcript and artifacts: `Packages/LancerKit/Sources/SessionFeature/Chat/`
- Settings: `Packages/LancerKit/Sources/SettingsFeature/`
- Core protocol types: `Packages/LancerKit/Sources/LancerCore/`
- SSH transport: `Packages/LancerKit/Sources/SSHTransport/`
- Relay bridge/router: `Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`, `daemon/lancerd/e2e_router.go`
- Agent dispatch: `daemon/lancerd/dispatch.go`, `daemon/lancerd/server.go`

## Drift Checks

- Generated reports can lag local code.
- `docs/current-state-audit.md` is archived/stale per `docs/agent-contract.md`.
- `docs/remaining-work.md` is superseded and should not drive work.
- Session-resume docs and current adapter code may disagree; inspect code before concluding.
- `docs/LANCER_PROJECT_DOSSIER.md` is useful as a broad briefing, but newer June 18 plans may supersede its IA/status details.
