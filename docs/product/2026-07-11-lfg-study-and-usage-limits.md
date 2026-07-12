# lfg (BennyKok/lfg) study — borrowables + usage-limits implementation sketch

Source: `research-repos/lfg` (gitignored, shallow clone, NOT committed). Clone SHA at
review time: `8c4d179` (v0.1.20, 2026-07-11).

## License verdict

**MIT** (`LICENSE`, Copyright 2026 Benny Kok). Fully portable — patterns AND verbatim
code/logic may be ported with an attribution comment (`// ported from BennyKok/lfg,
src/usage.ts, MIT`). No copyleft concerns.

## What it is

A Bun/TypeScript server (`src/commands/serve.ts`) + React PWA (`web/`) that runs Claude
Code, Codex, OpenCode, Grok, Cursor CLI, and Hermes inside long-lived `tmux` sessions on
a Linux/macOS box, streams transcripts to a web UI, and lets you answer prompts or steer
work from phone/laptop. Same category as Lancer (mobile/web mission-control for coding
agents) but web-PWA instead of native iOS, and single-host instead of daemon+relay+push.

## Feature inventory (top borrowables, file:line evidence)

1. **Cross-provider usage/rate-limit page** — `src/usage.ts` (full file), wired at
   `src/commands/serve.ts:3005` (`/api/usage`) and `:3012` (`/api/claude/usage`,
   60s-cached). Live Claude 5-hr + 7-day %, Codex rate-limit windows read from session
   JSONL, OpenCode Go spend-cap estimate. **This is the single most relevant find for the
   owner's ask** — see sketch below.
2. **Activity-ring usage indicator in the composer** — `web/src/App.tsx:4782-4930`
   (`UsageRings`, `UsageRingsButton`). Apple-Watch-style concentric rings, one per limit
   window, in a popover from the chat composer — always-visible, not buried in Settings.
3. **Cross-session "Ask" inbox** — `web/src/components/ask-center.tsx:1-60`+. Polls
   `/api/ask`, single unified queue of pending human-input questions across *all*
   sessions/agents (not per-thread), with a nav-badge, floating card, and full-page
   surfaces. Lancer's approval UX is per-session; a cross-session inbox is a real
   daily-driver gap when running >1 agent concurrently.
4. **Screenshot annotator feeding into chat** — `web/src/components/ImageAnnotator.tsx`
   (pen/rect/circle/arrow/text tools on a captured image before it's attached to a
   message). Useful for "point at this UI bug" turns.
5. **Markdown-defined scheduled "auto agents"** with pluggable collectors —
   `src/agents/collectors/{git,git-fresh,github,openrouter,openrouter-drift,repo-files,
   security}.ts`, `src/agents/runner.ts`. Cron-able agents that gather repo/git/GitHub/
   model-pricing/security context and produce reports — closer to a "nightly digest" than
   anything Lancer has.
5b. **Setup-check / CLI-install UX** — Settings → "Coding agents" checks whether each CLI
   is installed + signed in and can run the installer, mirrors Lancer's
   drift-detector idea but scoped to first-run onboarding rather than post-hoc drift.
6. **Web Push via PWA service worker** — `web/src/lib/push.ts`, `web/src/main.tsx:54-122`,
   toggle at `web/src/App.tsx:13411`. Confirms the same "notify when agent needs you"
   requirement Lancer solves natively via APNs — no new pattern, but validates the UX
   expectation (push toggle in header, not buried).
7. **No bug-report/feedback flow.** `feedback` in this codebase means dismissing Claude
   Code's own CLI upsell overlay (`src/tmux.ts:968`, `feedbackPromptOpen`) — lfg has
   **no user-facing "report a bug" feature**. Not a borrowable; note the gap doesn't need
   filling from here.

## Port to Lancer table

