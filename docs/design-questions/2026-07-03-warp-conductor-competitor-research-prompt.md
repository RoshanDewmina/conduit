# Research prompt: Warp, Conductor, and competitor mobile apps — features Lancer could borrow

> Prepared 2026-07-03 as a standalone handoff — self-contained, no prior conversation needed.
> Hand this whole file to a research agent (Codex, another Claude session, etc.).

## What Lancer is

Lancer is an iOS/iPadOS "mission control" app for steering AI coding agents — Claude Code, Codex,
OpenCode, and Kimi — that run as real CLI processes on a developer's own machine or server. It is
explicitly **not** a phone IDE and **not** a cloud execution environment: the phone pairs to a
resident background daemon (`lancerd`, written in Go) running on the user's own Mac/Linux box via
an end-to-end-encrypted relay, and that daemon is what actually launches/monitors/gates the coding
agent's CLI process. The phone dispatches tasks, watches streamed output, approves or denies
risky/gated actions (file writes, shell commands, etc.), and reviews history — all without the
phone ever holding the plaintext session (the relay only forwards ciphertext it cannot read).

**Three architectural layers:**
1. **iOS/iPadOS app** (SwiftUI) — the mission-control UI.
2. **`lancerd`** (Go, resident daemon on the user's own machine) — policy engine, hash-chained
   audit log, dispatch/argv construction per vendor CLI, fleet-drift detection, survives SSH drops.
3. **Hosted control plane** (`push-backend`, Go on Cloud Run) — the E2E-encrypted blind relay,
   APNs push delivery, billing/quotas, device pairing. A separate, currently-deferred "hosted-cloud
   execution" path (`agent-runner`) also exists in the codebase but is explicitly V2/not part of
   the current product story — do not treat it as live.

**Navigation model:** a sidebar/Command-Home shell (NOT a tab bar) organized as
**Machine → Workspace/Project → Chat**. A user picks a paired machine, picks or creates a named
workspace (a project directory on that machine), and within it sees a chat-style history of agent
runs. Recently rebuilt (as of 2026-07-03): each workspace is its own pushed screen (not an
inline-expanding list), chat messages render full markdown (headings, code blocks with syntax
highlighting, lists), file previews and unified diffs render properly inline in chat, and there's
a Live Activity / Dynamic Island surface showing glanceable run status (agent name, elapsed time,
pending-approval risk tier) that updates via push even while the app is fully closed.

## Current feature inventory (as of 2026-07-02/03, code-verified — not aspirational)

**Implemented and working:**
- Durable chat threads with follow-up/continue (new `runId` per turn, works across all 4 vendor CLIs).
- Governed approvals: CLI hook → policy engine → phone inbox → approve/deny → hash-chained audit
  log. Fail-closed by default (`ask`); daemon unreachable blocks mutating actions; approval timeout
  → deny, not allow.
- Policy presets, a policy matrix view, a policy simulator, and a policy editor on the phone.
- Fleet setup-drift detector (flags when a paired machine's environment has drifted from expected).
- End-to-end-encrypted blind relay as the primary V1 transport — the relay server itself cannot
  read session content, verified architecturally (not just a claim).
- Multi-vendor dispatch spanning 4 CLIs (Claude Code, Codex, OpenCode, Kimi) including
  continue/resume — most competitors are single-vendor.
- Push-driven Live Activity: the Dynamic Island/Lock Screen surface updates via APNs even while
  the app is fully backgrounded, with a redacted alert body (no raw command text in the push
  payload) and a risk-tiered visual escalation (a high/critical pending approval visually reads
  differently than a routine one).
- A physical-device, app-fully-closed APNs approval loop has been proven live (not simulator-only)
  — tap Approve/Reject from the lock screen with the app never foregrounded, decision round-trips,
  agent resumes. This is a real, verified proof point, not a simulator-only claim.
- Apple Watch companion (push/deny/stop wired; full depth not independently re-audited recently).
- QR-based pairing to the relay; daemon install via `curl | sh` against a manifest-verified,
  SHA-256-checked binary download.
- A legacy, secondary SSH connection path (TOFU host-key confirmation, unified-PTY block terminal
  with OSC 133/7 shell-integration parsing) still exists in code and works, but is **deliberately
  not part of the V1 navigation** (see gaps below).

**Explicitly deferred / not part of V1, code exists but unwired from the UI:**
- A full interactive live terminal/shell from the phone. Today the in-app "Work Thread" is a
  **read-only activity log** of what the agent did — there is no live, typeable shell session
  reachable from the primary V1 navigation. (The code for a real terminal exists via the legacy SSH
  path, deliberately demoted.)
- SFTP file browsing, port forwarding, and a SOCKS preview proxy — code exists, unwired from V1 nav.
- Reverse SSH port forwarding (`tcpip-forward`) — a known, unfilled gap versus terminal-focused
  competitors like Termius/Blink/Warp.
- A "hosted-cloud execution" mode (run agents on Fly/GCP/Lightsail with prepaid credits, no
  always-on personal machine required) — exists in code, fully deferred to V2, zero references in
  current navigation.
- **Cross-device conversation history sync** — chat history today lives only in local on-device
  storage on whichever phone dispatched a given conversation. There is no way yet to see the same
  conversation from a second phone/iPad, or after an app reinstall. (A build to fix this — a
  host-owned conversation ledger plus an Apple-device CloudKit mirror — is in progress but not yet
  shipped as of this prompt's writing.)

**Known regressions / weaknesses (relevant context, not to be treated as fixed):**
- Biometric gate / app-lock was **removed** for V1 by a deliberate owner decision (2026-07-01) —
  approvals commit on a bare tap; the app never shows a Face ID/passcode prompt before approving a
  gated action. This is a real, current gap versus the original security narrative.
- Emergency "stop everything on every host" breadth has not been independently re-verified recently
  (per-host/Watch-side stop exists; true fleet-wide kill-switch reachability is unconfirmed).
- App Store submission itself (App Store Connect record, IAP product, privacy nutrition label,
  screenshots) has not been started — TestFlight is uploaded, but this is pure administrative work,
  not an engineering gap.

## Existing competitive intelligence already gathered — do not redo this part

This repository already contains a competitive-intelligence dataset, compiled 2026-06-23 through
2026-07-02, at `docs/competitive-intelligence/data/competitors.jsonl` and
`competitor-features.jsonl` (19 competitors profiled), plus a baseline report at
`docs/competitive-intelligence/reports/current-product-baseline.md`. It already covers, in depth:

- **Omnara** (YC S25) — mobile/web/desktop/Watch command-center for Claude Code + Codex; admitted
  no true E2EE (plaintext stored server-side); free tier + $9→$20/mo paid tier; cloud-sandbox
  continuity when the user's own host is offline (a feature Lancer does not have).
- **Anthropic's own "Claude Code Remote Control"** (native, launched 2026-02-25) — drive a local
  Claude Code session from phone/browser, Claude Code CLI only, outbound-only HTTPS, multi-session
  server mode, git-worktree isolation per session.
- **OpenAI's "Codex in ChatGPT mobile"** (launched 2026-05-14) — control Codex sessions on your own
  machine from the ChatGPT app, sandboxed execution (Seatbelt/bwrap/WSL2), network-off-by-default
  domain allowlist, available even on ChatGPT's free tier.
- **GitHub Copilot CLI Remote Control + Agent HQ** — stream a local CLI session to GitHub Mobile,
  approve/deny tool/file/URL permission requests; Agent HQ is rolling out as a unified cross-vendor
  (Anthropic/OpenAI/Google/Cognition/xAI) mobile mission-control layer across GitHub/VS Code/mobile.

**Do not re-research these four from scratch.** Spot-check only if something looks stale (all data
is dated; check for anything materially newer). The genuinely new research needed is below.

## What to research (new ground)

### 1. Warp (the AI-powered terminal, warp.dev)

Warp is desktop-first (macOS/Linux/Windows) — confirm current mobile/remote-control status
explicitly rather than assuming, since that materially changes how directly its patterns transfer
to a phone app. Research and report on:
- Its **Agent Mode** / agentic terminal features — how it presents an AI agent's actions, what
  permission/approval model it uses before running commands, how it distinguishes agent-run
  commands from user-run ones visually.
- **Warp Drive** and **Workflows** (saved/shareable command blocks) — is there an equivalent worth
  building for Lancer's workspace/project layer (e.g., saved prompt templates per workspace)?
- **Blocks** — Warp's signature UI unit (each command + its output as a distinct, foldable,
  shareable block). Does this translate to how Lancer should render a single agent turn/tool-call
  in its chat view, beyond what it already does?
- Notifications, session/thread management, and anything about background/async command
  monitoring — the closest conceptual overlap with Lancer's "watch an agent work, get notified when
  it needs you" model.
- Any Warp mobile app, companion app, or remote-session feature that exists today (confirm yes/no
  with a source — do not assume based on Warp's desktop reputation).

### 2. Conductor (conductor.build)

Conductor orchestrates **multiple parallel Claude Code sessions** using git worktrees — this is
the closest existing analog to what Lancer's newly-built Machine → Workspace → Chat hierarchy could
grow into (today Lancer has named workspaces per machine, but not yet a "run N agents in parallel
across N worktrees of the same repo and compare results" workflow). Research and report on:
- How it presents multiple parallel agent sessions/worktrees in one UI — the switching/comparison
  UX between them.
- Its approval/review workflow — how a user reviews and accepts/rejects a given worktree's changes
  before merging.
- Whether it has (or has announced) any mobile/remote-control surface, or is desktop-only.
- Anything about how it names/organizes parallel workspaces that Lancer's workspace model should
  borrow (Lancer's current workspace = one named directory on one machine; Conductor's model may
  imply workspace = one task, potentially spanning multiple parallel attempts).

### 3. Broader sweep (your judgment)

If you find other tools with a materially relevant mobile or multi-session-orchestration UX not
already covered above or in the existing competitive-intelligence dataset (e.g., Cursor's mobile
surface if one exists, Replit's agent mobile experience, any other Claude Code / Codex wrapper with
a genuinely distinct mobile UI worth studying), include them — but keep the primary focus on Warp
and Conductor since those are the explicit ask.

## Deliverable

A synthesized, cited report (not a raw link dump) structured as:
1. Warp findings, with explicit confidence-flagging where public documentation is thin (do not
   present inference as confirmed fact).
2. Conductor findings, same standard.
3. Any additional tools found in the broader sweep.
4. **A prioritized "features worth borrowing" section — the most important part.** Not a long
   feature list: pick the **3-5 highest-impact ideas specifically for Lancer's mobile app**
   (steering agents from a phone, approving gated actions, reviewing diffs/files, managing
   multiple named workspaces per machine), each with a one-line rationale grounded in one of
   Lancer's actual current gaps listed above (e.g., no live interactive terminal in the V1 mobile
   flow, no parallel-worktree/multi-attempt workflow yet, no saved prompt-template system per
   workspace, etc.) — not generic "this would be nice" reasoning.

Where a claim can't be verified from a primary source (official docs, the product's own site,
credible first-party technical writeups), say so explicitly rather than stating it as settled fact.
