# Fable Frontend Wipe + Rebuild — Status

**Track:** Frontend wipe (scorched earth) → owner rebuilds later  
**Gate:** **WIPE EXECUTED 2026-07-09 — C / A / A** (no stub / no implement)  
**Wipe branch / worktree:** `feat/frontend-scorched-wipe` @  
`/Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe`  
**W0.A checkpoint:** `stash@{0}` + branch `checkpoint/w0a-dogfood-pre-scorched-wipe` (main checkout `feat/chat-overhaul-w0a`)

## Owner lock (2026-07-09)

| Q | Choice | Meaning |
|---|---|---|
| 1 | **C** | Scorched earth — entire `CursorStyle/` (views + bridges/engines), entire `DesignSystem/`, SessionFeature `Chat/` + UI views, DiffFeature/FilesFeature, HostKeyConfirmSheet, PaywallSheet, chrome UITests, Cursor* + chat-card unit tests, Live Activity + Status widget UI sources |
| 2 | **A** | Non-compiling tree OK — **no stub, no rebuild, no implement** |
| 3 | **A** | Checkpoint W0.A → wipe in isolated worktree |

## Done

- Wave 0 inventory (Fable 5) — evidence only; execute scope superseded by C/A/A
- W0.A LancerKit dirt stashed (`stash@{0}`) + named `checkpoint/w0a-dogfood-pre-scorched-wipe`
- Isolated worktree + branch `feat/frontend-scorched-wipe` from `e850b126`
- Scorched deletes applied (**113 file deletes**) + `Package.swift` cleanup (DesignSystem / DiffFeature / FilesFeature / MarkdownUI products+targets removed)
- `daemon/**` untouched in wipe tree
- **iOS app-target build FAIL (by design):** XcodeBuildMCP `build_sim` → `cannot find 'QuestionCardModel' in scope` (`CommandGateway.swift:207`). macOS `swift build` stays green because `AppRoot` is `#if os(iOS)`.

## What was deleted (113 paths)

| Area | Result |
|---|---|
| `AppFeature/CursorStyle/` | **entire directory gone** (29 files: LiveBridge, engines, all views) |
| `DesignSystem/` | **entire directory gone** (44 paths incl. tokens, atoms, fonts) |
| `SessionFeature/Chat/` + `LivePromptInputView.swift` | **gone** |
| `DiffFeature/` + `FilesFeature/` | **gone** + removed from Package.swift |
| `WorkspacesFeature/HostKeyConfirmSheet.swift` | gone (`SSHParse` kept) |
| `SettingsFeature/PaywallSheet.swift` | gone |
| `LancerLiveActivityWidget/*.swift` + `LancerWidget/*.swift` | UI sources gone |
| `LancerUITests/*.swift` | all 6 gone |
| Cursor* + chat-card / ThreadAttention unit tests | gone |

## What remains (not wiped — for your rebuild)

- `AppRoot.swift` + AppFeature stores / sync / dispatch / approval ingest (still reference deleted types)
- SessionFeature engines (relay, LA attributes/manager, approval relay, run dispatch, SessionViewModel, …)
- `Lancer/` app intents + `@main`
- Non-UI kits: LancerCore, Persistence, Sync, SSH, Security, AgentKit, Notifications, IntentsKit, TerminalEngine (`RawTerminalView` still present), PreviewKit, Inbox/Onboarding/Settings view-models
- Watch targets untouched
- `daemon/**` untouched

## Remaining / next

1. Owner reviews wipe worktree; commit when ready (not auto-committed)
2. Owner rebuilds UI in a new session — **this agent does not implement**
3. Restore W0.A dogfood from `checkpoint/w0a-dogfood-pre-scorched-wipe` / `stash@{0}` if needed on main checkout

## Explicit non-goals (honored)

- No stub shell · no Wave 3 implement · no daemon edits · no Siri Approve · no Face ID · no iOS 27 target raise · no phone reinstall
