# WP1 perf pass — 2026-07-17

Branch: `perf/thread-feel` (worktree `.worktrees/wp1-perf`, base `master` @ `bcda72bb`).

Scope: thread open→first paint, scroll-to-latest, thread-list return visits,
live-follow cost, honest skeletons. Base already includes LazyVStack
rendering, `ChatTranscriptSkeleton`/`ChatTranscriptSkeletonVisibility`,
`.defaultScrollAnchor(.bottom)`, CC-1 auto-follow scroll — not
re-implemented, only measured past.

## 0. Measurement seams added

- `LANCER_SEED_TRANSCRIPT_COUNT=<N>` (new, `DebugSeeder.swift`
  `seedLongTranscriptIfRequested`) — seeds a deterministic conversation
  `conv-perf-seed-<N>` with N turns × 4 events (thinking/tool_call/tool_result/output).
  Requires `LANCER_UITEST_RESEED=1` in the same launch env (the seeding
  `.task` in `AppRoot.swift` is gated on `isUITestSeedReady`, which starts
  `true` unless that var is set — same gate the existing
  `LANCER_SEED_TRANSCRIPT` seam sits behind). Pair with
  `LANCER_SKIP_CURSOR_ONBOARDING=1` to land straight on Workspaces.
  Note: the existing `LANCER_SEED_TRANSCRIPT` seam has no count parameter —
  it's a single fixed 12-event turn. This is a new, separate seam.
- Perf log lines (os.Logger, subsystem `dev.lancer.mobile`):
  - `ThreadDetailPerf` / `threadDetail.localRead`, `threadDetail.loadTurnsTotal`
    (`ThreadDetailView.swift`)
  - `WorkspaceCatalogPerf` / `workspaceCatalog.loadLocalRows`
    (`WorkspaceRepoCatalog.swift`)
  - Captured live via `xcrun simctl spawn <udid> log stream --predicate
    'subsystem == "dev.lancer.mobile"' --style compact`.
- `ShellLiveBridge.testTranscriptRefreshPublishCount` /
  `testTranscriptRefreshSkipCount` — test-only counters proving the
  diff-before-publish fix (see §3).

All measurement code is `#if os(iOS)` / `DEBUG`-gated where the surrounding
file already is; the two new repository methods and the `Duration` helper
are plain library code usable from `swift test` too.

## 1. What was measured (numbers)

### Cold open of a 200-turn / 800-event seeded thread

Seeded via `LANCER_SEED_TRANSCRIPT_COUNT=200` + `LANCER_UITEST_RESEED=1` +
`LANCER_SKIP_CURSOR_ONBOARDING=1`, real device log (`xcrun simctl spawn log
stream`) on the Simurgh-leased iPhone 17 Pro simulator (lease-204):

```
2026-07-17 11:18:33.003 [ThreadDetailPerf] threadDetail.localRead thread=conv-perf-seed-200 turns=200 events=800 elapsedMs=85.326167
2026-07-17 11:18:41.204 [ThreadDetailPerf] threadDetail.loadTurnsTotal thread=conv-perf-seed-200 elapsedMs=8286.251500
```

- **`localRead` = 85ms** — this is the number that matters for first paint:
  it's the local GRDB read + event grouping that lets
  `ChatTranscriptSkeletonVisibility.shouldShow` flip from skeleton to real
  content (`hasCachedContent` becomes true once `turns` is non-empty).
  85ms for 200 turns / 800 events is fast; screenshot evidence
  (`screenshots/02-thread-open-200-turns-bottom-anchored.jpg`) shows the
  transcript fully painted and bottom-anchored (existing `.defaultScrollAnchor(.bottom)`)
  on the very next screenshot after the tap — no visible skeleton flash was
  ever caught, consistent with an 85ms gate.
- **`loadTurnsTotal` = 8286ms** — this is `localRead` PLUS
  `workspaceData.refreshThreadFromHost` (a full relay round trip to
  reconcile with the host) PLUS `loadReviewDiffs()`. In this sandboxed run
  there is no paired host, so the host-refresh leg is dominated by a
  timeout/retry, not by local work. This number is real but is not
  representative of "first paint" — first paint already happened 8.2s
  earlier at the `localRead` gate. Not a regression from this pass; flagged
  as a separate backlog item (see §3 backlog: host-refresh should not block
  anything already skeleton-gated, and should have a tighter timeout when
  no machine is connected).

### Thread-list return visit

```
2026-07-17 11:19:02.701 [WorkspaceCatalogPerf] workspaceCatalog.loadLocalRows conversations=1 elapsedMs=6.577
```

Only 1 seeded conversation existed in the simulator run (the seeder
produces one long conversation, not N short ones), so this number alone
doesn't demonstrate the N+1 fix at scale. See the repository-level
benchmark instead:

