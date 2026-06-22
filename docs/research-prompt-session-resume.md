# Research prompt: session resume/continue for Lancer dispatch

Paste this to a fresh research agent (no prior context from this conversation needed — it's self-contained).

---

## Context

Lancer is an iOS app that dispatches AI coding agents (`claude`, `codex`, `opencode`, `kimi`) on a
remote/local host, either over SSH (`Packages/LancerKit/Sources/.../FleetStore` → daemon JSON-RPC)
or over a blind E2E-encrypted relay (`E2ERelayBridge.swift` ↔ `daemon/lancerd/e2e_router.go`). The
daemon is a Go binary (`daemon/lancerd/`) that, on dispatch, builds an explicit argv per vendor
(`agentArgv()` in `daemon/lancerd/dispatch.go`) and launches it as a one-shot subprocess via
`exec.Command` (`realLauncher` in the same file). Each dispatch gets a fresh `runID`; output streams
back to the phone over `agent.run.output` notifications (SSH) or `agentRunOutput` relay messages.

Two related gaps, currently both unimplemented:

1. **Resuming a session the user started themselves**, e.g. in Terminal/iTerm on the host, completely
   outside Lancer — and continuing that exact conversation from the phone.
2. **Following up on a run Lancer itself dispatched.** The phone UI already has a follow-up input bar
   (`RunDetailView` → `E2ERelayBridge.sendRunContinue(runId:prompt:)` → sends an `agentRunContinue`
   relay message). But the daemon never implements it: `e2e_router.go`'s `handleMessage` switch has no
   `agentRunContinue` case (falls through to the unhandled-type log line and is silently dropped), and
   the SSH-side `server.go` has no `agent.run.continue` RPC method either — only
   `agent.dispatch`/`agent.cancel`/`agent.pause`/`agent.resume`(from a paused process)/`agent.budget.set`
   exist. Today, every dispatch is a disconnected one-shot; nothing carries forward.

`dispatch.go`'s `dispatchRun` struct even has a vestigial field: `SessionID string // reserved for
future session-resume support` — never populated, never read.

## Key finding already verified (don't re-derive — confirm and build on it)

All four supported CLIs have **native, vendor-provided session continue/resume support**, and all four
persist sessions to disk independently of any wrapping process — meaning a session survives after the
original process exits, and can be resumed by ANYONE (a fresh Lancer dispatch included), regardless of
who/what started it:

| Vendor | Continue-most-recent | Resume-by-id | On-disk session storage (host-side, confirmed to exist) |
|---|---|---|---|
| `claude` | `-c, --continue` | `-r, --resume <session-id>` (also `--session-id <uuid>` to pin one at start, `--fork-session`) | `~/.claude/projects/<cwd-hash>/<session-id>.jsonl` |
| `codex` | `codex resume --last` | `codex resume <session-id>` (picker by default) | `~/.codex/sessions/`, `~/.codex/session_index.jsonl`, `~/.codex/archived_sessions` |
| `opencode` | `-c, --continue` | `-s, --session <id>` (`--fork` to branch instead of continuing) | `~/.local/share/opencode/opencode.db` (sqlite) + `~/.local/share/opencode/storage/` |
| `kimi` | `-C, --continue` | `-S, --session <id>` | `~/.kimi-code/sessions/wd_<project>_<hash>/session_<id>/`, `~/.kimi-code/session_index.jsonl` |

This means **items 1 and 2 above are the same underlying capability** — "continue/resume a vendor
session in a given cwd" — not two separate features. A dispatch that passes `--continue` (or
`--resume <id>`) instead of starting fresh will pick up ANY existing session for that cwd, whether it
was started by Lancer, by the user in Terminal, or by anything else.

## What to research and design (don't just confirm the table above — go deeper)

1. **Per-vendor flag/streaming compatibility.** Confirm whether `--continue`/`--resume` combine cleanly
   with the same streaming flags `agentArgv()` already uses (e.g. claude's
   `--output-format stream-json --verbose --include-partial-messages`). Does resuming still emit a
   session-init event the daemon can capture? (`dispatch.go`'s `streamJSONOutput` already receives and
   discards a claude `"system"` event — check if that's the session-init event carrying the session id,
   and whether it's needed to populate the stub `SessionID` field for round 2+ of a continued run.)

2. **TTY/headless constraints.** `agentArgv()` has a documented landmine: `codex exec` hangs without a
   TTY unless `--dangerously-bypass-approvals-and-sandbox` is passed (gated behind
   `LANCER_CODEX_UNSAFE=1`, see `docs/audit/CODEX_GATING.md` — the bypass disables codex's own sandbox,
   so Lancer's policy gate must cover it). Check whether `codex resume` has the same headless-hang
   problem and the same bypass requirement, or whether resume behaves differently from `exec`.

3. **Session discovery/listing, not just "most recent."** `--continue` always grabs the single latest
   session for the cwd. For a real "pick which session to resume" UX (especially useful for item 1 —
   resuming a SPECIFIC terminal session, not necessarily the newest), investigate parsing each vendor's
   on-disk index (`~/.codex/session_index.jsonl`, `~/.kimi-code/session_index.jsonl`, the claude
   `.jsonl` directory per project hash, opencode's sqlite db) to list sessions with cwd + last-active
   timestamp + maybe a title/summary, so the daemon can expose `agent.session.list` (cwd, vendor) →
   `[{id, lastActive, title?}]` for the phone to render a picker. Figure out the least-fragile way to
   read each format (avoid depending on internal schema that vendors could change — prefer documented
   CLI subcommands like `codex resume` picker's underlying data source, `opencode session` subcommand,
   `kimi export`, if they expose listing in a stable JSON form, over hand-parsing internal db/log files).

4. **Architecture for wiring it in**, concretely:
   - `dispatch.go`: extend `dispatchRun` to actually use `SessionID`, plus remember `Agent`+`CWD` (already
     present) so a continue request can rebuild the right resume argv.
   - A new `continueArgv(agent, cwd, sessionID, prompt)` (or extend `agentArgv` with a resume mode) per
     vendor, keeping the existing "explicit argv, never shell-interpolated" security property.
   - A new `dispatcher.continueRun(runID, prompt) dispatchResult`-style method that re-launches with the
     resume argv, reusing the **same runID** so existing output-streaming UI just keeps appending.
   - New RPC surface: `agent.run.continue` in `server.go` (SSH path) and an `agentRunContinue` case in
     `e2e_router.go`'s `handleMessage` switch (relay path) — both should funnel into the same
     dispatcher method.
   - Whether a continued run needs to re-run the policy/budget gate (`dispatch()`'s `evalFn`/budget
     check) — almost certainly yes, since a follow-up prompt is new attacker-influenceable input,
     same as the original dispatch.
   - For item 1 specifically (resuming a session never dispatched by Lancer, so no existing `runID`):
     whether `agent.dispatch` should grow an optional `sessionID`/`resume: true` param so the FIRST
     phone-side message about a pre-existing terminal session is itself a "resume" dispatch that
     allocates a fresh `runID` bound to that pre-existing vendor session.

5. **Phone-side UX**, lighter-weight, after the daemon design is solid: how `RunDetailView`'s existing
   follow-up bar should behave once `agent.run.continue` exists (today it calls
   `sendRunContinue` which is fire-and-forget into the void), and whether `NewChatTabView` (the agent
   picker described in `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`) needs a "browse
   existing sessions on this host" entry point for item 1, vs. just defaulting new dispatches to
   "continue most recent in this cwd" as a low-effort MVP toggle.

## Constraints to respect

- No shell interpolation — argv must stay explicit (see the comment at the top of `agentArgv()` in
  `dispatch.go`).
- Every code path that can launch a process — including resumed/continued ones — must still pass
  through the policy gate and budget gate; don't special-case continues to skip them.
- Codex's sandbox-bypass flag is a known security tradeoff already flagged in
  `docs/audit/CODEX_GATING.md` — don't silently extend its blast radius via the resume path without
  flagging it the same way.
- This must work over BOTH transports (SSH fleet channel and the E2E blind relay) — design the daemon
  internals vendor/transport-agnostic, with thin RPC/relay-message shims on top, same pattern as
  existing dispatch/cancel/pause/resume.

## Deliverable

A concrete implementation plan (file-by-file, function-by-function — not yet code) for:
(a) an MVP that makes today's existing follow-up UI actually work by continuing the most recent session
in the run's cwd, and
(b) a stretch design for listing/picking a specific pre-existing session (covering the "I started this
in Terminal" case) — with a recommendation on whether to build the stretch now or ship the MVP first and
gather real usage before investing in a session browser UI.
