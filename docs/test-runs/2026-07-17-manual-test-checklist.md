# Manual test checklist — physical iPhone, Debug device build

**Date:** 2026-07-17
**Tip tested against:** `master` @ `bba98bb4` (docs-only past the 2026-07-16 sweep tip `62b4424d`)
**Audience:** owner, walking the app end-to-end on their own iPhone with a Debug (device) build,
paired to their production `lancerd`.
**Goal:** every user-facing surface that exists in the app today, grounded in code/docs — nothing
invented. Walkable in under an hour; fast/cheap checks are grouped so you're not hunting for edge
cases between them.

**How to read severity:** **P0** = the governed-approval loop or data safety is broken, ship-blocking.
**P1** = a real, frequently-hit feature is broken or misleading. **P2** = cosmetic/polish, doesn't
block using the app. Items marked **PROOF OWED** are exactly the checks the 2026-07-16/17 sweeps
could not close live on your phone — these are the load-bearing ones; a fail here is a real
regression, a pass is new evidence, not a re-confirmation of something already proven.

**Sources mined this session** (see full list at the bottom): `ARCHITECTURE.md` §0.1/§4.1,
`docs/test-runs/2026-07-16-untested-feature-sweep/GAP_LIST.md` +
`DOGFOOD_DEVICE_WALKTHROUGH.md`, `docs/appstore/SUBMISSION_CHECKLIST.md`,
`docs/test-runs/2026-07-17-siri-test-workflow.md`, and the actual Swift source under
`Packages/LancerKit/Sources/AppFeature/**` (Settings, Workspaces, Composer, Chat, ThreadList,
ThreadDetail, Review, Terminal, Profile, Onboarding).

---

## 0. Setup