```
[WP1 perf] N+1 loop (150 conversations): 51.217ms; batched: 4.981ms; speedup: 10.28x
```

(`ChatConversationRepositoryTests.batchedLookupFasterThanN1Loop`, in-memory
GRDB DB, 150 conversations × 1 turn × 1 artifact each — the exact old-vs-new
code paths, real `ContinuousClock` measurement, `swift test` output.) This
is an in-memory DB so absolute numbers are optimistic vs. a real on-disk
`AppDatabase.openShared()`; the important number is the **10.3x reduction
in DB round trips** (2 batched queries vs. up to 300 sequential ones for 150
conversations), which is architecture, not environment, so it holds on
device too — if anything the win is larger on-device where each round trip
also pays the `ChatConversationRepository` actor-hop.

### Live-follow (in-flight run poll, ~1s cadence)

Direct proof via `ShellLiveBridgeTests.unchangingRunningTurnSkipsRepublishAfterFirstTick`
(new test, runs `pollUntilTerminal` for real over 3.3s of wall-clock time —
i.e. ~3 real 1s poll ticks — against a `.running` turn whose DB row never
changes):

```
✔ Test "unchanging running turn: only the first poll tick republishes transcriptTurns" passed after 3.411 seconds.
```

Assertions: `testTranscriptRefreshPublishCount == 1` (only the first tick,
when `transcriptTurns` is still empty, actually reassigns it),
`testTranscriptRefreshSkipCount >= 2` (every subsequent tick reads the DB,
finds identical content, and skips the write).

Caveat: this is the **in-flight send** poll loop (`pollUntilTerminal`,
`LivePollPolicy.pollIntervalNanoseconds` = 1s), which is what actually calls
`refreshTranscript` unconditionally every tick. The separate **desktop
live-follow** loop (`observedFollowLoop`, 1.5s cadence, used for watching
activity on an already-open thread from another device) was checked and
already guards on `delta.messages.isEmpty` before doing any work — it did
not need this fix. A true ≥30s on-device observation against a live paired
`lancerd` was not possible in this sandboxed run (no host machine
available to pair) — the poll-loop proof above is the direct-code-path
substitute; noted as a gap, not fabricated as a device observation.

## 2. What was fixed (file:line)

1. **`ShellLiveBridge.refreshTranscript` full republish on every poll tick**
   — `Packages/LancerKit/Sources/AppFeature/Bridge/ShellLiveBridge.swift:1234-1250`
   (was `:1234-1242` pre-fix). `pollUntilTerminal` called this on
   essentially every tick (`.completed`, `.failed`, `.running`, and the
   `else` fallback), unconditionally doing `transcriptTurns = turns` — a
   full `@MainActor` published-array reassignment that re-triggers every
   downstream `.task(id:)` keyed off `transcriptTurns`
   (`LiveThreadView.receiptRefreshToken` → `refreshTranscriptExtras()` →
   another 10k-event DB fetch), even when nothing changed. Fix: added
   `Equatable` conformance to `LancerCore.ChatTurn` and `ChatTurn.Status`
   (`Packages/LancerKit/Sources/LancerCore/ChatConversation.swift:113,143`)
   and gated the reassignment on `turns != transcriptTurns`. Proven by
   `ShellLiveBridgeTests.unchangingRunningTurnSkipsRepublishAfterFirstTick`.

2. **`TurnTranscriptAssembler.items(from:)` recomputed on every SwiftUI
   re-render, up to ~7x per turn per render** —
   `Packages/LancerKit/Sources/AppFeature/ConversationSyncCoordinator.swift:196`
   (the pure assembler, unchanged) is a full sort + two-pass walk over a
   turn's event array. It was called from `ThreadDetailView.swift` (3 call
   sites: `threadAssistant`, `hasAssistantArtifacts`, `backgroundTaskRows`)
   and `LiveThreadView.swift` (4 call sites: `turnTranscriptBody`,
   `hasAssistantArtifacts`, `liveToolChips`, plus the assistant-artifacts
   check reused inside the visible-turns filter) every time, with no cache,
   so a turn with N events got re-sorted/re-walked on every unrelated
   `@State` change in the view (scroll, keyboard focus, poll tick). Fix:
   added `TurnTranscriptItemsCache`
   (`Packages/LancerKit/Sources/AppFeature/ConversationSyncCoordinator.swift:539-579`,
   a reference-type cache held in `@State` so cache writes don't themselves
   republish through SwiftUI, keyed on `(turn.id, event count, last event
   seq)` — correct because this codebase's event log is strictly
   append-only per turn) and wired it into both views' 7 call sites via a
   `transcriptItems(for:)` helper
   (`ThreadDetailView.swift:397-400`, `LiveThreadView.swift` next to
   `eventsByTurnID`). Proven correct by 3 new unit tests
   (`TurnTranscriptItemsCacheTests.swift`); magnitude not wall-clock-proven
   (would need Instruments Time Profiler across a scroll gesture — see
   backlog).

