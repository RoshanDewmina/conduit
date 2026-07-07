# Phone-ready verification pass — 2026-07-06

Branch/worktree: `claude/amazing-mayer-246fef` (merged `master` Cursor shell)

## Automated gates (evidence)

| Gate | Command / artifact | Result |
|---|---|---|
| Relay E2E round-trip | `scripts/validation/relay-approval-e2e.sh` | **PASS** (2026-07-06 04:33 UTC); harness hardened with test-start detection — re-run if sim diagnostics hang |
| TapInjectionProofTests (sidebar IA) | `xcodebuild test … -only-testing:LancerUITests/TapInjectionProofTests` (4 rewritten tests) | **PASS** (2026-07-06 01:09 UTC) |
| CursorAppShellExhaustiveTests | `xcodebuild test … -only-testing:LancerUITests/CursorAppShellExhaustiveTests` | **20/20 PASS** (~399s) |
| CursorShellLiveApprovalTests | `xcodebuild test … -only-testing:LancerUITests/CursorShellLiveApprovalTests` | **PASS** (Tier-0 live shell + seeded approval) |
| lancerd Go | `cd daemon/lancerd && go test ./...` | **PASS** |
| App sim build (iPhone 17 Pro) | `xcodebuild build -destination id=095F8B3A-…` | **SUCCEEDED** |
| App device build (iPhone 17 physical) | `xcodebuild build -destination id=557A7877-…` | **SUCCEEDED** |
| Sim matrix builds | iPhone 17e (`83032C2E…`), iPad Pro 11" (`4E1C92AC…`) | **SUCCEEDED** |

## Harness fix

`scripts/validation/relay-approval-e2e.sh` now **blocks until phone pairs** (up to 600s) before firing `agent-hook`. Previous failure was escalation dropped with `relay client not paired` because xcodebuild + pairing outlasted the old 240s warn-and-continue path.

## Product changes in this pass

1. **Tier-0 wire-only (sidebar)** — `CursorHomeView` / `CursorWorkspacesView` receive live `CursorShellLiveBridge` via `AppRoot` env; navigation wired for threads, composer, inbox attention.
2. **Unified appearance** — `AppRoot.cursorResolvedScheme` drives `\.cursorScheme` from `LancerAppearance` (light/dark/system).
3. **KNOWN_ISSUES §4b** — `ChatInputBar` hardcoded `.system` fonts → DS tokens; `DSStatusDot` accessibility labels.
4. **UI-IA-1** — `TapInjectionProofTests` rewritten for sidebar + Cursor Workspaces IA; UITest biometric bypass via `LANCER_UITEST_RESEED`.

## Owner-gated (not re-proven this session)

| Item | Notes |
|---|---|
| CHECKPOINT **5c** APNs on physical device | Requires fresh install + screen recording per `LIVE_LOOP_RUNBOOK.md` |
| Both shells manual device checklist | Sidebar + `LANCER_CURSOR_SHELL_LIVE=1` — build green; manual tap-through on Roshan's iPhone 17 (`557A7877…`) pending |
| StoreKit / Watch / production Supabase | Per `KNOWN_ISSUES.md` §0.1 / §6 owner gates |

## Docs reconciled (2026-07-06)

- [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](../product/2026-07-06-feature-implementation-gap-matrix.md) — refreshed
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) §4.1 — 3-root IA + Cursor DEBUG shell
- [`docs/product/2026-07-06-phone-primary-dev-readiness.md`](../product/2026-07-06-phone-primary-dev-readiness.md)
- [`docs/architecture/2026-07-06-terminal-git-worktree-adr.md`](../architecture/2026-07-06-terminal-git-worktree-adr.md)

- **Sidebar / New Chat** — production `AppRoot` path; relay E2E uses `LANCER_DESTINATION=inbox`.
- **Cursor live shell** — `LANCER_CURSOR_SHELL_LIVE=1` DEBUG seam; 20/20 mock exhaustive tests green.
