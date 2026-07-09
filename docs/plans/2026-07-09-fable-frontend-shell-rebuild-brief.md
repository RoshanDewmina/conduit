# Fable brief — Cursor shell view wipe + Orca-informed rebuild

**Date:** 2026-07-09  
**Branch context:** `feat/chat-overhaul-w0a` (history keeps the old UI; wipe is intentional)  
**Owner decision:** Hybrid wipe — delete view chrome, keep live bridge + transcript/streaming engine + backend. Research competitors (Orca primary), then one-shot a new SwiftUI shell against the existing contract.

Use this document as the full prompt for Fable (or any executor). Do not paraphrase the KEEP contract into a weaker summary — attach / open the cited files.

---

## Exact ask

Rebuild Lancer’s **iOS Cursor shell view layer** from a clean slate after competitor research, while **preserving** the live bridge contract, AppRoot wiring, transcript/streaming engine, and all backend/transport.

**Two phases, one CLOSED gate:**

1. **Phase R — Research (read-only):** Mine Orca (MIT) + existing port map; produce a short Port-to-Lancer design note with file:line evidence.
2. **Phase B — Rebuild:** Delete the approved view-chrome WRITE-SET, implement a new 3-root shell + chat that satisfies the Done-bar against `CursorShellLiveBridge` + `AppRoot` wiring unchanged in behavior.

**CLOSED** only when Phase B Done-bar is green (build + tests + on-device smoke listed below).  
Phase R alone is **not** closed.

---

## Why this is blocked / what already failed

- Incremental bug-fix on the current shell loses to layout/nav debt (pair doesn’t land on machine; workspace start-chat blocked; composer sheet goes full-screen; 2nd message UI stale until reopen).
- Owner rejected “fix each little bug.” Second opinion rejected “delete everything under CursorStyle / AppFeature UI.”
- Hybrid is the approved path: wipe **pages**, keep **contract + engine**.
- Tip has dirty WIP on shell/bridge/relay files — **land or stash before wipe**; do not silently discard other agents’ work (`AGENTS.md`).

---

## Non-negotiable constraints

1. **Phone steers and approves — not a phone IDE.** Governance + dispatch is the product.
2. **IA:** `ARCHITECTURE.md` §4.1 — **Home / Workspaces / Settings** (3-root). Do **not** reintroduce a tab bar named Control/Activity. `enum Tab` in `AppRoot` is vestigial.
3. **Launch seams must keep working:**
   - `LANCER_CURSOR_SHELL=1` — mock/seeded shell for UITests
   - `LANCER_CURSOR_SHELL_LIVE=1` — live bridge via `AppRoot` → shell
4. **Deep-link route names must survive** (Siri / APNs / Live Activity destinations):
   - `workspaceThreadList(String)`
   - `workThread(String?)`
   - `prDetail` / `reviewDiff` (can be stub destinations, but names stay)
5. **Competitor license discipline:**
   - Orca: MIT — patterns + logic portable with attribution comment (`stablyai/orca` + source path)
   - Happier: treat as patterns-first; re-check `LICENCE` before any verbatim logic
   - Omnara: Apache-2.0 — portable with attribution
   - **Never** commit competitor clones or copy React/RN UI verbatim — re-implement in SwiftUI
6. **No product/backend redesign.** Do not rebuild Layer 3 Live Activity / content-hash / push-to-start. Do not start Layer 1 proof-receipt product work unless the shell must *display* existing receipt/question cards.
7. **Security fail-closed.** No biometric reintroduction. Never log secrets.
8. **Verify before done.** LancerKit: `cd Packages/LancerKit && swift build` (+ `swift test` for behavior). App shell: XcodeBuildMCP app-target build. On-device smoke for Done-bar items that need a phone.

---

## KEEP (do not delete; Fable must not rewrite behavior)

### Contract (hand to Fable verbatim)

| Artifact | Path | Role |
|----------|------|------|
| Live bridge | `Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorShellLiveBridge.swift` | **The API contract** — `@Observable` state + closures |
| Env injection | `CursorShellLiveEnvironment.swift` | Environment key |
| Wiring hub | `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` | Especially `cursorShellRoot` + bridge closure population (~946–1245 and env inject sites ~665/773/794) — **behavioral spec** |
| Launch seam | `CursorShellLaunchSeam.swift` (+ tests) | DEBUG launch routing |