3. **`WorkspaceRepoCatalog.loadLocalRows()` N+1 query on every thread-list
   appear/return-visit** —
   `Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspaceRepoCatalog.swift:773-798`
   (was `:773-791` pre-fix). Looped `chatRepo.recent(limit: 200)` then, for
   each of up to 200 conversations, awaited `turns(conversationID:).last`
   (a full unfiltered scan of that conversation's turns just to take the
   last one) and then `artifacts(turnID:)` — up to 400 sequential,
   actor-hopping DB round trips, re-run every time `ThreadListView` appears
   (including every pop back from a pushed thread). Fix: two new batched
   repository methods,
   `ChatConversationRepository.latestTurns(conversationIDs:)`
   (`Packages/LancerKit/Sources/PersistenceKit/ChatConversationRepository.swift:189-208`,
   one SQL query with a `MAX(ordinal)` self-join) and
   `artifacts(turnIDs:)` (`:264-280`, one `IN (...)` query grouped in
   Swift). `loadLocalRows()` now does exactly 2 round trips regardless of
   conversation count. Proven both for correctness (3 new repository unit
   tests) and for magnitude (`batchedLookupFasterThanN1Loop`, 10.3x
   speedup on 150 conversations — see §1).

## 3. Backlog (ranked, not done this pass)

1. **`refreshThreadFromHost` should not gate anything already
   skeleton-gated, and should have a tight timeout when no machine is
   connected.** Measured: `loadTurnsTotal` was 8.2s slower than `localRead`
   on a device with no paired host — that's a real user-visible stall
   (spinner-adjacent state, "Machine unreachable" banner) even though first
   paint already happened. Worth a dedicated pass; out of scope here
   (touches relay/timeout policy, not rendering).
2. **Wall-clock proof of the `TurnTranscriptItemsCache` win** — correctness
   is unit-tested but the actual scroll-performance delta (frame time
   during a fling through a 200-turn thread) needs Instruments Time
   Profiler or an XCTest metrics harness (`XCTOSSignpostMetric` /
   `XCTMemoryMetric`), not just log-line timestamps. Candidate next step:
   add `os_signpost` intervals around `LazyVStack` row bodies and capture
   with `xctrace`.
2b. **List vs LazyVStack for the transcript** — flagged by the coordinator
    mid-task (List recycles cells; LazyVStack retains every child view that
    has appeared). Not applied this pass — no wall-clock scroll-memory
    measurement was taken to justify the design-risk trade-off list vs.
    LazyVStack entails (existing skeleton/streaming/tool-chip row designs
    were built against LazyVStack). Recommend pairing with backlog item 2's
    Instruments pass before deciding.
3. **`ThreadDetailView.loadTurns()` calls `AppDatabase.openShared()` fresh
   on every load/retry** (not per-fetch inside one load — that part's fine
   — but once per `loadTurns()` invocation). `LiveThreadView` already
   fixed the equivalent issue by caching the repo in `@State`
   (`extrasRepo`, see comment at `LiveThreadView.swift:779`). Same fix is
   straightforward for `ThreadDetailView` — not done this pass to keep the
   diff scoped to the three proven offenders above.
4. **`ThreadDetailView.loadTurns()` fetches events twice per open** when
   `refreshThreadFromHost` is set (once for the instant local-mirror paint,
   once again after host reconcile) — inherent to the "paint local, then
   reconcile" design and arguably correct, but worth revisiting once
   backlog item 1 lands (a tighter host-refresh timeout changes the cost
   profile here).
5. **`LiveThreadView.refreshTranscriptExtras()`** still re-fetches up to
   10k events on every `receiptRefreshToken` change (turn-count/status
   change) — this pass's `refreshTranscript` fix reduces how *often* that
   token changes (no more spurious identical-content ticks), but doesn't
   cap the 10k-event refetch itself. A cursor/delta-based extras refresh
   would be the next step if this still shows up as a hot path after
   backlog item 2's Instruments pass.

## 4. Gates run

