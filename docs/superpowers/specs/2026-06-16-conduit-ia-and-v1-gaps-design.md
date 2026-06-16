# Conduit — IA + v1 Gap-Closure Design Spec

**Date:** 2026-06-16
**Status:** Design approved in brainstorming; session-adoption (§6) is the one open decision.
**Scope:** Information architecture, the two pulled-in v1 features, session-resilience scope, Settings organization, and competitive positioning. This spec covers *product/IA decisions*, not Swift implementation. The v1 view-cut list is confirmed separately at implementation time (see §8).

---

## 1. Problem & Goal

Conduit has ~120 catalogued surfaces in the design board but no settled v1 information architecture, and several capabilities that competitors ship are missing or unscoped. This spec locks the navigation model, folds redundant surfaces, picks the v1 gap features worth building now, and sets the resilience scope — so Swift implementation can start against a stable target.

**North star:** Conduit is *the governed way to let agents act on your machines* — agent runs on the host, phone is the remote control with a policy engine, tamper-evident audit, and Face-ID risk gating. We close parity gaps without diluting that governance moat.

---

## 2. Information Architecture — 3-tab model

**Decision:** Collapse from 4 tabs to **3**: **Fleet · Inbox · Settings**.

| Tab | Purpose | Notes |
|---|---|---|
| **Fleet** ◆ | Hosts + running agents/sessions. Tap an agent → its Run/session view. | The home surface. Includes New Chat / new session entry. |
| **Inbox** ⊞ | Two segments: **Pending** (approvals firewall) and **History** (audit timeline). | History absorbs the former standalone **Activity** tab. |
| **Settings** ⚙ | All configuration, grouped (see §5). | |

**Activity → History fold (decided).** The old Activity tab was "prettier logs of everything that happened" — useful, but it does not warrant its own tab. It is the *resolved* counterpart to Inbox's *pending* approvals, so it lives as the **History** segment inside Inbox. One mental model: Inbox = "things that need or needed my attention," split pending vs. resolved.

**Built — prototype verified.** The 3-tab bar and the Inbox Pending|History segmented control are live in the vanilla-JS prototype (`proto-shell.js` tab bar; `screen-tabs.js` inbox segments).

---

## 3. The two v1 gap features (pulled in)

### 3a. Mobile diff review (greenlit, prototyped)
A **single-column unified diff** viewer — not side-by-side, which is unreadable on a 402px phone. The agent pauses, the phone shows exactly what changed (`@@` hunk headers, red removed / green added line tints, collapsible unchanged regions, per-file switcher chips), and the user taps **Approve & continue** or **Request changes**. This is the visual companion to the approvals firewall: review the *content* of a change, not just its command.

- Prototype: `screen-diff.js`, reachable from `chat-resumed → Review changes · 2 files`. Verified rendered.
- Rationale: Moshi has side-by-side git diff via a host helper; we differentiate with a *mobile-first unified* view wired directly into the approval loop.

### 3b. Two-way voice (greenlit, not yet prototyped)
Speak to the agent and hear status/results back. Happy Coder and Omnara both ship real-time two-way voice; Moshi has on-device dictation only. This is table stakes for the category. v1 target: speech-to-text for prompts + spoken summaries of agent state/approvals. Full duplex streaming is a stretch goal.

---

## 4. Session resilience — scope A+B (decided)

Two distinct failure modes:

1. **Transport drop** (phone loses network, roams, sleeps) — *host keeps running.* **In scope (A+B).**
2. **Host offline** (the machine the agent runs on sleeps/dies) — *compute stops.* **Deferred** (needs cloud execution; future/premium tier, Omnara-style).

**v1 commitment (A+B):**
- **A — Host-side detached persistence:** the agent survives the phone disconnecting (it already runs under conduitd on the host; harden this so a dropped relay/SSH link never kills the run).
- **B — Resilient/roaming reconnect:** the phone re-attaches cleanly after network change/sleep, resuming the live block stream where it left off (Mosh-style feel, our own transport).
- **Trust indicator:** a visible "session persists" affordance so the user *knows* their run is safe when they pocket the phone. The anxiety this removes is the feature.