Bridge closures that must keep working (non-exhaustive; open the file):  
`onDispatch`, `onContinue`, `onOpenThread`, `onPollThread`, `onSearch`, `onDecide`, `onAcceptReceipt`, `onAnswerQuestion`, `onRequestPairing`, `onOpenReview`, `onPaired`, `onClearInvalid`, `onRemoveTrustedMachine`, `onClearAllPairings`, `onResetAppData`, `onImportObservedSession`, `onRequestRefresh`, `lookupApproval`.

Bridge state that views must observe:  
`workspaces`, `threadsByWorkspace`, `pendingApprovalID` / `pendingApproval`, `repoPaths`, `composerCWD`, `selectedThreadID`, `activeThread*`, `activeRunID`, `activeThreadArtifacts`, `connectionPhase`, `threadAttention` / `threadStates`, `trustedMachines`, `observedSessions`, composer model/run-target fields.

### Engine (keep; may call from new views; do not throw away)

- `CursorTranscriptMapper.swift`
- `CursorThreadTranscriptModel.swift`
- `CursorStreamingTextPacer.swift`
- `CursorStreamingTextSmoother.swift`
- `CursorTranscriptAutoScrollPolicy.swift`
- `CursorMarkdownPreprocessor.swift`
- `CursorAssistantMarkdownView.swift` *(renderer helper — keep or thin-wrap; do not drop MarkdownUI path)*
- `CursorThreadAttention.swift`
- `CursorComposerDraftStore.swift`
- `CursorTrustedMachineModel.swift`
- `CursorObservedSessionsSection.swift` *(mapping/importer glue — UI chrome around it may be replaced)*

### Outside CursorStyle (untouchable unless compile break)

- `SessionFeature/Chat/*` — `ReceiptCardView`, `QuestionCardView`, `ProofReelView`, answer resolvers
- `IntentsKit/*`, `NotificationsKit/*`, `LiveActivityManager` / presentation
- `ApprovalRelay`, `ConversationSyncCoordinator`, `ChatConversationRepository`
- `RelayFleetStore`, `E2ERelayClient`, pairing Keychain paths
- Daemon / push-backend / agent-runner

### Tests that must stay green (adapt only if APIs they cover move)

- `CursorShellLiveBridgeTests.swift`
- `CursorShellLaunchSeamTests.swift`
- `CursorThreadTranscriptModelTests.swift`
- `CursorChatPolishSlice1Tests.swift`
- `CursorConversationSearchSupportTests.swift`
- `CursorTrustedMachineModelTests.swift`
- `CursorObservedSessionMappingTests.swift`
- `CursorComposerContractTests.swift`
- `CursorDesignTokenTests.swift`
- UITests under `LancerUITests/` that target Cursor shell — update selectors if chrome changes, do not delete coverage of live approval loop

### Reference docs (read; do not “fix” unless status lines require it)

- `ARCHITECTURE.md` §0.1 + §4.1
- `docs/product/2026-07-09-chat-ui-port-map.md`
- `docs/design-audit/2026-07-08-cursor-shell-frontend-audit.md` (known-bug catalog — **must not regress**)
- `docs/design-audit/lancer-ia-2026-07-08/` + workflow wireframes under `docs/design-audit/lancer-workflows-2026-07-05/`
- `docs/LIVE_LOOP_RUNBOOK.md` (Tier 0 procedure)
- Competitor clones (gitignored): `research-repos/orca` (MIT), `research-repos/happier`, `research-repos/omnara`

---

## DELETE / replace (view chrome only)

Safe to delete and replace with new SwiftUI (approx. the “frontend pages”):

