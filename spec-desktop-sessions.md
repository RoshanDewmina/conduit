# Spec — merge real desktop Claude Code sessions into "All Repos" list (risk: ui)

Work in the main checkout /Users/roshansilva/Documents/command-center (current working tree —
DO NOT create a worktree, DO NOT commit, I am reviewing/redeploying directly). Owner ask
(2026-07-15, verbatim): the "All Repos" thread list only shows phone-dispatched conversations;
there are 20+ real Claude Code CLI sessions on disk for this repo that never show up. Scope: v1
is claudeCode only (other providers/vendors are explicit future work, not in scope now — the
underlying model already carries a `provider` field so this doesn't block adding others later).

## What already exists (do not rebuild these)

- Daemon RPC `agent.sessions.list` (daemon/lancerd/server.go:864) → `buildSessionIndex` reads
  `~/.claude/projects/**` and returns Claude Code sessions with id/cwd/title/lastActivity/etc.
- Swift model `ObservedSession` (Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift:396) —
  `sessionId, provider, title, cwd, state, source, lastActivity: Date, messageCount`.
- Bridge call `machine.bridge.relayListSessions()` returning `[ObservedSession]` — see the exact
  usage pattern in Packages/LancerKit/Sources/AppFeature/Agents/RunningAgentsSection.swift:184-188
  (`async let sessionsTask = machine.bridge.relayListSessions()`).
- The resume/continue mechanism: `ShellLiveBridge.armObservedContinue(vendor:sessionId:cwd:)`
  followed by presenting `LiveThreadIdentifier(prompt: "", cwd:)` — see
  Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift around its
  `RunningAgentsSection { session, prompt in ... }` closure (search for `armObservedContinue` and
  `onContinueInLancer`) for the exact working call shape. Reuse this verbatim — do not invent a
  new resume path.

## What to build

File: Packages/LancerKit/Sources/AppFeature/ThreadList/ThreadListView.swift

1. Add `@Environment(RelayFleetStore.self) private var relayFleetStore` and
   `@Environment(ShellLiveBridge.self) private var bridge` (check if not already present).
2. Add `@State private var observedSessions: [ObservedSession] = []`.
3. On appear / alongside whatever loads `threads` today, fetch:
   ```swift
   if let machine = relayFleetStore.firstConnectedMachine {
       let sessions = (try? await machine.bridge.relayListSessions()) ?? []
       observedSessions = sessions.filter { $0.provider == "claudeCode" }
   }
   ```
   Wire this into a `.task` (fire on load; a simple one-shot fetch is fine for v1, no need to
   match the 5s poll cadence RunningAgentsSection uses — but re-fetch on pull-to-refresh if this
   view already has one, check first).
4. Introduce a small unified row enum so the existing `ThreadListItem`-only list can render both
   kinds without corrupting the ledger model:
   ```swift
   enum ThreadListRowKind: Identifiable {
       case ledger(ThreadListItem)
       case desktopSession(ObservedSession)
       var id: String {
           switch self {
           case .ledger(let t): return t.id
           case .desktopSession(let s): return s.id
           }
       }
       var sortDate: Date {
           switch self {
           case .ledger(let t): return t.lastActivityAt
           case .desktopSession(let s): return s.lastActivity
           }
       }
   }
   ```
5. Replace the `groups`/`ForEach(groups)` construction so it merges `threads.map(.ledger)` +
   `observedSessions.map(.desktopSession)`, sorted by `sortDate` descending, THEN grouped by
   recency the same way `WorkspaceRepoCatalog.groupByRecency` already buckets ledger threads —
   either extend that function to accept `[ThreadListRowKind]` (preferred, keeps one grouping
   implementation) or write an equivalent tiny grouping directly in this view if extending it is
   awkward. Your call — whichever is less invasive to the existing (working) ledger-only path.
6. Render each row kind differently in the `ForEach`:
   - `.ledger(thread)`: EXACTLY the existing `NavigationLink { ThreadDetailView(thread: thread) } label: { ThreadListRow(...) }` — unchanged.
   - `.desktopSession(session)`: a `Button` (not NavigationLink — this doesn't push to
     ThreadDetailView, it arms an observed continue and presents `activeLiveThread` exactly like
     the Agents-tab tap flow) whose action does:
     ```swift
     bridge.armObservedContinue(vendor: session.provider, sessionId: session.sessionId, cwd: session.cwd)
     activeLiveThread = LiveThreadIdentifier(prompt: "", cwd: session.cwd)
     ```
     (confirm this exact call shape against the working WorkspacesView reference above before
     using it — match it exactly, don't guess the argument order/labels)
     Label: reuse `ThreadListRow`'s visual style as closely as possible (same padding/typography)
     but make it visibly distinct — owner asked for "an icon or badge": add a small
     `Image(systemName: "desktopcomputer")` + a tiny capsule badge reading "Desktop" (secondary
     color, small font, matching this session's `ChatPendingApprovalCard` badge style —
     `Packages/LancerKit/Sources/AppFeature/Chat/ChatThreadChrome.swift`'s `riskLabel` — same
     small-capsule-pill pattern, different label) next to the title. Show `session.title`,
     relative `session.lastActivity`, and `session.cwd`'s display name (there's likely a
     `WorkspaceRepoCatalog.displayName(forCwd:)` helper already used elsewhere — reuse it, don't
     reimplement).
7. `activeLiveThread` binding: this view likely already has `.liveThreadPresentation($activeLiveThread)`
   wired (check — WorkspacesView/ThreadListView both use this pattern per tonight's earlier work).
   If `ThreadListView` doesn't have it yet, add it (same modifier used elsewhere:
   `.liveThreadPresentation($activeLiveThread)`).

## Constraints

- Do NOT touch daemon/, dispatch.go, or any Go file — this RPC already exists and returns
  everything needed.
- Do NOT change `ThreadListItem`, `WorkspaceDataStore`, or the ledger-only data path — the merge
  happens ONLY in the view layer via the new `ThreadListRowKind` enum.
- Do NOT build a "resume other providers" path — filter to `provider == "claudeCode"` explicitly,
  leave a one-line comment noting other providers are future work (the model already supports it).
- Empty-state: if `observedSessions` is empty (RPC failed, no machine connected, etc.), the
  existing ledger-only behavior must be completely unaffected — this is additive only.

## Acceptance (run yourself)

- `cd Packages/LancerKit && swift build` — must be clean.
- App-target build via XcodeBuildMCP (`mcp__XcodeBuildMCP__build_sim`, call
  `session_show_defaults` first) — must SUCCEED. Plain `swift build` skips `#if os(iOS)` code,
  so this is the real gate.
- Do NOT run the full `swift test` suite (I may be using it concurrently). A focused
  `swift build` + the app-target sim build are sufficient for this UI-only change.
- Do not commit. Leave the working tree as-is when done; I will review the diff myself.

Before reporting progress, audit each claim against a tool result from this session. Only report
work you can point to evidence for; if the build fails, say so with the real output. Paste real
command output, never paraphrase it.

Final message: exact diff summary (files + line counts), the resume-call shape you actually used
(confirm it matches the WorkspacesView reference), real build output for both gates, and anything
you had to guess or decide that deserves a second look.