| Feature | Their approach | Our approach | Effort |
|---|---|---|---|
| Plan-limit view (Claude/Codex/Cursor) | `src/usage.ts`: read local OAuth token → hit Anthropic's live usage endpoint; read newest Codex session JSONL for `rate_limits`; no live source for Cursor/OpenCode, static/estimated notes | `lancerd` collector reads the same local credential files + JSONL on the **agent's host** (already has filesystem access there), exposes over existing daemon RPC; iOS renders | **M** — collector is ~150 LOC port of `usage.ts` logic into Go; iOS view is new but small |
| Activity-ring usage indicator | SVG concentric rings, provider-colored, popover breakdown | SwiftUI `Canvas`/`Shape` rings in composer toolbar or a Settings→Usage screen | **S** once data is wired |
| Cross-session Ask/approval inbox | Single poll loop, badge, floating card, full page (`ask-center.tsx`) | Lancer already has per-session approvals; add a top-level "Inbox" aggregating open approvals across all active sessions/hosts | **M** — mostly UI aggregation over existing approval RPC, no new protocol |
| Screenshot annotator → chat attach | Canvas-based draw tool, attaches to next message | SwiftUI `PencilKit`/Canvas markup on a captured screenshot before sending as agent context | **S-M** — PencilKit is a well-trodden iOS API |
| Scheduled "auto agents" w/ collectors | Cron + markdown prompt + pluggable Go/TS collectors, headless run | Out of scope for V1 daily-driver; note for post-launch backlog | **L** (own feature, not urgent) |
| Web Push toggle placement | Header-level, always visible, one tap | Confirms Lancer's existing native push design is directionally right | **—** (no action) |

## Usage-limits implementation sketch (daemon collector → wire → iOS)

**Feasibility: high for Claude, medium for Codex, low/none for Cursor.**

- **Claude Code**: `~/.claude/.credentials.json` → `claudeAiOauth.accessToken` → `GET
  https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and
  header `anthropic-beta: oauth-2025-04-20`. Returns `five_hour.utilization` (0-100) +
  `resets_at`, and `seven_day.utilization` + `resets_at`. This is the **same endpoint
  Claude Code's own `/status` UI uses** — undocumented but stable, live, and exact (not
  an estimate). Direct 1:1 port of `src/usage.ts:64-97`.
- **Codex**: no public usage API. The CLI itself persists the server's `rate_limits`
  block (primary=5h-ish window, secondary=weekly) into the newest `*.jsonl` under
  `~/.codex/sessions/**`; walk for mtime-newest file, scan from the tail for a line
  containing `"rate_limits"`, deep-search the parsed JSON for `primary`/`secondary`
  windows (`used_percent`, `window_minutes`, `resets_at` in epoch seconds). Plan name
  comes from decoding the JWT in `~/.codex/auth.json` (`tokens.id_token`, claim
  `https://api.openai.com/auth.chatgpt_plan_type`). Direct port of `usage.ts:128-210`.
- **Cursor**: **no local or client-usable API found** — confirmed by both lfg (ships no
  Cursor usage window, unlike Claude/Codex) and independent web research. Cursor's usage
  dashboard is account/web-console only; the documented Cursor APIs are Basic-Auth
  team-admin endpoints for org billing, not a per-device/per-CLI live quota read
  reachable from a local credential file. Bottom line: **skip Cursor for V1** of this
  feature; revisit if Cursor ships a local session file with quota data (it doesn't as
  of 2026-07, per lfg's own `staticProvider` fallback pattern and current Cursor docs).
- **lancerd side**: add a `daemon/lancerd` collector package (mirrors `usage.ts`) with
  `GetUsage(agentKind) ProviderUsage` per adapter; cache 60s in-process like lfg does
  (`src/usage.ts:345-361`) to avoid hammering Anthropic on every phone poll. Expose via
  a new RPC (`agent.usage.get`) alongside the existing `agent.*` dispatch surface in
  `dispatch.go`; this reads local host files only — no new secrets/scopes needed beyond
  what the daemon already has filesystem access to for the CLI it's driving.
- **iOS side**: a `UsageWindow`/`ProviderUsage` Codable mirroring the Go struct; a
  Settings→"Plan limits" screen (or composer-adjacent indicator per the ring pattern)
  showing per-agent 5-hr/weekly % with reset countdown; degrade gracefully (note text)
  when a provider isn't signed in or has no data yet — exactly lfg's `available:
  false` + `note` pattern.
- **Risk**: the Anthropic OAuth usage endpoint is undocumented/unofficial (not in public
  API docs) — treat as best-effort, fail soft, and don't block any core loop on it.