- `CursorAppShell.swift`
- `CursorWorkspacesView.swift`
- `CursorWorkspaceThreadListView.swift`
- `CursorWorkThreadView.swift` *(scaffold only — keep using mapper/model/pacer/attention)*
- `CursorProfileDrawer.swift`
- `CursorSettingsView.swift`
- `CursorTrustedMachinesView.swift`
- `CursorOnboardingView.swift`
- `CursorReviewDiffView.swift` *(mock path; AppRoot live Review sheet must still exist — rebuild a Review surface wired to `pendingApproval` / `onDecide` / `onOpenReview`)*
- `CursorPRDetailView.swift`, `CursorDiffView.swift` (mock OK)
- `CursorSearchOverlay.swift`
- `CursorRepoPickerSheet.swift`, `CursorRunOnSheet.swift`, `CursorModelSheet.swift`
- `CursorComposerSheet.swift` *(replace with docked composer — do not bring back full-screen sheet as primary)*
- `CursorShipActionSheet.swift`, `CursorContextSheet.swift`, `CursorCommitsSheet.swift`, `CursorWorkspaceDetailSheet.swift`
- `CursorReturnPacketView.swift`
- `CursorRelayPairingSheet.swift` *(rebuild pairing UI; keep calling `onPaired` / `onRequestPairing` — pair-once, no mid-run code rotation)*
- `Components/*` ornaments as needed (`CursorBottomComposer`, banners, etc.) — recreate under new design system tokens if required

**After delete:** `AppRoot.cursorShellRoot` must compile against a **new** root shell view that accepts `liveBridge: CursorShellLiveBridge`.

---

## Phase R — Research (before writing UI)

Read-only. Produce `docs/plans/2026-07-09-orca-shell-port-design.md` (or update the existing port map with a “Shell rebuild” section) covering:

| Lancer requirement | Primary donor | What to port (logic, not React) |
|--------------------|---------------|----------------------------------|
| Post-pair → land on that machine/workspace | Orca `mobile/app/pair-confirm.tsx` → `router.replace(/h/{hostId})` | Atomic nav: dismiss settings/pairing → select machine → Workspaces (replace semantics) |
| Start chat from named workspace opens thread | Orca `launch-agent-in-new-tab.ts` + `native-chat-view-state.ts` | Successful new dispatch always activates conversation surface; never silent stay on list |
| Docked composer / keyboard not full-screen | Orca `NativeChatView.tsx` column + mobile `keyboardLift` translate | Transcript `flex-1` + composer `shrink-0`; lift dock with keyboard; **no** primary full-screen composer sheet |
| 2nd+ message live update | Orca `native-chat-pending.ts` + streaming overlay + incremental append | Optimistic user bubble every send; streaming overlay; don’t clear pending on session-id discovery |
| Markdown + tool/artifact cards | Orca fold/summary + existing Lancer MarkdownUI / Receipt/Question cards | Prose then tools; fold + summary + 4KB cap; keep receipt/question kinds |

Also skim Happier for streaming throttle / tool state machine **patterns only** (already sketched in port map).

**Attribution comment shape** on ported logic:

```swift
// Ported from stablyai/orca (MIT): src/renderer/src/components/native-chat/<file>
```

---

## Phase B — Rebuild requirements (product behavior)

### Navigation / IA

1. **3 roots:** Home / Workspaces / Settings (wireframe-faithful; pick TabView or equivalent — but roots must exist; current code’s Workspaces-only root is **debt to fix**, see audit P0-1).
2. **Post-pair:** on `onPaired` success, user lands on that machine’s workspace context — **not** left in Settings.
3. **Start chat:** from All Repos **and** named workspace, successful send opens `workThread` and shows the conversation. Named workspace must resolve CWD via `repoPaths` or a host path discovery path — never dead-end with “path unknown” and no navigation.
4. **Open existing thread:** `onOpenThread` loads real content into `activeThread*`.
5. **Approval recovery:** banners + `onOpenReview` from Home/Workspaces/thread list when `pendingApprovalID` set (audit P0-2).
6. **Review surface:** shows **real** `pendingApproval` / `lookupApproval` command/risk — never hardcoded terraform example (2026-07-07 bug).

### Chat layout (Orca-informed)

7. Thread screen = column: scrollable transcript above, **docked** composer below.
8. Keyboard lifts the dock; does **not** present a `.large` full-screen sheet as the primary typing UI.
9. Cap composer growth (few lines); transcript remains visible.

### Live updates