- [ ] Confirm `lancerd` is running on the host and `~/.lancer` is the **production** state dir
      (not a sweep's isolated `/tmp/...` dir). `ps aux | grep lancerd`; check uptime. — [P0]
- [ ] Build a **Debug** configuration for a physical device (not Release/TestFlight — Debug
      unlocks `LANCER_DESTINATION` deep-links if you need to jump to a screen; not required for
      this walk but keep it in mind if a step needs isolating). Install + launch once so App
      Intents/Siri metadata registers with the system (`docs/test-runs/2026-07-17-siri-test-workflow.md`
      prerequisite #1). — [P1]
- [ ] Confirm phone is already paired (or plan to re-pair fresh in §1). Check `~/.lancer/relay-pairing.json`
      exists and the daemon log shows a recent `paired with phone` line. — [P0]

---

## 1. First-run / onboarding gate

*(Skip to §2 if already paired and you don't want to burn your one pairing slot — note whether
you tested this fresh or from memory.)*

- [ ] Fresh install (or reset via Settings → General → Reset if you want a true first-run):
      first screen shows the **welcome explainer** — "Lancer / Mission control for AI coding
      agents" copy (`OnboardingGateView.swift:56-63`). — [P2]
- [ ] Tap **Continue** → **"Pair a Machine"** screen: "Connect this phone to a host that runs
      `lancerd`" (`OnboardingGateView.swift:96-111`). — [P1]
- [ ] Confirm **"Skip for now"** exists and actually lets you into the app without pairing
      (`OnboardingGateView.swift:118-126`) — the app must not hard-block on pairing. — [P1]
- [ ] Complete pairing via the pairing code flow (see §7 Trusted Machines for the sheet detail);
      confirm you land on the Workspaces home afterward. — [P0]

---

## 2. Workspaces home

(`Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift`)

- [ ] Home shows a large "Workspaces" title, a top bar with **search** (magnifying glass) and
      **new-chat** (+) circle buttons (`WorkspacesView.swift:391-407`). — [P1]
- [ ] Tap the **profile avatar** (top-left area) → Profile sheet opens (see §8). — [P1]
- [ ] **Pending-approvals banner** appears at the top of the list only when a real approval is
      waiting (`PendingApprovalsBanner`); tapping it should focus the right machine and open a
      live thread at that approval's cwd (`WorkspacesView.swift:57-63`). If nothing is pending,
      confirm the banner is simply absent (no empty placeholder). — [P1]
- [ ] **"All Repos"** row shows a live thread count and opens `ThreadListView(.allRepos)`
      (`WorkspacesView.swift:65-74`) — this is the #149 "instant cache paint" fix; rows should
      paint immediately on cold reopen, not spinner-then-paint. **PROOF OWED** (WT-C found the
      header spinner never resolves on return-visit even though rows paint — check if that's
      still true). — [P1]
- [ ] Each **repo row** shows folder icon + name + thread count, opens that repo's thread list
      (`WorkspacesView.swift:89-104`). If you have zero repos, confirm the honest empty state
      ("Add a repo to get started") instead of a fake row. — [P2]
- [ ] **"Add Repo"** row opens `AddRepoView` sheet; add a repo by name + cwd and confirm it now
      appears in the list (`WorkspacesView.swift:106-116, 185-189`). — [P1]
- [ ] **Running Agents section**: if an agent is actively running (dispatched outside the app,
      e.g. a bare CLI session), it should list here; tapping it should open/attach the matching
      live thread (`RunningAgentsSection`, `WorkspacesView.swift:120-132`). — [P1]
- [ ] Tap the **composer bar** at the bottom → it morphs in place (matched-geometry "inline
      expand", not a modal sheet) into the full composer (`WorkspacesView.swift:148-172`); tap
      the dimmed background to collapse it back. — [P1]

---

## 3. Composer / dispatch

(`Composer/NewChatComposerView.swift`, `Composer/ComposerDispatchPickerView.swift`)

- [ ] With the composer expanded, tap the **model/tools summary chip** — opens
      `ComposerDispatchPickerView` with: **vendor picker** (Claude Code / Codex / OpenCode / Kimi,
      filtered to what's actually installed on the host), and — only for Claude — a **model
      picker** (Haiku "fastest" / Sonnet "balanced" / Opus "highest quality") and a **Full tools**
      toggle ("Slower first reply; enables MCP tools") (`ComposerDispatchPickerView.swift:43-184`).
      Confirm switching vendor hides/shows the Claude-only rows correctly. — [P1]
- [ ] Tap the **attachment icon** → `ContextAttachView` sheet opens; attach a photo/file and
      confirm a chip appears in the composer with a thumbnail/name
      (`NewChatComposerView.swift:166, 190-203, 305-`). — [P1]
- [ ] Trigger an attachment upload failure path if you can (e.g. airplane mode momentarily) —
      confirm the composer shows a dismissable "no transport" banner rather than silently eating
      the attachment (`NewChatComposerView.swift:196-203, attachmentNoTransportBanner`). — [P2]
- [ ] **No mic/voice-dictation control exists in the composer** — this is intentional
      (`NewChatComposerView.swift:389`, "No decorative mic — empty draft shows no trailing
      control"). Confirm there is in fact no mic button; if one appears, that's new/unexpected
      behavior worth flagging, not a pass. — [P2]
- [ ] Type a prompt, pick a **repo/cwd** (composer requires a real selected repo, never a guessed
      path per the file's doc comment), hit send → a new live thread opens and the turn actually
      dispatches to the host. — [P0]

---

## 4. Live thread / chat surface

(`Chat/LiveThreadView.swift` + `Chat/*`)

- [ ] **Transcript renders** streamed assistant text with markdown (tables, code blocks) as the
      turn progresses (`ChatMarkdownAttributedString`/`ChatMarkdownTableView`). — [P0]
- [ ] **Tool-call chips**: a real run that calls tools (bash, edit, etc.) renders one distinct,
      correctly-labeled chip per call, not a "Bash Bash:" duplicate-label bug
      (`ToolCallChipView`/`ToolChipGrouping`). 2026-07-17 gap-reproof already found this **PASS**
      live (gap #14) — re-confirm it still holds. — [P1]
- [ ] **Thought process**: tap into a turn's "thinking" affordance
      (`ThinkingRow`/`ThoughtProcessSheet`) and confirm it opens and shows real reasoning text,
      not empty/placeholder. — [P2]
- [ ] **Turn diff card**: after a turn that edited files, a `TurnDiffCard` appears inline under
      that turn showing the file/hunk summary (`LiveThreadView.swift:659-660, 921-922`). — [P1]
- [ ] **Session diff pill**: a running/accumulating diff-summary pill shows near the top of the
      thread when the session has file changes (`SessionDiffPill`, `LiveThreadView.swift:252-266`). — [P1]
- [ ] **Proof reel / receipt**: tap the ⋯ on a completed "Worked Ns" row → Proof opens showing the
      command(s) actually run (`ProofReelView`/`ReceiptCardView`). This is the #147 fix — the
      DOGFOOD walkthrough logged this **PASS** live on phone once already; confirm it still is. — [P1]
- [ ] **Background-tasks pill**: with a run that spawns background/async tasks, a pill with a
      running count appears near the top and opens a sheet listing each task with live elapsed
      timers (`BackgroundTasksPill`/`BackgroundTasksSheet`, `LiveThreadView.swift:266-268,
      568-596`). 2026-07-17 gap-reproof called this **PASS** live (gap #10) but noted a **known
      minor bug: the pill can stay "Running" after the turn has actually completed** — check for
      that specifically. — [P1]
- [ ] **Permission-mode pill**: visible near the top of the thread (`ChatPermissionModePill`,
      `LiveThreadView.swift:274`). **Known finding (WT-A, still open as of 2026-07-16): this pill
      is display-only** — it writes to phone-local `@AppStorage` and is never sent to the daemon;
      an escalation still risk-gates under the *global* policy default regardless of what the
      pill shows. Confirm this is still true: set the pill to something permissive, then trigger
      an action that should escalate under `ask` — it should still escalate. **PROOF
      OWED / KNOWN BUG**, not a new find if it reproduces. — [P1]
- [ ] **Mid-run feedback queue**: while a turn is running, send a follow-up message from the
      docked composer at the bottom — confirm it queues visibly ("mid-run-feedback-caption") and
      is actually delivered to the agent once the turn is receptive, rather than silently dropped
      (`LiveThreadView.swift:150, 213, 295-302`). Prior sweeps found this **BLOCKED** under
      harness timing, never proven live. **PROOF OWED.** — [P1]
- [ ] **Pending approval card renders in-thread** (not just the Workspaces banner) when an
      escalation happens mid-conversation (`LiveThreadView.swift:1140` "Pending approval card"). — [P0]
- [ ] **Pending question card**: if the agent asks an in-thread question (distinct from a tool
      approval), confirm a question card renders and your answer round-trips
      (`LiveThreadView.swift:1206` "Pending question card"). — [P2]
- [ ] **Follow-up / continue same thread**: after a turn completes, send another message in the
      same thread — confirm it resumes the **same vendor session** (not a fresh session) per the
      `continue`/follow-up contract (`ARCHITECTURE.md` §0.1 "continue/follow-up"). DOGFOOD walk
      already proved this once (same `vendor_session_id` across ordinals). — [P0]
- [ ] **Live completion rendering**: after you approve/resume and the turn actually exits on the
      host, confirm the "Ran a command" chip flips from spinner/"Running" to "Completed" **without
      leaving the thread and re-entering.** Known bug (WT-B, 2026-07-16): the live event stream
      stopped applying terminal state, leaving a stale spinner for minutes even though the daemon
      had already recorded exit 0; re-entering rendered correctly. **PROOF OWED** — check if this
      still reproduces. — [P1]
- [ ] **Scroll-to-latest on open**: open a long existing thread — confirm it lands at the bottom
      (latest message), not the top. Known bug (WT-J): `scrollToTailIfFollowing` is gated on
      `isNearBottom`, which is false on open for a long thread, so it never fires — you have to
      tap the scroll-to-bottom arrow every time (`LiveThreadView.swift` per WT-J, cited lines
      164/549-551 in the sweep report). **PROOF OWED.** — [P2]
- [ ] **Top-right ⋯ menu on first entry**: open a live thread you haven't visited yet this
      session — confirm the ⋯ menu (Proof, etc.) is present immediately, not only after backing
      out and re-entering (WT-D). **PROOF OWED.** — [P2]
- [ ] **Hook/system artifact leakage**: watch an *observed* (non-Lancer-dispatched) desktop
      thread for raw JSON like `stop_hook_summary{"type":"pr-link",…}` rendering as literal
      message text instead of being filtered/decoded (WT-I). — [P2]
- [ ] **Desktop-thread live follow**: if you have a terminal session running on the desktop
      outside the app, open its observed thread in Lancer and confirm new desktop messages appear
      live without re-entering the thread (fixed 2026-07-16 per WT-H / PR #154 — re-confirm it
      still holds, don't assume the doc claim). — [P1]

---

## 5. Approvals & governance (the core loop)

- [ ] **In-app approval card**: trigger an action that needs approval (e.g. ask the agent to run
      a shell command under `ask` policy) → confirm the card shows command, cwd, and a risk band,
      with **Allow once / Allow always / Reject** (or Approve/Deny) actions
      (`ARCHITECTURE.md` §4.5). — [P0]
- [ ] **Approve** it → confirm the round trip completes in a reasonable time (prior proof: ~14s
      escalate→approve→exit) and the turn actually resumes/exits on the host. — [P0]
- [ ] **Deny/Reject** a separate escalation → confirm the host actually blocks that action (check
      the audit log line), not just a UI-only rejection. — [P0]
- [ ] **Risk scoring sanity check**: a genuinely read-only command (e.g. `ls -la`) should not be
      scored **High** — known miscalibration (WT-F) rated `ls -la` as High. Note whether it's
      still over-scored; this is a scoring-tuning bug, not a security bug. — [P2]
- [ ] **Live Activity / Dynamic Island**: with a run active, check the lock-screen/Dynamic Island
      Live Activity updates while the app is backgrounded (not just foregrounded) — this depends
      on push-token-driven updates (`LiveActivityManager`, ARCHITECTURE §0.1). — [P1]
- [ ] **Lock-screen push approval (APNs)**: lock the phone, trigger an escalation from another
      thread/session, and check whether an actual APNs push notification arrives on the lock
      screen (not just in-app relay delivery). **Known FAIL as of 2026-07-16 (WT-E):** no push
      arrived twice in a row; the daemon fell back to re-sending the pending approval over relay
      on reconnect, and approval had to happen in-app. Prime suspect: push-backend's in-memory
      device-token registry was wiped by a redeploy since the 2026-06-23 push-while-closed PASS.
      **PROOF OWED — this is the single most load-bearing check in this whole checklist**, since
      "approve from the lock screen while the app is closed" is the architecture's headline claim
      (`ARCHITECTURE.md` §0.1 "C2 physical-device live loop PASSED (2026-06-23)" — that proof
      predates the current regression). — [P0]
- [ ] **Approving directly from the Live Activity / lock-screen tap** (if a push does arrive):
      confirm tapping Approve there round-trips to the daemon even from a killed app (the
      "cold-decision gate" fix, ARCHITECTURE §0.1). Depends on the previous check passing first. — [P0]
- [ ] **Emergency Stop** (Settings → red section at the bottom, `AppSettingsView.swift:131-166`):
      tap it, confirm the destructive confirmation dialog text, confirm it. **Known confirmed
      FAIL (2026-07-17 gap-reproof, gap #1):** the app reports "Stopped N runs" and the daemon
      audit records `run-stopped`, but the actual host-side PreToolUse hook process gating a
      pending tool-call escalation was observed to stay alive 6+ minutes after the stop (had to
      be `kill -9`'d manually) — the stop resolves the dispatch-level approval, not the specific
      in-flight gate process. **Do this test with something you can safely manually kill** (e.g.
      a `sleep 120` escalation) so you can verify the process really is still running after
      "Stopped 1 run" — check via `ps` on the host. **PROOF OWED, expect it to still fail.** — [P0]
- [ ] **Policy editor** (Settings → Policy & Governance → Policy): the relay-only picker (Default
      decision: Deny/Ask/Allow) loads without a stale-SSH error flash (`PolicyEditorView.swift`,
      #144 fix). Confirmed PASS on phone 2026-07-16 — re-confirm holds. — [P1]
- [ ] **Product concern to note, not fix**: there are two overlapping permission controls — the
      global Policy default picker (works) and the per-chat pill (display-only, see §4). Owner
      already flagged wanting the per-chat one to be the real control (WT-A2) — just confirm this
      is still the state, no action needed here. — [P2]
- [ ] **Audit feed** (Settings → Policy & Governance → Audit): opens, loads real entries from
      tonight's activity over the relay (`AuditFeedView.swift`, confirmed PASS on phone
      2026-07-16). Known cosmetic bug (WT-G): feed renders **oldest-first**, so tonight's entries
      require scrolling through days of history instead of newest-first. — [P2]

---

## 6. Siri / App Intents

**Pointer only — do not duplicate here.** Full 5-step voice test ladder (Shortcuts app → read-only
voice → safety-reducing voice → the deep iOS-27 long-running path → ergonomic custom phrases) is
in `docs/test-runs/2026-07-17-siri-test-workflow.md`. Run it as its own pass; it needs your voice
and a physical device, and it's the one Siri surface that's never been proven live. Note:
approve-by-voice is deliberately absent — don't treat that as a bug.

- [ ] Ran the Siri test workflow (yes/no) — if yes, link results here or in that file directly. — [P1]

---

## 7. Settings

(`Packages/LancerKit/Sources/AppFeature/Settings/AppSettingsView.swift` — every row enumerated,
nothing invented)

- [ ] **Connections → Trusted machines** row opens `TrustedMachinesView`
      (`AppSettingsView.swift:71-86`). — [P1]
  - [ ] List shows **Paired** machines and (if any) a **Dead pairings** section with "Clear all
        dead pairings" (`TrustedMachinesView.swift:123-144`). — [P1]
  - [ ] **"Pair a machine"** opens the `RelayPairingSheet`; complete a pairing (or cancel — don't
        burn a slot if you're already at the machine cap) and confirm the sheet dismisses itself
        after a brief "paired" confirmation (`TrustedMachinesView.swift:47-56`). Recent fix
        (`67fb18d9`, per `git log`) specifically targeted pairing-sheet error display and Remove
        reliability — this is freshly-changed code, worth extra attention. — [P0]
  - [ ] **Remove a machine**: tap into a machine row → `MachineDetailView` → "Remove Machine"
        works and doesn't leave a stuck "offline" pairing with no way to remove it (this exact bug
        was fixed 2026-07-17 per the recent commit — confirm it holds; "Remove" and the row's
        `NavigationLink` must not share a hit target per the code comment at
        `TrustedMachinesView.swift:169-172`). — [P1]
  - [ ] **Open Terminal** from `MachineDetailView` — "Opens a daemon-owned shell on this machine
        over the relay (Orca-style). No separate SSH host setup." (`MachineDetailView.swift:34-39`).
        See §9 Terminal for what to check once it's open. — [P0]
- [ ] **Policy & Governance → Policy** and **→ Audit** rows — same as §5 above, listed here for
      completeness of the Settings sweep (`AppSettingsView.swift:88-114`). — [P1]
- [ ] **Send Feedback** row (newest addition, shipped with TestFlight build 2 today) opens
      `FeedbackView`: a segmented **Type** picker (feature/bug/other), a message text editor,
      footer disclosure "Includes app version and device info," and a **Send** button
      (`FeedbackView.swift`). Send a real test message and confirm you get "Thanks — filed as
      #N" (posts to push-backend `/feedback` → GitHub issue) or a clear error if the backend is
      unreachable (`AppSettingsView.swift:116-129`, `FeedbackView.swift:102-122`). Per today's
      changelog, push-backend `/feedback` was live but **503 `feedback_unconfigured`** until the
      owner's GitHub PAT was set — confirm whether that's since been resolved. — [P1]
- [ ] **Emergency Stop** — covered in §5 (this is where it physically lives in the UI,
      `AppSettingsView.swift:131-166`). — [P0]
- [ ] Settings **does not** show a stray "What's new" panel or a tab-bar-era Control/Activity
      section — the current row set is exactly: Connections, Policy & Governance, Send Feedback,
      Emergency Stop. If you see anything else, that's new/undocumented — flag it. — [P2]

---

## 8. Profile

(`Packages/LancerKit/Sources/AppFeature/Profile/ProfileView.swift`)

- [ ] Identity section shows "Lancer" + a real machine-pairing summary text ("Paired with X" /
      "N paired machines" / "No paired machines yet") — never a fake usage/streak stat
      (`ProfileView.swift:114-126`, comment explicitly: "no invented usage/streak"). — [P2]
- [ ] **Connections → Trusted Machines** row (with a live paired-count badge) opens the same
      Trusted Machines sheet as Settings (`ProfileView.swift:128-145`). — [P1]
- [ ] **More → Settings** row pushes `AppSettingsView` onto Profile's own nav stack (not a nested
      sheet) (`ProfileView.swift:152-160`). — [P1]
- [ ] **More → Help** row opens the GitHub issues URL
      (`github.com/RoshanDewmina/conduit/issues`) in Safari (`ProfileView.swift:162-166`). — [P2]
- [ ] Footer shows real "LANCER <version> (<build>)" from the bundle, not a placeholder. — [P2]

---

## 9. Terminal (Orca-style daemon-owned PTY)

- [ ] Open a terminal (from Trusted Machines → machine → Open Terminal, or a thread's ⋯ → open at
      cwd). Confirm a real shell prompt comes up and you can run a command and see live output
      (Orca `terminal-stream-protocol` over relay, `RelayTerminalModel`/`LiveTerminalView`). Prior
      sweep: **PASS** for open + real usage (`LF-final-report.md`). — [P0]
- [ ] Run a full-screen TUI (`vim`, `htop`, `tmux`) if you have one on the host — confirm the
      alt-screen renders via SwiftTerm without corrupting the block view underneath. — [P1]
- [ ] Background the app mid-command, come back — confirm the terminal reconnects rather than
      showing a dead/frozen session. Lifecycle here was noted as only **partial** proof in the
      sweep — treat any hang here as a real finding, not expected. — [P1]
- [ ] Desktop-history / cold-restore of a terminal you didn't start from the phone — noted as
      **unproven** in the sweep (`LF-final-report.md` "desktop-history unproven"). If you have a
      pre-existing tmux/desktop session, check whether opening it from the phone shows its
      existing scrollback or starts blank. **PROOF OWED.** — [P2]

---

## 10. Search

(`Packages/LancerKit/Sources/AppFeature/ThreadList/SearchView.swift`)

- [ ] Open Search (top bar magnifying glass on Workspaces) → type a query that matches a real
      thread title/content → confirm real results, not placeholder rows. — [P1]
- [ ] **Filter chips**: "All" + one chip per repo — tapping a repo chip narrows results to that
      repo's cwd (`SearchView.swift:192-208`). — [P2]
- [ ] Clear search (X button) resets to the unfiltered/empty state
      (`SearchView.swift:184` "Clear search"). — [P2]
- [ ] Empty states are honest: "No threads yet" when you have none vs. "No matching threads" when
      a query has zero hits (`SearchView.swift:95-97`). — [P2]

---

## 11. Thread list (per-repo and All Repos)

- [ ] **Filters** (status/source filter sheets, `ThreadListStatusFilterSheet` /
      `ThreadListSourceFilterSheet`) narrow the list correctly. Prior sweep: **PASS**. — [P2]
- [ ] **Customize** sheet (`ThreadListCustomizeSheet`) lets you change which metadata columns show
      per row. Prior sweep: metadata **PASS**. — [P2]
- [ ] **Repo name vs. cwd correctness**: confirm the displayed repo name is the friendly name you
      gave it, but any command that runs uses the real absolute cwd underneath (prior sweep
      verified this with `sc3-repo` display vs. commit landing in the real absolute path). — [P2]
- [ ] Tapping a thread row opens the live thread at the right point (not always the top — see the
      WT-J scroll bug in §4). — [P1]

---

## 12. Review / diff surfaces

(`Packages/LancerKit/Sources/AppFeature/Review/*` — reached from a turn's diff card / session
diff pill / thread ⋯)

- [ ] **Review sheet**: "Modified" diffs list + "All Files" tree toggle, file list at top with
      +/- summary (`ReviewSheetView.swift`, `ARCHITECTURE.md` §4.6). — [P1]
- [ ] **Per-hunk approve/reject** — partial patch approval, not all-or-nothing
      (`DiffHunkView.swift`, §4.6). — [P1]
- [ ] **File viewer**: tap into a changed file to see full contents, not just the diff hunk
      (`FileViewerView.swift`). Prior sweeps repeatedly found this **BLOCKED** on a pairing-harness
      issue, never live-disproven. **PROOF OWED.** — [P1]
- [ ] **Add line comment**: long-press or tap a diff line → `AddCommentSheet` → attach a comment
      that queues against the review. Also previously **BLOCKED** on the same harness issue.
      **PROOF OWED.** — [P1]
- [ ] **Flight Recorder** (`FlightRecorderView`/`FlightRecorderTimeline`) — a timeline view,
      reachable from the review/diff surface. Also previously **BLOCKED**, never live-proven.
      **PROOF OWED.** — [P2]

---

## 13. Watch app / widgets (if you have an Apple Watch paired)

- [ ] `LancerWatch` companion app launches and shows live `agentActive`/`pendingCount`/uptime via
      `WatchConnector`/`PhoneWatchConnector` (not hardcoded stubs — this was a prior fix). — [P2]
- [ ] **Inbox Count widget** (`InboxCountWidget`, home-screen/lock-screen widget family
      `.accessoryRectangular`) shows a live pending-approval count and has a VoiceOver label. — [P2]

---

## 14. StoreKit / IAP

- [ ] There is **no reachable in-app purchase UI** for `dev.lancer.mobile.pro` as of this tip —
      `PurchaseManager` exists and restores/refreshes entitlement silently on launch
      (`Lancer/LancerApp.swift:79-80`), but no paywall/purchase button was found anywhere in
      `AppFeature` (grepped for "Paywall"/"Unlock Pro"/purchase call sites — none). This is a gap
      between the App Store submission checklist (which describes creating the IAP product) and
      the shipped UI, not something to test interactively. Flag if you find a purchase surface
      that this session missed — otherwise there's nothing to click here. — [P2]

---

## 15. Edge cases / reconnect

- [ ] **Airplane mode mid-turn**: toggle airplane mode on while a turn is running, then off again
      — confirm the relay reconnects and the daemon re-sends any pending approvals rather than
      losing them (this is the exact mechanism the DOGFOOD walk observed working for the
      lock-screen-push fallback: "re-sending 1 pending approval(s) after (re)pair"). — [P1]
- [ ] **Kill and relaunch the app** mid-run — confirm the live thread reattaches to the in-progress
      run on relaunch rather than showing it as dead/errored. — [P1]
- [ ] **Force-quit then approve from a killed-app Live Activity/push** (if push is working per §5)
      — confirm the cold-decision gate hydrates relay creds from Keychain and the decision still
      reaches the daemon. Depends on §5's lock-screen push check passing. — [P0]
- [ ] **Re-pair after a stale/dead pairing**: if a pairing goes dead (host restarted, code
      rotated), confirm the app surfaces a clear re-pair path rather than silently failing —
      recent commits (`67fb18d9`, `285edc33`) targeted exactly this. — [P1]

---

## 16. Teardown

- [ ] If you paired a throwaway/test machine for this walk, remove it from Trusted Machines so
      you don't leave dead slots occupying the fleet cap (max 3 machines).
- [ ] Note anywhere you deviated from "Debug device build" (e.g. had to fall back to the
      TestFlight build for a push test) so the next session knows which binary the results apply to.
- [ ] File any **new** finding (not already listed as a known bug above) as a GitHub issue via
      Send Feedback (§7) or directly, so it doesn't get lost.

---

## Sources read this session

- `docs/test-runs/2026-07-16-untested-feature-sweep/GAP_LIST.md` (full)
- `docs/test-runs/2026-07-16-untested-feature-sweep/DOGFOOD_DEVICE_WALKTHROUGH.md` (full)
- `docs/appstore/SUBMISSION_CHECKLIST.md` (full)
- `docs/test-runs/2026-07-17-siri-test-workflow.md` (full)
- `ARCHITECTURE.md` §0.1 (current-state snapshot) and §4 (UX architecture, §4.1–§4.7)
- `Packages/LancerKit/Sources/AppFeature/Settings/AppSettingsView.swift` (full)
- `Packages/LancerKit/Sources/AppFeature/Settings/TrustedMachinesView.swift`,
  `PolicyEditorView.swift`, `AuditFeedView.swift`, `FeedbackView.swift` (grepped/read)
- `Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift` (read in full)
- `Packages/LancerKit/Sources/AppFeature/Composer/NewChatComposerView.swift`,
  `ComposerDispatchPickerView.swift` (grepped)
- `Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift` (grepped for structure/state)
- `Packages/LancerKit/Sources/AppFeature/Profile/ProfileView.swift` (read in full)
- `Packages/LancerKit/Sources/AppFeature/Terminal/MachineDetailView.swift`,
  `ThreadList/SearchView.swift` (grepped)
- `Packages/LancerKit/Sources/AppFeature/Onboarding/OnboardingGateView.swift` (grepped)
- `Packages/LancerKit/Sources/SettingsFeature/PurchaseManager.swift` + cross-repo grep for
  purchase/paywall UI call sites (none found beyond `LancerApp.swift` restore-on-launch)
- Directory listings of `Review/`, `Terminal/`, `Agents/`, `RepoPicker/`, `FlightRecorder/`,
  `Context/`, `LancerWatch/`, `LancerWatchWidget/`, `Lancer/` (App Intents / Siri files)
- `docs/CHANGELOG.md` head (format + today's entries, for the changelog line added alongside this doc)
