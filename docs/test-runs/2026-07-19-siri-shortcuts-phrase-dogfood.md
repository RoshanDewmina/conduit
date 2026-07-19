# Siri / Shortcuts phrase dogfood — 2026-07-19

Owner-style phrases 1–9 (+ negative Approve) on production phone
`557A7877-F729-5031-9606-0E04F2B67822` / hardware `00008150-0001653C26F8401C`.

## Preflight

| Check | Result |
|---|---|
| Lancer installed (`dev.lancer.mobile`) | Yes (v1.0.0 / 2) |
| App launch | Yes (`devicectl device process launch`, Workspaces) |
| `lancerd` resident | OK (`doctor`: 12 OK / 4 warn / 0 fail; relay paired) |
| Queue pending | `[]` |
| Active agent runs | None (`agent.sessions.list`: historical/completed only) |
| Hey Siri / Shortcuts UI automation | Not available (Mac `shortcuts list` is Mac-local; idb/pyat no physical target; phone UI not driveable without owner) |

## Method

Primary: `AppIntentsTesting` live XCTest on device with `TEST_RUNNER_LANCER_APPINTENTS_LIVE=1`
(`LancerUITests/LancerShortcutsPhraseLiveExecutionTests.swift`), same out-of-process
path as prior `AgentStatusIntentLiveExecutionTests` PASS.

Companion static: `Lancer.app/Metadata.appintents/extract.actionsdata` `autoShortcuts`
lists exactly the nine registered phrases; **no Approve** shortcut.

Logs: `/tmp/lancer-appintents-phrases-test2.log`,
`/tmp/lancer-appintents-phrases-result.xcresult`.

## Results

| # | Phrase / intent | Method | Result | Evidence | Notes |
|---|---|---|---|---|---|
| 1 | Agent status (`AgentStatusQueryIntent`) | AppIntentsTesting `run()` | **PASS** | testPhrase1 passed (~2.5s) | Also prior session PASS |
| 2 | Pending approvals (`PendingApprovalsQueryIntent`) | AppIntentsTesting `run()` | **PASS** | testPhrase2 passed (~4.0s) | Empty queue → “no approvals” path |
| 3 | Pause run (`PauseRunIntent`) | AppIntentsTesting `run()` | **PASS** (empty-state) | testPhrase3 passed (~3.5s) | No active run; mutation path **SKIP** |
| 4 | Stop run (`StopRunIntent`) | AppIntentsTesting `run()` | **PASS** (empty-state) | testPhrase4 passed (~3.4s) | No active run; confirm+stop **SKIP** |
| 5 | Deny latest (`DenyApprovalIntent`) | AppIntentsTesting `run()` | **PASS** (empty-state) | testPhrase5 passed (~3.6s) | No pending; real deny **SKIP** |
| 6 | Search Lancer (`SearchLancerIntent`) | AppIntentsTesting `run()` + `query=pong` | **PASS** | testPhrase6 passed (~3.5s) | Opens app when run |
| 7 | Open conversation (`OpenConversationIntent`) | Discovery only | **PASS** (discoverable) | XCTAssertNotNil; full `run()` needs interactive pick (Code 206) | Owner Shortcuts/Siri still needed for end-to-end open |
| 8 | Start agent run (`StartAgentRunIntent`) | Discovery only (no dispatch) | **PASS** (discoverable; not auto-dispatched) | testPhrase8; intentional no `run()` | Owner must confirm+cancel in Shortcuts/Siri |
| 9 | Answer question (`AnswerQuestionIntent`) | AppIntentsTesting `run()` + `answer=yes` | **PASS** (empty-state) | testPhrase9 passed (~3.4s) | No unanswered question; real answer **SKIP** |
| 10 | Negative: Approve by voice | Metadata `autoShortcuts` + AppIntentsTesting (fictional Approve* `run()` must fail) | **PASS** | autoShortcuts = 9 intents, no Approve; testPhrase10 passed (~4.7s) after harness fix; `ApprovalActionIntent` exists for Live Activity only (“Respond to Approval”) | Owner should still say “Approve the pending command in Lancer” once to confirm Siri does not map it |

Suite: phrases 1–6, 8–9 live `run()`/`discover` PASS; phrase 7 discoverable PASS (interactive open needs owner); phrase 10 PASS (metadata + live).

## What could not be automated

- Spoken Hey Siri for any phrase
- Shortcuts app UI browse/run on the physical phone (no idb/pyat/XcodeBuildMCP device UI in this session)
- Pause/Stop/Deny/Answer **mutation** paths (no live run / pending approval / question)
- StartAgentRun confirm→progress→cancel without risking a real dispatch

## Owner voice checklist (remaining)

1. Shortcuts → search “Lancer” → confirm all 9 actions listed; **no Approve**
2. Run **Agent Status** and **Pending Approvals** from Shortcuts (compare to live XCTest)
3. “Hey Siri, how many agents are running on Lancer”
4. “Hey Siri, are any approvals waiting in Lancer”
5. With a real active run: pause, then stop (confirm)
6. With a real pending approval: deny latest (confirm) — never approve by voice
7. “Hey Siri, search Lancer” / open a conversation
8. “Hey Siri, start an agent run in Lancer” → walk confirms → **Cancel**
9. Negative: “Hey Siri, approve the pending command in Lancer” → must **not** become a Lancer Approve action