10. First **and** subsequent sends show user bubble immediately (optimistic / pending).
11. Streaming assistant text updates in place via bridge `activeThreadResponse` + existing pacer/smoother.
12. Follow-up turns must not require leave/reopen (`CursorTranscriptMapper` live-overlay rules must support Nth turn — fix engine if needed; this is the one engine file Fable may patch).

### Markdown / artifacts

13. Assistant markdown via existing MarkdownUI path + preprocessor.
14. Inline artifacts: at least `.receipt` → `ReceiptCardView`, `.question` → `QuestionCardView`; tool cards if ledger emits them (Orca fold/summary).

### Settings / machines

15. Trusted machines list from bridge; Remove / Clear pairings / Reset app data call bridge hooks (no-op stubs are **bugs**).
16. Pairing sheet: enter code / QR → `onPaired`; pair once.

### Known bugs that must not return

From `docs/design-audit/2026-07-08-cursor-shell-frontend-audit.md` + bridge comments:

- P0-2 dismissed Review with no recovery  
- P0-3 Review blank/stale after decide  
- P0-4 Run-target picker no-op  
- Composer CWD sent as bare repo name (must use `repoPaths` absolute path)  
- `pendingApproval` observability race  
- Search filtering hardcoded rows (must use `onSearch`)  
- Force-light / token regressions where A3 already fixed dark/light  

---

## Suggested implementation order

1. Stash/commit dirty WIP on current branch (owner/agent hygiene) — do not wipe mid-dirty-tree.
2. Phase R design note committed.
3. Introduce new shell root stub that compiles with `AppRoot` + empty destinations.
4. Delete old view chrome WRITE-SET; fix compile breaks only in AppRoot call sites / imports.
5. Implement 3-root chrome + pairing + post-pair nav.
6. Implement workspaces → thread list → work thread + docked composer.
7. Wire dispatch/continue/openThread/search/approvals.
8. Fix mapper/pending for Nth-message live update if still broken.
9. Settings + trusted machines + pairing.
10. Verification gate.

---

## Done-bar (CLOSED only when all green)

| # | Gate | Evidence |
|---|------|----------|
| D1 | `cd Packages/LancerKit && swift build` | exit 0 |
| D2 | `swift test` for Cursor* / bridge / transcript suites | 0 failures |
| D3 | XcodeBuildMCP app-target `build_sim` (scheme `Lancer`) | SUCCEEDED |
| D4 | Mock shell: `LANCER_CURSOR_SHELL=1` launches, 3 roots visible | screenshot or UITest |
| D5 | Live shell on device/sim with daemon: pair → lands on machine/workspace | host + phone note |
| D6 | Start chat from **named** workspace → thread view opens + dispatch | audit `conversation-append-launched` |
| D7 | Docked composer: keyboard does not take full screen; transcript visible | screenshot |
| D8 | Second message in same thread updates live without leave/reopen | screenshot / screen record |
| D9 | In-app approve still works (`onDecide` → host audit) | audit line |
| D10 | No KEEP-file behavior regressions in listed unit tests | as D2 |

Optional follow-up (not blocking shell CLOSED): Layer 0 / 5c lock-screen re-proof on new tip → `docs/test-runs/YYYY-MM-DD-tier0-device-proof-results.md`.

---

## Out of scope

- Deleting or rewriting `CursorShellLiveBridge` API surface (additive fields OK if documented)
- Rewriting `AppRoot` business logic (only adapt to new root view type)
- Daemon / push-backend / Live Activity content-hash work
- Full PR/ship git product (stubs OK)
- Away Mode / Watch
- Wholesale merge of any worktree

---

## Fable output expectations

1. Phase R design note with Orca file:line → Lancer mapping  
2. New SwiftUI shell under `AppFeature/CursorStyle/` (or clearly named successor package folder if you must rename — update `AppRoot` + ARCHITECTURE §4.1 in the same change)  
3. Deleted old view chrome; KEEP list intact  
4. Attribution comments on ported logic  
5. Verification evidence pasted (commands + results)  
6. Short owner walkthrough: how to launch mock vs live, and the D5–D8 tap script  

**Stop and ask the owner** if: pairing blocks the run, KEEP files appear to require a breaking bridge API change, or a compile break forces touching daemon/relay beyond import fixes.
