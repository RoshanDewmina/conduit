# Siri / App Intents simulator dogfood — 2026-07-19

Lease: **`lease-229`** (iPhone 17 Pro clone, iOS 27.0, UDID `777C98AB-F4A5-4DDC-97F8-7DCCC01FA217`)  
Branch: `fix/siri-sim-and-aesthetics` (widget tip + Siri phrase harness + aesthetics)  
Worktree: `/Volumes/LancerDev/worktrees/lancer/siri-sim-and-aesthetics`

## Inventory — Siri / App Intents surfaces

### App Shortcuts (`Lancer/LancerAppShortcuts.swift`) — 9 registered

| # | Intent | Shortcut short title | Notes |
|---|--------|----------------------|-------|
| 1 | `AgentStatusQueryIntent` | Agent Status | Read-only |
| 2 | `PendingApprovalsQueryIntent` | Pending Approvals | Read-only |
| 3 | `PauseRunIntent` | Pause Run | Empty-state OK |
| 4 | `StopRunIntent` | Stop Run | Confirmation when run resolves |
| 5 | `DenyApprovalIntent` | Deny Approval | Safety-reducing; Approve is **not** a shortcut |
| 6 | `SearchLancerIntent` | Search | |
| 7 | `OpenConversationIntent` | Open Conversation | Disambiguation / pick |
| 8 | `StartAgentRunIntent` | Start Agent Run | Confirmation-gated dispatch |
| 9 | `AnswerQuestionIntent` | Answer Question | iOS 18+ |

**Explicit non-shortcut:** `ApprovalActionIntent` (Live Activity Approve/Reject only — never in `AppShortcutsProvider`).

Static sim build evidence (`Lancer.app/Metadata.appintents/extract.actionsdata`):
- `autoShortcuts` = **9** items — see `autoShortcuts.json`
- `ApprovalActionIntent` exists under `actions` (LA “Respond to Approval”) but is **not** in `autoShortcuts`
- No fictional `Approve*Intent` action keys

### Entities (`Packages/LancerKit/Sources/IntentsKit/`)

`ConversationEntity`, `RunEntity`, `MachineEntity`, `WorkspaceEntity`, `ApprovalEntity` + indexed/syncable query support.

## Results matrix

| Check | Command / method | Result | Evidence |
|-------|------------------|--------|----------|
| IntentsKit unit | `cd Packages/LancerKit && swift test --filter IntentsKitTests` | **PASS** 62 / 11 suites | SwiftPM host |
| RunningAgentsMapping + SiriNavigation | `swift test --filter 'RunningAgentsMappingTests\|SiriNavigationTests'` | **PASS** 19 / 5 suites | SwiftPM host |
| LiveActivity → Agents widget (incl. dedupe) | `simurgh exec lease-229 -- xcodebuild -scheme LancerKitTests -only-testing:…/LiveActivityRunningAgentsWidgetTests test` | **PASS** 5 / 1 suite | xcresult under lease-229/Results |
| App-target build (sim) | `simurgh exec lease-229 -- xcodebuild … build` | **PASS** `BUILD SUCCEEDED` ~154s | lease-229 DerivedData |
| Install + launch | `simctl install` + `simctl launch booted dev.lancer.mobile` | **PASS** pid launched | screenshot `01-app-launch.png` |
| Static metadata: 9 shortcuts, no Approve | Parse `extract.actionsdata` | **PASS** | `autoShortcuts.json` |
| Phrase 7 OpenConversation discoverable | AppIntentsTesting live suite | **PASS** | sim |
| Phrase 8 StartAgentRun discoverable (no dispatch) | AppIntentsTesting live suite | **PASS** | sim |
| Catalog of 9 shortcut intents discoverable | `testRegisteredShortcutIntentsAreDiscoverable` | **PASS** | sim |
| Phrase 10 negative Approve | `testPhrase10_…` + metadata | **PASS** | sim (fictional Approve* `run()` fails as expected) |
| Phrases 1–6, 9 live `run()` | `LANCER_APPINTENTS_LIVE=1` on sim | **FAIL (expected)** | `AppIntentsServicesSecurityErrorDomain` **Code=800** — sim `linkd` rejects unvalidated team identity (`Your app does not have permission… Bundle ID: dev.lancer.mobile`). Same finding as 2026-07-15 AgentStatus live note. Device dogfood (#186) remains the live `run()` proof. |
| AgentStatus live `run()` | same | **FAIL (expected)** Code=800 | sim |

## Aesthetic fixes (same branch)

| Issue | Before | After |
|-------|--------|-------|
| Duplicate “2 agents” / identical `Claude Code · host` lines | ActivityKit could expose in-process + push-to-start Activities for one run | Dedupe by `(agent, hostID\|host)` in `LiveActivityRunningAgentsWidget`; widget read-path also collapses identical lines |
| Visual polish | Ad-hoc colors; medium title “Lancer”; `ForEach(id: \.self)` fragile on dupes | Shared orange/green/black palette with Live Activity island; “Agents” / “Idle” hierarchy; enumerated line IDs; truncation |

## Gaps (honest)

- **Owner voice / spoken Siri** — not automated; use device checklist in `docs/test-runs/2026-07-19-siri-shortcuts-phrase-dogfood.md`
- **Sim live `intent.run()`** — blocked by linkd Code=800 (documented, not a product regression)
- **StartAgentRun / OpenConversation full interactive `run()`** — discovery-only in automation
- **Mutation paths** (pause/stop/deny/answer with live work) — need paired device + live run/approval

## Verification gate report

```text
Verification:
- SwiftPM: PASS — IntentsKitTests (62), RunningAgentsMapping+SiriNavigation (19)
- Xcode app target: PASS — simurgh lease-229 build SUCCEEDED; install+launch OK
- iOS package tests: PASS — LiveActivityRunningAgentsWidgetTests (5) via LancerKitTests scheme
- AppIntents live on sim: FAIL expected — Code=800 for perform(); discovery + negative Approve PASS
- Go daemon: skipped (no daemon changes in aesthetics commit)
- Owner-gated: spoken Siri + device live run() already covered by PR #186 dogfood
- Dirty files: see git status at commit time
```
