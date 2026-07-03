# Second opinion needed: cross-device conversation sync architecture for Lancer

> Prepared 2026-07-02 for hand-off to Codex. This is a standalone brief — it doesn't assume you've
> read anything else in this repo's conversation history.

## What Lancer is

Lancer is a mobile control-plane iOS app for AI coding agents (Claude Code, Codex, OpenCode, Kimi)
running on a user's own machine(s) via a resident Go daemon, `lancerd`. The daemon dispatches/
monitors agent runs and talks to the phone through a hosted relay (websocket, end-to-end encrypted)
plus APNs for push. The product's core premise: the phone approves/monitors; the actual coding
work happens on the user's own machine. There's also a native macOS companion, `LancerMac`, but
it's menu-bar management/monitoring only (pairing, pause/stop, diagnostics) — it cannot itself
start or hold an agent conversation.

## The problem

A user starts a chat with a coding agent from their phone. They expect to be able to see and
continue that same conversation from a second device (another phone, or by observing from the
laptop) — "start something, walk away, pick it up anywhere" is the whole pitch. Today this does
not work: conversation history (`ChatConversationRepository`, a GRDB/SQLite table,
`Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift`) lives **only** in the local
on-device database of whichever phone dispatched the chat. There is no server-side or host-side
canonical store of conversation content. The daemon streams live output over the relay during a
run but persists none of it. A separate sync engine (`SyncKit/SyncEngine.swift`) does real
bidirectional CloudKit sync, but only for two unrelated entity types — paired Hosts and command
Snippets — never conversations. The architecture doc explicitly scopes this out today: "Blocks and
scrollback are not synced. They are tied to a workspace, not a user" — and lists cross-device
session sync as a deferred future milestone, not a broken feature.

## What already exists and works, adjacent to this problem: "Observed Sessions"

If a user runs a CLI coding agent directly in a terminal on their laptop (bypassing the phone
entirely), `lancerd` can enumerate that session and let *any* paired phone fetch its live
transcript on demand, because the daemon reads the coding agent vendor's own on-disk session files
directly rather than relying on any phone-local database (`daemon/lancerd/dispatch.go` session
listing/resume RPCs; iOS side in `AppRoot.swift` — `loadObservedSessions`,
`fetchObservedTranscript`, `sendObservedSessionFollowUp`). This means the daemon/host machine is
*already* capable of being an authoritative, live, multi-device-readable source of conversation
truth for one specific case (terminal-originated sessions) — it's just that phone-originated "New
Chat" conversations never get registered into that same discoverable surface.

## Two candidate approaches, need your independent assessment

**Option A — extend Observed Sessions (host-owned history).** Make the daemon register
phone-dispatched runs into the same session-listing/transcript-fetch mechanism it already uses for
terminal-originated sessions. The host machine becomes the source of truth for a conversation's
history for as long as that host is reachable; any paired device (phone or otherwise)
discovers/resumes/fetches through the daemon. The phone's local SQLite DB becomes an offline
cache/mirror, not the source of truth. Reuses existing plumbing (RPCs, transcript-fetch protocol
already built and tested for the terminal case).

Open questions: what happens to a conversation's history if the host is offline/asleep when a
second device wants to view it (cache serves stale-but-available data, vs. genuinely
unavailable)? What happens if the host machine is wiped/replaced — does history move, or is it
tied to that physical host forever? How does this interact with the existing local DB (does it get
demoted to pure cache, or removed entirely)?

**Option B — build real bidirectional CloudKit/relay conversation sync from scratch**, the same
pattern `SyncEngine.swift` already uses for Hosts/Snippets, extended to cover conversations. This
gives genuine offline-first behavior (works even if the originating host is completely
unreachable) with real multi-master conflict resolution, at the cost of being new architecture
with no existing plumbing to build on — a materially larger, riskier build than Option A.

## What we need from you

An independent recommendation, not just a restatement of the tradeoffs. Specifically:

1. Which of these is architecturally sounder for a product whose stated design philosophy is
   "history is tied to a workspace/host, not a user account" — does Option B actually fight that
   philosophy, or is that philosophy itself worth reconsidering given the phone-continuity
   requirement?
2. Is there a third/hybrid approach we're missing — e.g., host is authoritative while reachable,
   phone locally queues/caches conversations it starts and pushes them to the host's
   observed-session store once reconnected, with the local DB purely as a resilience cache rather
   than the source of truth?
3. What failure modes should we be most worried about either way — host asleep when a chat is
   started, two devices both trying to append to the same conversation nearly simultaneously, a
   host being uninstalled/re-paired and orphaning its history?
4. Rough shape of the implementation for whichever you recommend — new RPCs needed, daemon-side
   storage requirements (currently `lancerd` persists nothing durable about conversation content —
   would this need a local DB on the host itself?), and how much of the existing Observed-Sessions
   RPC surface is reusable verbatim vs. needs new shapes.

Please give a recommendation with reasoning, not just a menu of options.
