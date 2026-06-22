# Lancer v1 — Agreed Feature Set

**Date:** 2026-06-16  
**Source:** Synthesis of owner decisions from the Claude Code session (`6c747743-5c80-4fc4-8640-a99427ae7bb0`) plus subagent research in `docs/audit/` and the IA + gap-closure spec.

---

## 1. Product Identity

Lancer is **the governed way to let agents act on your machines**. The agent runs on the user's own host via the resident daemon `lancerd`; the phone is the remote control. The moat is governance: policy engine, tamper-evident audit chain, blast-radius risk scoring, and Face-ID/WebAuthn gating.

---

## 2. Information Architecture (4 tabs)

| Tab | Purpose |
|---|---|
| **Fleet** ◆ | Hosts + running agents/sessions/worktrees. Home surface. |
| **Inbox** ⊞ | Pending approvals (firewall) only. |
| **Activity** ⧗ | Governance audit timeline / history. The moat surface. |
| **Settings** ⚙ | Connection, security/governance, agents/sessions, appearance. |

---

## 3. v1 Core Features

### Onboarding & Setup
- Onboarding flow (first-launch)
- SSH host pairing / TOFU host-key prompt
- E2E relay pairing (6-digit code)
- Biometric SSH-key gate

### Fleet (home)
- Host list + connection status
- Running agent/session cards
- Agent = worktree card in Fleet (single-agent v1; full parallel fleet v1.x)
- One-tap "New Agent" → create worktree + launch
- Worktree list with status (branch, agent type, diff summary)
- Stop agent / clean up worktree
- Quota rings (SwiftUI `Gauge` over existing `QuotaGuard` data)

### Inbox (Pending approvals only)
- Pending approval stream
- Approval cards with risk tier (Low/Medium/High/Critical)
- Approve / Deny / Approve Always actions
- Face-ID gate on Critical actions
- Tap-through to unified diff review

### Activity / Audit (4th tab)
- Tamper-evident governance timeline
- Event detail with chain hash, host, worktree, policy, decision
- Diff summary and merge-back audit entries
- Export / share audit bundle

### Diff Review
- Mobile unified diff review (single-column, collapsible hunks, AI-tinted code)
- Per-file switcher
- Governed merge-back: diff summary → ack → Face ID → `git merge --squash` → audit log

### Session Chat
- Warp-style block terminal
- Live block stream (agent thinking → streaming → approval → done)
- TUI rendered inside block (vim/htop/etc.)
- No full-screen escalation
- Two-way voice (speech-to-text prompts + spoken status summaries)

### Settings
- Connection & Hosts (SSH hosts, relay/pairing, Tailscale, Doctor)
- Security & Governance (policy engine, presets, risk thresholds, Face-ID gate, audit export, secrets vault)
- Agents & Sessions (providers, startup/auto-resume, resilience, QuotaGuard)
- App & Appearance (theme, notifications, about)

### Session Continuity
- A — Launch-through-Lancer shim (PATH binary + shell function + env var)
- B — Read-only transcript discovery of bare sessions
- Takeover via `--resume` (relaunch under lancerd, governance-preserving)
- tmux as persistence container for lancerd-owned agents
- Resilient reconnect after phone network change/sleep

### Apple Ecosystem (v1 subset)
- Quota rings (in-app) — no architecture cost
- Live Activity / Dynamic Island / Lock Screen status: **hybrid A+B**
  - **Hosted relay:** full push-driven Live Activities with `liveactivity` push type and APNs sender on relay
  - **Self-host:** app-foreground Live Activities + UNNotification fallback; no relay-side APNs sender
  - Inline Approve/Deny inside Live Activity is a v1.x target, not a v1 blocker
- Widgets / Watch complications — reuse Live Activity/Gauge views, post-v1

### Web Dashboard (v1)
- Web client as `role=phone` blind-relay peer
- Fleet, Inbox/approvals, agent detail surfaces
- WebAuthn/passkey gate for Critical approvals
- Wires to real relay; no mock backend

### Session Chat
- Warp-style block terminal
- Live block stream (agent thinking → streaming → approval → done)
- TUI rendered inside block (vim/htop/etc.)
- No full-screen escalation
- Two-way voice (speech-to-text prompts + spoken status summaries)

### Settings
- Connection & Hosts (SSH hosts, relay/pairing, Tailscale, Doctor)
- Security & Governance (policy engine, presets, risk thresholds, Face-ID gate, audit export, secrets vault)
- Agents & Sessions (providers, startup/auto-resume, resilience, QuotaGuard)
- App & Appearance (theme, notifications, about)

### Session Continuity
- A — Launch-through-Lancer shim (PATH binary + shell function + env var)
- B — Read-only transcript discovery of bare sessions
- Takeover via `--resume` (relaunch under lancerd, governance-preserving)
- tmux as persistence container for lancerd-owned agents
- Resilient reconnect after phone network change/sleep