**Explicitly out of v1:** cloud session migration for the *laptop-is-the-host* case (true Omnara parity). Documented as a premium-tier candidate.

---

## 5. Settings organization (Claude's call, per owner)

All 18 Settings surfaces are real and functional; none cut. Grouped for sense, not flattened:

- **Connection & Hosts** — SSH hosts, relay/pairing (E2E relay, 6-digit pair, Tailscale funnel), Doctor (host diagnostics).
- **Security & Governance** — Policy engine (`policy.yaml`, presets, auto-allow/deny), Policy Simulator, blast-radius/risk thresholds, Face-ID gate, audit-chain export (JSON/JSONL), Secrets vault, biometric SSH-key gate.
- **Agents & Sessions** — agent providers (Claude/Codex/Gemini/etc.), startup command / auto-resume, session-persistence + resilience controls (§4), QuotaGuard.
- **App & Appearance** — theme/appearance, notifications, about/version.

**Deferred:** Git files browser + file preview — punted to a later milestone per owner.

---

## 6. Session adoption / takeover — OPEN (recommended approach inside)

**The dealbreaker question:** if a user starts a bare `claude` (or any agent) in their own terminal — *not* launched from Conduit — does that session appear in Conduit and can they continue it from the phone?

**Today: no.** conduitd only controls agents *it* spawned — it owns their PTY, parses their OSC-133 block markers, and installs the approval-firewall interception at launch. A `claude` started in Terminal.app/iTerm is a child of that terminal's shell with a PTY conduitd has no handle to. No PTY handle ⇒ no input injection, no approvals, no blocks.

**How competitors actually do it:** they don't attach to a pre-existing bare process either. Happy Coder requires you to launch via `happy` (a wrapper around Claude Code); Omnara wraps via its CLI/SDK or runs in its cloud. The "open the app and it's just there" magic = *the session was started through their shim* + persistence. There is no free attach to an arbitrary running `claude`.

**Three mechanisms for Conduit (recommendation = A primary + B visibility):**

- **A — Launch-through-Conduit shim (RECOMMENDED, primary).** The host installer drops a frictionless `claude` shell alias / `conduit run` wrapper that routes the launch through conduitd. conduitd owns the PTY from byte zero ⇒ full control, approvals, blocks, and §4 resilience for *every* session the user starts. Cost to user ≈ zero (alias is invisible); cost to us = installer + wrapper plumbing we largely already have.
- **B — Read-only session discovery (RECOMMENDED, visibility layer).** conduitd watches the agent's on-disk transcript store (e.g. Claude Code's `~/.claude/projects/**/*.jsonl`) and surfaces *externally-started* sessions in Fleet as read-only mirrors — you can *watch* a bare session from the phone even if you can't drive it. "Take over" then prompts to attach (via C) or relaunch through the shim.
- **C — tmux/multiplexer adoption (DEFER).** If the bare session runs inside tmux, conduitd can `pipe-pane` to mirror output and `send-keys` to inject input → genuine read/write takeover of an externally-started process. Full control of bare non-tmux sessions is otherwise not possible without ptrace-grade hacks. Defer unless users demand driving non-shim, non-tmux sessions.

This is a sibling to §4 — call the bundle **Session Continuity**: §4 keeps a *Conduit-owned* session alive across drops; §6 brings *externally-started* sessions into Conduit.

### Decision (owner, 2026-06-16): do A+B+C, gated on research → **research complete, architecture revised**

The research pass (`docs/audit/session-continuity-research-2026-06.md`, opencode + Claude-verified) confirmed the core instinct (shim is the real answer; nobody adopts bare processes) but surfaced **two materially better mechanisms** than tmux-injection. Revised v1 architecture:

