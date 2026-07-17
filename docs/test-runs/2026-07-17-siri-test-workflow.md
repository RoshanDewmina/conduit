# Siri / App Intents test workflow — 2026-07-17

**Does the iOS 27 deep integration work?** Code-wise yes, and it's in the TestFlight build you
just uploaded (delivery `2c17f676`, tip `639ba8da`): PR #167 made the iOS-27 long-running path
unconditional — `StartAgentRunIntent.perform()` now always uses
`LongRunningIntent`/`CancellableIntent`/`ProgressReportingIntent` (Siri's "your agent is working
on it" background execution with progress). What has NEVER been proven is live Siri behavior on
a physical device — that needs your voice and your phone. This is the workflow.

## Registered Siri surface (Lancer/LancerAppShortcuts.swift)

| Phrase (say "…in Lancer") | Intent | Risk class |
|---|---|---|
| "How many agents are running in Lancer" | AgentStatusQueryIntent | read-only |
| "Are any approvals waiting in Lancer" | PendingApprovalsQueryIntent | read-only |
| "Search Lancer" / "Search my Lancer conversations" | SearchLancerIntent | read-only |
| "Open a conversation in Lancer" | OpenConversationIntent | read-only |
| "Pause the agent in Lancer" | PauseRunIntent | safety-reducing |
| "Stop the agent in Lancer" | StopRunIntent | safety-reducing |
| "Deny the latest approval in Lancer" | DenyApprovalIntent | safety-reducing |
| "Start an agent run in Lancer" / "Start Claude Code in Lancer" | StartAgentRunIntent | dispatch (confirms everything first) |
| "Answer the question in Lancer" (iOS 18+) | AnswerQuestionIntent | interactive |

**Deliberately absent:** approve-by-voice. `ApprovalActionIntent` is never registered with Siri —
approving stays visual (in-app / Live Activity tap). Don't "fix" this.

## Prerequisites (once)

1. Install the TestFlight build (or a device build) on the iPhone. **Launch the app once** —
   App Intents metadata registers with the system on first launch; Spotlight/Siri may take a
   minute after that.
2. Daemon running + phone paired (currently true: pair confirmed live 07-17).
3. Siri enabled; for best results say "Lancer" clearly — if Siri mishears the app name,
   rename trick: Settings → Apps → Lancer has no rename, but a custom Shortcut wrapping the
   intent gives you any phrase you want (step 5).

## Test ladder — cheapest first, each step isolates a different failure

**Step 1 — Shortcuts app (no voice, proves intents + metadata).**
Open Shortcuts → + → search "Lancer". All 9 actions above should be listed. Add "Agent Status"
→ run it from Shortcuts. Expected: a spoken/visible dialog with the live agent count.
If actions are missing → metadata didn't merge (report back; that's a build issue, not Siri).

**Step 2 — read-only voice.**
"Hey Siri, how many agents are running in Lancer" → same dialog by voice.
Failure here with Step 1 passing = phrase-recognition issue, not app issue; try the exact
phrases from the table (they're the trained ones).

**Step 3 — safety-reducing voice.**
With a run active (dispatch one from the app first): "Hey Siri, pause the agent in Lancer",
then "…stop the agent in Lancer". Expected: confirmation, then the run actually
pauses/stops (verify in-app + `~/.lancer/audit.log` on the Mac shows the control action).

**Step 4 — the deep iOS-27 path (the real test).**
"Hey Siri, start an agent run in Lancer."
Expected sequence: Siri walks machine → agent → workspace → prompt confirmation (it never
auto-runs), then the long-running progress UI ("working on it") while the run executes, with
cancel support. Try it once with the phone LOCKED too — the intent should still confirm and
report progress. Watch for: progress updates actually appearing (ProgressReportingIntent),
and cancellation working mid-run (CancellableIntent).

**Step 5 — ergonomic phrases (optional).**
Shortcuts → create a shortcut wrapping StartAgentRunIntent with preset machine/agent/prompt →
name it e.g. "Ship it" → "Hey Siri, Ship it". This is also the workaround if Siri keeps
mishearing "Lancer".

## Known caveats

- iOS 27 beta Siri can be flaky about newly-installed apps' phrases for ~a few minutes after
  first launch; retry after opening the app once more.
- `AnswerQuestionIntent` needs a pending agent question to do anything visible.
- Simulator is NOT a valid rig for voice — Shortcuts-app invocation works there, but
  voice + lock-screen behavior only proves out on hardware.

## Evidence to capture

Per intent tested: phrase used → what Siri showed/said → in-app effect → (for step 3/4) the
matching `audit.log` line. Drop results in this file or tell the orchestrator and it'll file
them + any failures as issues.
