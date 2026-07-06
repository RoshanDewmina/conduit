# amazing-mayer worktree audit — 2026-07-06

Branch: `claude/amazing-mayer-246fef`  
Path: `.claude/worktrees/amazing-mayer-246fef`  
Baseline: `988a468c` (feat(ios): finish phone-ready core)  
Diff vs HEAD: **68 files, +595 / −18,013 lines** (51 deletions, 17 modifications, 14 untracked)

**Verdict: do not merge wholesale.** The deletion surface is too large and removes production paths that `codex/tier-0-live-cursor-shell` still depends on for Settings, inbox, and relay harnesses. Cherry-pick only after file-by-file review.

---

## Intent (inferred)

Replace legacy sidebar / New Chat / SettingsFeature views with a **Cursor-only production shell**. Gap matrix in this worktree states legacy IA is deleted and Cursor shell is the only root.

## High-risk deletions (51 files)

### App navigation & chat (legacy shell)

| File | Risk |
|------|------|
| `LancerSidebarView.swift`, `SidebarShellState.swift` | Removes sidebar IA — OK only if Cursor shell fully replaces all destinations |
| `NewChatTabView.swift`, `ChatHistoryView.swift` | Removes durable chat thread UI — Cursor shell must own dispatch/follow-up |
| `ChatArchiveView.swift`, `ChatArtifactCards.swift`, `ChatArtifactDetailView.swift` | Artifact surfaces removed |
| `ObservedSessionView.swift`, `ObservedSessionsCache.swift` | Observed-session attach UI removed |
| `RunDetailView.swift`, `RunControls.swift` | Run inspection removed |
| `WorkspaceDetailView.swift`, `WorkspaceRouting.swift`, `FleetThreadMapper.swift` | Workspace routing helpers removed |

### Inbox / approvals

| File | Risk |
|------|------|
| `InboxFeature/InboxView.swift` | **Critical** — relay E2E harness (`TapInjectionProofTests`) expects Inbox board cards |
| `ActivityView.swift`, `BridgeAuditFeedView.swift`, `AllowAlwaysScopeSheet.swift` | Secondary inbox surfaces |

### Settings (entire SettingsFeature module views)

All of `SettingsFeature/*View.swift` deleted (~20 files), including:

- `SettingsView.swift`, `E2ERelayPairingView.swift`, `PolicyEditorView.swift`, `PolicyHomeView.swift`
- `AuditView.swift`, `BillingView.swift`, `SSHKeysView.swift`, `SecretsView.swift`, `DoctorView.swift`

`AppRoot` on this branch routes Settings through `CursorSettingsView(onOpenRealSettings:)` — verify the replacement actually exposes relay pairing, policy, audit, and billing before deleting sources.

### Onboarding

All `OnboardingFeature/*` views deleted. Replaced by `CursorRelayPairingSheet` (untracked) — must verify pairing parity.

### Tests removed

- `ChatArtifactRenderingTests`, `FleetThreadMapperTests`, `SidebarShellStateTests`, `WorkspaceRoutingTests`

## Modifications worth cherry-picking (review first)

| File | Notes |
|------|-------|
| `AppRoot.swift` | Cursor shell as production root; live bridge wiring |
| `CursorAppShell.swift`, `CursorShellLiveBridge.swift` | Live shell integration (overlap with `codex/tier-0-live-cursor-shell`) |
| `CursorSettingsView.swift`, `CursorComposerSheet.swift` | UI polish |
| `InboxViewModel+Live.swift` | Approval VM changes — may conflict with codex P0 fixes |
| `DispatchAgent.swift` (untracked) | New dispatch helper |
| `DispatchHaikuFlowTests.swift`, `LegacyUIRemovalTests.swift` (untracked) | New test coverage |

## Missing from this worktree (present on `codex/tier-0-live-cursor-shell`)

| Item | Impact |
|------|--------|
| BiometricGate fail-closed refactor + tests | P0 security — **must port** |
| Daemon `emergencyStop` latch + RPC | P0 security — **must port** |
| `BiometricGateTests.swift`, updated `KNOWN_ISSUES.md` P0 closure | Doc/test gap |
| Consolidated status + Tier 0 proof run docs | Documentation gap |

## Cherry-pick recommendation

| Action | Items |
|--------|-------|
| **Port from codex → amazing-mayer** | P0 security commits (`531685b6`, security fix), Tier 0 proof doc, consolidated status |
| **Consider from amazing-mayer → codex** | `DispatchAgent.swift`, `CursorRelayPairingSheet.swift`, `DispatchHaikuFlowTests` after review |
| **Do not merge as-is** | Entire deletion pass; breaks relay E2E and Settings surfaces |
| **Reconcile before merge** | Two divergent `AppRoot` / live-bridge implementations — diff and merge manually |

## Build impact preview

Deleting `SettingsView.swift` and `InboxView.swift` without complete replacements will break any code path still referencing those symbols. `AppRoot` in this worktree appears rewired, but **daemon relay E2E** and **publish checklist B10** still assume approval surfacing that the harness has not been updated for.

---

Audit performed against git diff on 2026-07-06. Cross-check with [consolidated status](../../product/2026-07-06-lancer-consolidated-status.md).