- **A — Launch-through-Conduit shim (PRIMARY, v1).** Build it as **three layers** — PATH-level shim binary + shell function + managed env var (`CONDUIT_CLAUDE_WRAPPER_SHIM`) — copying cmux's proven approach. This is the only way to survive `env claude`, non-interactive shells, user aliases, and IDE-spawned agents. The shim is also the *single biggest risk* (silent failure across shells) → ship a `conduit doctor` wrapper-coverage check.
- **B — Read-only transcript discovery (v1).** Watch each agent's on-disk transcript (`~/.claude/projects/**/*.jsonl`, `~/.codex/sessions/**/rollout-*.jsonl`, `~/.gemini/tmp/**`) to surface even truly-bare sessions in Fleet, read-only.
- **Takeover via `--resume`, NOT tmux injection (v1 — replaces old "C-as-takeover").** "Take Over" reads the bare session's transcript, then **relaunches it under conduitd with `claude --resume <session-id>`** (universal across all three agents). The continued session runs with the **approval firewall + audit chain fully intact** — this *resolves* the governance-collision caveat instead of accepting it. Limitation: resumes at a conversation boundary, not mid-turn; if the bare agent is mid-execution the user waits or kills it.
- **tmux = persistence container, not adoption driver (v1).** Spawn conduitd-owned agents inside a named tmux session (`conduit-<id>`) so the run survives conduitd restart and is re-attachable. This is §4's process-survival mechanism.
- **C — tmux-injection (`pipe-pane` + `send-keys`) demoted to UNGUARDED BETA (v1.x, opt-in).** Only for driving a still-running bare session that can't be `--resume`d. Bypasses the firewall → ships behind a prominent red "this session is unguarded — approvals, audit, and risk scoring are off" banner, never auto-approves, and logs the adoption event. Carries real risks (control-char injection, concurrent-input races) → not core v1.
- **Agent SDK / app-server as an alternative launch mode (STRONGLY CONSIDER — see §6a decision).** Claude Agent SDK (`@anthropic-ai/claude-agent-sdk`) gives programmatic tool-approval callbacks + `SessionStore` *without* terminal parsing; Codex exposes `codex app-server --listen ws://`. Happy Coder + Omnara both migrated to the SDK in 2026. Potentially a cleaner approval firewall than OSC-133 PTY parsing.
- **Transport resilience (Mosh/QUIC) deferred to v2.** Tailscale/WireGuard already roams at the network layer; v1 = WireGuard tunnel + conduitd stream buffering. (Refines §4-B: roaming *transport* is mostly already handled; v1 effort goes to process persistence + buffering, not a custom transport.)

**Net:** the security caveat is no longer "accept an unguarded adopted session" — the `--resume` takeover brings externally-started sessions *under* governance, which is on-brand for the moat. tmux-injection survives only as an explicitly-labeled escape hatch.

### §6a — Open fork for the owner: commit to SDK launch mode in v1?
The one genuinely undecided item. Either keep **PTY-spawn + OSC-133 parsing** as the sole launch path for v1 (SDK is v1.x), or **adopt the Claude Agent SDK as a first-class launch mode now** (cleaner approvals, but a vendor dependency and no raw-terminal UI for that mode). Pending owner decision.

---

## 7. Competitive positioning (summary; full report: `docs/audit/competitive-landscape-2026-06.md`)

- **Moat (nobody else combines):** policy engine + tamper-evident audit chain + blast-radius/Face-ID gating + Warp-style block terminal + on-device secrets vault + Doctor + on-host architecture.
- **Primary threats:** Happy Coder (free, OSS, E2EE, multiplatform — eats the privacy story) and Moshi (polish, Mosh resilience, Apple-ecosystem surfaces, 4.8★/750+).
- **Gap-close priority:** (1) resilience A+B [decided §4], (2) two-way voice [greenlit §3b], (3) mobile diff review [greenlit §3a], (4) Apple Watch / Live Activities / Dynamic Island [open], (5) web/Android for reach [open, biggest reach gap], (6) usage/quota rings [open — QuotaGuard data exists, no visual surface], (7) image paste [open].

---

## 7b. Parallel agents via git worktrees (research-backed; full report: `docs/audit/git-worktrees-mobile-research-2026-06.md`)