### Apple Ecosystem (v1 subset)
- Quota rings (in-app) — no architecture cost
- Live Activity / Dynamic Island / Lock Screen status + Approve/Deny **deferred to relay-tier decision** — design captured, gated on push-sender architecture
- Widgets / Watch complications — reuse Live Activity/Gauge views, post-v1

### Web Dashboard (v1)
- Web client as `role=phone` blind-relay peer
- Fleet, Inbox/approvals, agent detail surfaces
- WebAuthn/passkey gate for Critical approvals
- Wires to real relay; no mock backend

---

## 4. Explicitly Deferred (not v1)

| Feature | Deferred to | Rationale |
|---|---|---|
| Cloud session migration (host offline) | Premium / future | Omnara-style; breaks on-host privacy model |
| Full parallel-worktree fleet compare | v1.x | Single-agent diff+merge in v1 |
| Git files browser / file preview | v1.x+ | Owner-punted; diff review is the mobile need |
| Standalone Apple Watch app | Post-v1 | Complications + Smart Stack come free with widget extension |
| Inline Approve/Deny inside Live Activity | v1.x | Requires relay-pushed Live Activity + secure intent handling |
| Image paste into prompts | Open | Competitive parity item, not v1-critical |
| Web/Android full parity (live blocks, reply-to-agent) | Relay-extension pass | Needs new `blockChunk`/`agentReply` message types |
| tmux-injection adoption (unguarded r/w) | v1.x beta | Bypasses approval firewall; ship as opt-in |
| Agent SDK launch mode | Open fork | Owner must decide PTY-only v1 vs SDK now |
| Native roaming transport (Mosh/QUIC) | v2 | Tailscale/WireGuard handles roaming at network layer |

---

## 5. Frontend Coverage vs. Design Board

### v1 board pages
| Board Page | v1 Role |
|---|---|
| Lancer v1 Features.dc.html | ✅ Spec overview |
| Lancer Onboarding.dc.html | ✅ v1 |
| Lancer Pairing Hosts SSH.dc.html | ✅ v1 |
| Lancer Fleet.dc.html | ✅ v1 (worktree/agent cards + quota rings) |
| Lancer Quota Rings.dc.html | ✅ Gauge component reference |
| Lancer Agent Worktree Detail.dc.html | ✅ Drill-down from Fleet |
| Lancer New Chat.dc.html | ✅ v1 |
| Lancer Session Chat.dc.html | ✅ v1 (blocks + voice) |
| Lancer Voice Input.dc.html | ✅ Two-way voice surface |
| Lancer Inbox.dc.html | ✅ Pending approvals only |
| Lancer Diff Review.dc.html | ✅ Mobile unified diff |
| Lancer Activity Audit.dc.html | ✅ 4th tab governance timeline |
| Lancer Live Activity.dc.html | ✅ Hybrid A+B design captured |
| Lancer Settings.dc.html | ✅ v1 |

### Beyond-v1 board pages
| Board Page | New Home |
|---|---|
| Lancer Approvals.dc.html | 🔄 Absorbed into Inbox + Diff Review |
| Lancer Activity.dc.html | 🔄 Replaced by Activity/Audit tab |
| Lancer Git Files Preview.dc.html | ⏸ Deferred |
| Lancer Agent Cloud Hosted.dc.html | ⏸ Beyond v1 |
| Lancer Worktrees.dc.html | ⏸ Beyond v1 (full parallel fleet; single-agent worktree in Fleet v1) |
| Lancer Quota Spend.dc.html | 🔄 Partial — quota rings in Fleet/Settings v1; full spend analytics beyond |
| Lancer Platform Surfaces.dc.html | 🔄 Partial — rings now; widgets/post-v1 |
| Lancer Design System.dc.html | 📚 Reference (not a product surface) |

---

## 6. Open Owner Decisions Blocking Swift Dispatch

1. **SDK launch mode in v1?** PTY-only vs adopt Claude Agent SDK now.
2. **Parallel-worktree fleet timing?** Single-agent diff+merge in v1 regardless; confirm full N-agent fan-out in v1.x.
3. **Live Activity push tier?** Decision: hybrid A+B — hosted relay gets full push Live Activities; self-host gets app-foreground Live Activities + UNNotification fallback. Relay APNs sender scoped to `liveactivity` push type.

---

## 7. Recommended v1 View-Cut for Swift Port

Port these views first (stable, owner-approved):

1. Onboarding
2. Pairing / Host setup
3. Fleet (with worktree/agent cards + quota rings)
4. Agent/Worktree Detail
5. New Chat / New Agent
6. Session Chat (blocks + voice)
7. Inbox (Pending approvals)
8. Diff Review
9. Activity / Audit (4th tab)
10. Settings (grouped)
11. Live Activity / Lock Screen (hybrid A+B)
