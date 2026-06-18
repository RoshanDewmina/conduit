# Research prompt: in-place chat thread + host-backed conversation history

Paste this to a fresh research agent (no prior context from this conversation needed — it's
self-contained). Related/overlapping prompt already written: `docs/research-prompt-session-resume.md`
— read that one too, since Phase 2 here reuses the `agent.session.list` capability it scopes, and the
follow-up bar in Phase 1 is the exact UI surface the `agentRunContinue` daemon handler from that prompt
needs to drive.

## Context

Conduit is an iOS app that dispatches AI coding agents (`claude`, `codex`, `opencode`, `kimi`) on a
remote/local host over SSH or an E2E-encrypted blind relay. Today's flow for a phone-initiated dispatch:

1. `Packages/ConduitKit/Sources/AppFeature/NewChatTabView.swift` — a compose screen: text editor +
   bottom toolbar (agent picker, machine·cwd picker, model/budget options, send).
2. On send, `AppRoot.performDispatch()` (in `AppRoot.swift`) calls either
   `E2ERelayBridge.sendDispatch` (relay) or `slot.channel.dispatchAgent` (SSH).
3. On a `started` result, `AppRoot` sets `activeRelayRun = ActiveRelayRun(runId:, title:, subtitle:)`
   (`AppRoot.swift` ~line 780), which triggers `.sheet(item: $activeRelayRun) { … RunDetailView(...) }`
   (`AppRoot.swift` ~line 372) — a **separate full-screen sheet** titled "run" that shows live streaming
   output, a HUD strip (`PixelBox` + elapsed timer), a `SpectrumBar`, Stop/Pause/Budget controls, and a
   follow-up text bar (`RunDetailView.swift`).