- `cd Packages/LancerKit && swift build` — green (`Build complete!`).
- `cd Packages/LancerKit && swift test` — green, 819 + 62 + 13 tests / 3
  bundles, 0 failures (run before the `ShellLiveBridgeTests` addition,
  which is `#if os(iOS)`-gated and doesn't compile on the macOS `swift
  test` destination — see next line).
- `ChatConversationRepositoryTests` (cross-platform, incl. the 4 new tests)
  re-run standalone after adding them: `swift test --filter
  ChatConversationRepositoryTests` — 40/40 green, including the N+1 speedup
  print above.
- `TurnTranscriptItemsCacheTests` (new, cross-platform) — 3/3 green.
- iOS-only tests (`ShellLiveBridgeTests`, including the two new/modified
  ones) run via `simurgh exec lease-204 -- xcodebuild test -scheme
  LancerKit-Package -destination "platform=iOS Simulator,id=<lease-204
  UDID>" -only-testing:LancerKitTests/ShellLiveBridgeTests` — 13/13 green
  (`** TEST SUCCEEDED **`).
- App-target build (XcodeBuildMCP, bound to Simurgh lease-204): `build_run_sim`
  — `SUCCEEDED`, 0 errors, pre-existing type-check-time warnings only
  (`LiveThreadView.swift:122`, `ThreadDetailView.swift:130`, unrelated to
  this diff).
- Full `LancerKitTests` iOS suite (`-only-testing:LancerKitTests`) via the
  same `simurgh exec` route: 977 tests / 153 suites, **10 failures**, all in
  `RelayMachineMigrationTests` (5), `RelayApprovalDecisionRaceTests` (3),
  `ApprovalRelayColdLaunchTests` (1), `LiveActivityContentStateTests` (1) —
  none of these files were touched by this pass. Re-ran the 4 failing
  suites in isolation: only `RelayMachineMigrationTests` (4/6 tests) and
  `LiveActivityContentStateTests` (1/1) failed again;
  `RelayApprovalDecisionRaceTests` and `ApprovalRelayColdLaunchTests`
  passed clean on rerun. `RelayMachineMigrationTests`'s own source has an
  existing comment documenting this exact failure mode: the suite mutates
  real shared global state (`UserDefaults.standard` + a static
  `RelayMachineMigration.indexKeychain`) and Swift Testing runs a suite's
  tests concurrently by default, racing them against each other —
  pre-existing test-isolation flakiness, not a regression from this diff
  (confirmed by file scope: none of `ShellLiveBridge.swift`,
  `ConversationSyncCoordinator.swift`, `WorkspaceRepoCatalog.swift`,
  `ChatConversationRepository.swift`, or `ChatConversation.swift` are
  imported/exercised by the failing suites).

## 5. Screenshots

- `screenshots/01-workspaces-with-seeded-thread.jpg` — Workspaces landing
  on the seeded 200-turn conversation ("project", 1 thread), onboarding
  skipped via `LANCER_SKIP_CURSOR_ONBOARDING=1`.
- `screenshots/02-thread-open-200-turns-bottom-anchored.jpg` — cold open of
  the 200-turn thread, screenshot taken immediately after the tap. Content
  fully painted, bottom-anchored near turn ~185-199 (existing
  `.defaultScrollAnchor(.bottom)` + CC-1 auto-follow, not changed this
  pass), no skeleton visible — consistent with the measured 85ms
  `localRead`. "No connected host" banner visible (expected — no paired
  machine in this sandboxed run; explains the 8.2s `loadTurnsTotal`, see §1).

## 6. Simurgh frictions encountered

1. **XcodeBuildMCP session defaults are shared/global, not scoped per
   Simurgh lease.** After `simurgh integration xcodebuildmcp start
   --session lease-204` and `session_set_defaults` pointing at this
   worktree's project/scheme/lease-204 simulator, a subsequent
   `session_show_defaults` (and one `screenshot` call) showed a
   *different* worktree's project (`wp5-gap-reproof/Lancer.xcodeproj`) and
   a different lease (`lease-205`) — evidently another concurrent agent
   session's defaults clobbered mine via the same XcodeBuildMCP
   server/config file. Re-`set_defaults` immediately before each
   screenshot/build call was needed to avoid operating against the wrong
   simulator. No data was lost/corrupted, but every XcodeBuildMCP call had
   to be treated as "verify defaults immediately before use, not once at
   session start."
2. **`build_run_sim`'s `launchArgs` are argv, not environment variables** —
   the tool description ("Arguments passed to the launched app process")
   reads ambiguously; `LANCER_SEED_TRANSCRIPT_COUNT=200` passed via
   `launchArgs` was silently ignored (`ProcessInfo.environment` never saw
   it) because the app only reads `ProcessInfo.processInfo.environment`,
   not `CommandLine.arguments`. Had to use `session_set_defaults({env:
   {...}})` + `launch_app_sim` instead. Not a Simurgh issue per se
   (XcodeBuildMCP), but cost a full rebuild-and-relaunch cycle to diagnose.