**Decision shape:** capture the design now; recommended phasing = **single-agent diff review + governed merge in v1 (already greenlit §3a, extended here), full parallel-worktree fleet in v1.x.** Pending owner confirm on timing.

**Why worktrees.** A `git worktree` checks a branch out into its own directory sharing one `.git` store, so N agents get isolated copies without colliding. Git enforces one branch per worktree ⇒ **one branch = one worktree = one agent.** This is the industry-consensus isolation primitive (Conductor, Crystal/Nimbalyst, Vibe Kanban, Claude Squad, Omnara, and Claude Code's own worktree flag all use it). The power-pattern is **fan-out → review → merge the winner** (discarding a worktree is free).

**Maps cleanly onto the 3-tab IA — no new tabs:**
- **Fleet** = the worktree list. One card per agent: branch name, status badge, agent type, `N files +X/−Y` diff summary, `[View Diff] [Stop]`. Swipe-to-delete removes the worktree (Face ID if unmerged). An agent *is* a worktree in this model.
- **Inbox** = a **consolidated approval stream across all N agents**, each item tagged with its branch — defeats per-agent approval fatigue. Reuses the §2 Pending/History structure.
- **Settings** = auto-cleanup toggle, merge strategy (squash default), merge-to-protected-branch policy, max parallel agents.

**Governed merge-back = a genuine market gap (moat extension).** No surveyed competitor gates the merge to `main` — they all one-click merge. Conduit's flow: review diff → **mandatory diff-summary screen** → "I reviewed the changes" ack → **Face ID** → `git merge --squash` → conflict *detection* (not resolution) → push + auto-remove worktree → audit-chain entry with Face-ID attestation + `worktree_id`. This directly mitigates the single biggest UX risk: *accidentally merging unreviewed agent output because the phone made it too easy.*

**On a phone (v1.x scope):** create agent/worktree, review unified diff, approve+merge (governed), auto-cleanup, list active worktrees with status.
**YAGNI on a phone (desktop-only):** interactive rebase, cherry-pick, per-line staging, blame, submodule mgmt, a worktree file browser. (This supersedes the earlier blanket "git files/preview deferred" — the *file browser* stays deferred; *diff review + worktree fleet* are in scope.)

**Host-side notes:** `node_modules`/`target`/`.build` are duplicated per worktree (the #1 disk trap) → conduitd should lean on pnpm/cargo shared stores. conduitd uses Claude Code's native worktree support when present, else manual `git worktree add`, falling back per-agent for Codex/Gemini — invisible to the phone UI.

**§7b open fork for the owner:** parallel-worktree fleet = **v1 or v1.x?** (Single-agent diff review + Face-ID merge gate is v1 regardless.)

---

## 8. Implementation gate (do not skip)

Before any Swift dispatch: **confirm the v1 view-cut list with the owner** ("we don't need everything"). The board has ~120 surfaces; v1 ships a deliberate subset. This spec defines the *target*, not the cut. Per repo workflow, Swift edits are dispatched to opencode; Claude plans and verifies (app-target build).

---

## 9. Open items rollup

| Item | State |
|---|---|
| 3-tab IA + Activity→History fold | ✅ Decided, prototyped |
| Mobile diff review | ✅ Greenlit, prototyped |
| Two-way voice | ✅ Greenlit, not prototyped |
| Session resilience A+B / defer cloud | ✅ Decided |
| Settings grouping | ✅ Decided |
| Git files/preview (file *browser*) | ⏸ Deferred |
| Parallel agents via worktrees (§7b) | ✅ Design captured; governed merge-back = moat extension — 🟡 timing fork: v1 vs v1.x |
| **Session adoption (§6)** | ✅ Research-revised: A + B + `--resume` takeover (v1, governance-preserving); tmux = container; tmux-injection → unguarded beta (v1.x); transport resilience → v2 |
| **SDK launch mode (§6a)** | 🟡 **Open fork — awaiting owner: PTY-only v1 vs. adopt Agent SDK now** |
| v1 view-cut list | 🟡 Confirm at Swift time (§8) |