4. Output is in `RunOutputStore` (a run's accumulated text/chunks), independent of any UI presentation.

**The user's ask:** the "run" sheet should not be a separate page at all. Sending a message in New Chat
should show the agent's streaming response **inline, in the same screen**, below the input — a real chat
thread, not "compose → navigate away to a Run page." After the first message, the New Chat screen's
title should auto-rename to reflect what the conversation is about (instead of staying "new chat"), and
that named conversation should become discoverable later from the Fleet tab.

## What's already in place and worth reusing (don't rebuild from scratch)

- `RunDetailView.swift` already renders exactly the content this needs: a HUD strip, `SpectrumBar`,
  flowing streamed output (`StreamingOutputText` — one concatenated `Text`, not bubble-per-chunk, so
  sub-line token deltas render inline like a terminal), a `controlBar` (Stop / Pause-Resume / Budget,
  collapsing to a calm "Run complete/failed" line once terminal — see `runIsTerminal`/`finishedBar`),
  and a `followUpBar` that calls `onSendFollowUp`. **This is the right visual language already** — the
  work is likely "embed this below the compose input instead of sheet-presenting it," not "design chat
  bubbles from scratch."
- `FleetView.swift`'s body already has an established list pattern to extend: `DSListSectionHead(title,
  count:)` headers + `ForEach` rows + `NavigationLink`, used today for "Active Loops" and per-host agent
  sections (`FleetView.swift` ~line 119-150). It also already has a `+` button in its header that calls
  `onNewTask()` to launch New Chat (~line 100-105) — so Fleet and New Chat are already linked entry
  points; a "Conversations" section would slot into this same list using the same primitives.
- The companion research prompt (`docs/research-prompt-session-resume.md`) already establishes: all 4
  vendor CLIs persist sessions to disk independent of the dispatching process, and proposes a daemon-side
  `agent.session.list` RPC + an `agentRunContinue`/`agent.run.continue` handler. Treat that as the backend
  this feature's "Conversations" list and follow-up bar should be powered by — **don't invent a second,
  parallel persistence mechanism.**

## What to research and design

### Phase 1 — collapse the separate Run page into an inline thread

1. Whether to literally embed `RunDetailView` (or its constituent pieces — HUD strip, output renderer,
   control bar, follow-up bar) inside `NewChatTabView`'s body below the compose input, vs. extracting a
   shared "RunThreadView" component used by both. Consider: `NewChatTabView` currently owns its own
   `bottomToolbar` (agent/machine/options/send) — once a run is active, does that toolbar disappear in
   favor of `RunDetailView`'s `followUpBar`+`controlBar`, or do both need to coexist (e.g. still need to
   switch agent/model for a NEXT separate conversation while one is active)?
2. Multi-turn rendering once `agentRunContinue` actually works (per the companion prompt): should each
   user message + agent response render as a distinct turn (timestamped, scrollable history of turns),
   or does the existing single-flowing-text-block model (`StreamingOutputText`) extend naturally to
   multiple turns by just appending separators? Look at how `ChatTranscriptView.swift` and `ToolCardView`
   (`Packages/ConduitKit/Sources/SessionFeature/Chat/`) — used for the SSH block-terminal pipeline
   elsewhere in the app — solve this exact "multi-turn agent conversation in one scrolling view" problem,
   since reusing that pattern would keep New Chat visually consistent with the rest of the app rather
   than introducing a third chat-rendering approach.
3. What changes in `AppRoot.swift`: removing the `.sheet(item: $activeRelayRun)` presentation (~line
   372-388) in favor of just setting state NewChatTabView reads directly, and whether `ActiveRelayRun`
   (the `Identifiable` struct at ~line 1609) still makes sense as a model or should become per-thread
   state owned by NewChatTabView itself.

### Phase 2 — auto-naming + host-backed Conversations list in Fleet

4. **Auto-naming**: recommend an approach and justify it against the alternatives — (a) cheap heuristic
   (truncate/clean the first user message, e.g. first ~6 words), (b) a short separate LLM call to
   summarize into a title (better quality, costs latency + a token spend per conversation — is that
   worth it given dispatches already go through a budget gate?), (c) precedent from how ChatGPT/Claude.ai
   web/mobile auto-title conversations today (what heuristic do they actually use, and does it run
   client-side or server-side?). Recommend one for v1, with the others as later upgrades if relevant.
5. **Source of truth**: per the companion prompt's `agent.session.list` design, the daemon (not the
   phone) should be authoritative for "what conversations exist." Work out: what fields that RPC needs
   to return for THIS feature specifically (title, vendor, cwd, host, last-active timestamp, terminal
   status) vs. what it needs for the session-resume picker (which may want different/fewer fields) —
   ideally one shared shape serves both call sites. Where does the auto-generated TITLE actually get
   stored — phone-side cache only (simplest, but lost if you reinstall/use a second phone) or persisted
   by the daemon alongside the session id (more durable, consistent with "host is source of truth," but
   requires the daemon to track titles it didn't generate for externally/Terminal-started sessions —
   does it just label those "Untitled session — started outside Conduit" instead?).
6. **Phone-side caching strategy**: which conversations does the phone cache a rendered transcript for
   (only ones it has actually dispatched/streamed itself, presumably, not ones discovered via the host's
   index but never opened) — and what should the Fleet "Conversations" row show before the phone has any
   cached transcript for a host-discovered session (e.g. "tap to load" vs. eagerly fetching a preview).
7. **Multi-host reconciliation**: Fleet can have multiple connected hosts/slots (`FleetStore.slots`) plus
   the relay-paired "virtual" host (`dispatchAgents()`'s `"relay|opencode"` entry in `AppRoot.swift`).
   Does the Conversations list interleave sessions from all hosts/transports into one chronological list,
   or group by host like the rest of FleetView already does (per-host `DSListSectionHead` sections)?
8. **Offline behavior**: when a host/daemon is unreachable, can the user still see (read-only) the
   conversations they've previously cached, with a "host offline" affordance, consistent with how
   `FleetView` already shows offline/reconnectable hosts (`reconnectableHosts`, `slotTone`)?

## Constraints to respect

- Don't duplicate the persistence work already scoped in `docs/research-prompt-session-resume.md` — this
  feature should consume that RPC, not invent its own daemon-side session tracking.
- Stay consistent with the existing component library (`DesignSystem/Components/`) and the "clean Inbox
  look" the user has asked for app-wide elsewhere in this project (no extra colored bars/accents beyond
  what's already established) — check recent UI-consistency decisions before introducing new visual
  patterns for the Conversations list rows.
- `RunDetailView`'s existing terminal-state collapse behavior (`runIsTerminal` → calm `finishedBar`
  instead of dead controls) is a deliberate, already-shipped UX decision — preserve that behavior in
  whatever inline-thread design replaces the sheet presentation.

## Deliverable

A concrete implementation plan, file-by-file:
(a) **Phase 1** (no daemon changes needed): how `NewChatTabView` + `AppRoot.swift` change to render the
run inline instead of sheet-presenting `RunDetailView`, and what (if anything) gets extracted into a
shared component with `ChatTranscriptView`/`ToolCardView`.
(b) **Phase 2** (depends on the companion prompt's `agent.session.list`): the exact RPC/relay message
shape, the auto-naming approach recommendation, and the `FleetView.swift` section design for surfacing
Conversations — plus a recommendation on whether Phase 2 should ship as one unit or be split further
(e.g. "auto-naming + local-only history list" before "full host-backed cross-device history").
