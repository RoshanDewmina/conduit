# 13 — Design Directions

> Wave-3 synthesis. Three genuinely different directions, each applied to the same core flows, then scored with a weighted decision matrix. Not three colour variations — they differ in product shell, chat's role, density, and personality. All three honor the non-negotiable constraints: **sidebar shell (no tab bar), V1 blind E2E relay (no phone SSH), security fail-closed**.

## The fork these directions resolve

Every research lane converged on three things — governance-first, attention-first home, chat-as-depth — but left one genuine open question: **what does the user see first, and how visible is "chat" in the product's spine?** That is the axis the three directions span:

```
Direction C ───────────── Direction A ───────────── Direction B
Safety-triage first        Operations console         Conversation-led
(approval inbox = home)     (dashboard = home)         (thread list = home)
  most differentiated        balanced                    most familiar
  narrowest                  broadest                    closest to Claude-clone risk
```

---

## Direction A — "Command Console"

**Design thesis.** An attention-first operations dashboard is the home. The first screen answers "what needs me, and what's happening across my machines?" Chat/runs are a depth surface reached by dispatching or drilling in. This is the research consensus made concrete.

- **Target user perception:** "a calm control room for my agents" — serious, scannable, in control.
- **Navigation model:** sidebar/drawer shell; Command Home as the default root; Machines, Needs Attention, Governance, Settings as roots; everything else drills in.
- **Home-screen concept:** three bands — **Act Now** (pending approvals, blocked runs, offline hosts), **Continue** (recent threads / active runs), **Machines** (compact status summary) — with a primary **New run** CTA.
- **Chat concept:** a depth surface; threads sorted by state; context chips in the header; run settings (model/budget) demoted from the hero.
- **Approval-flow concept:** approval cards on Home → detail → risk-tiered decision (see [08](08-approval-and-security-experience.md)).
- **Fleet concept:** adaptive Machines root (single-machine board / ≤3 switcher).
- **Activity concept:** contextual drawer (global + per-machine).
- **Terminal concept:** read-only block transcript + follow-up + Stop (V1).
- **Onboarding concept:** demo approval → mode → install bridge → pair → verify → policy → contextual permissions.
- **Upgrade concept:** contextual upsell at scale friction + persistent Settings row; no onboarding paywall.
- **Design-system principles:** warm control room; de-glassed buttons; status = glyph+word+color; mono only in code surfaces.
- **Reference apps (pattern level):** Linear (dense lists + command), Datadog/Better Stack (attention + status), Tailscale (host list), GitHub Mobile (status drill-in).
- **Borrowed at the pattern level:** attention-first triage, dense operational lists, command/search layer.
- **Distinctively Lancer:** the warm chrome around a dark terminal hero; governance bands as the home; emergency stop as a first-class control.
- **Accessibility implications:** moderate — dense lists need Dynamic Type reflow + VoiceOver labels, but uses native lists heavily.
- **Technical complexity:** **Low-Medium** — closest to the current app; mostly consolidation + wiring (status binding, stubbed-number removal, paywall wiring).
- **Major risks:** can feel "busy" if bands aren't disciplined; requires the status-integrity fixes to land first or it amplifies the trust-leak.
- **Advantages:** lowest build cost, best fit to current architecture, strongest governance signal, lowest regression risk.
- **Disadvantages:** least novel; relies on execution polish to feel premium.

---

## Direction B — "Conversation-Led Governance"

**Design thesis.** Home is the **work inventory** — a thread/run list sorted by state (Needs you → Running → Failed → Done) — with governance surfaced as inline chips and a persistent status bar, not a separate dashboard. The composer is elevated; "chat" is reframed as "runs." Closest to Codex-mobile / Linear-agents.

- **Target user perception:** "a fast agent cockpit" — conversational, immediate, work-centric.
- **Navigation model:** sidebar shell; **Recent work (threads)** as the default root; Needs Attention, Machines, Governance as roots; a prominent composer.
- **Home-screen concept:** state-sorted run list; each row = agent + machine + repo + status + newest artifact; a persistent status bar shows fleet health + pending count; primary CTA is the composer ("Start work").
- **Chat concept:** elevated to the spine but reframed — run turns, evidence cards (diff/test/file/approval), a visible work timeline (planning/editing/testing/waiting).
- **Approval-flow concept:** approvals appear inline in the relevant run AND in a global Needs Attention; same risk-tier engine.
- **Fleet concept:** Machines as a root, but secondary to the run list; surfaced via the status bar.
- **Activity concept:** woven into each run's timeline + a global audit drawer.
- **Terminal concept:** the run body IS the block transcript; follow-up composer is always present.
- **Onboarding concept:** same trust checklist, but lands on the run list (with a seeded demo run).
- **Upgrade concept:** contextual upsell on scale/automation; persistent row.
- **Design-system principles:** warm control room, but the composer + run cards carry more visual weight.
- **Reference apps:** Codex mobile, GitHub Copilot agent, Linear agents/coding-sessions, Cursor.
- **Borrowed at the pattern level:** state-sorted work list, run timeline, evidence cards, queued follow-ups.
- **Distinctively Lancer:** governance chips on every run (policy mode, blast radius, budget); persistent fleet status bar; the run is *governed*, not just a chat.
- **Accessibility implications:** medium — run timelines + evidence cards need careful VoiceOver ordering; composer-first helps one-handed reach.
- **Technical complexity:** **Medium** — reuses the strong chat/run model but restructures the home and elevates the composer; risk of regressing the governance-first signal.
- **Major risks:** **closest to the "Claude clone" failure mode** — must work hard so the run/evidence/governance framing reads as supervision, not assistant-chat; governance can become invisible if it's only chips.
- **Advantages:** fastest dispatch, leverages the already-rich `NewChatTabView`/`ChatConversation` model, feels modern and agent-native.
- **Disadvantages:** weakest governance-forward identity; highest differentiation risk; demotes the dashboard.

---

## Direction C — "Safety-Triage Console"

**Design thesis.** Home **is** the approval/attention inbox — the app opens directly to "what needs your decision right now." Maximally differentiated from Claude (no chat at home at all), leaning hardest into the governance/safety identity. Like an on-call/security triage app.

- **Target user perception:** "the safety instrument for my agents" — a guard rail you trust to wake you only when it matters.
- **Navigation model:** sidebar shell; **Needs Attention (inbox)** as the default root; Machines, Runs/Threads, Governance, Settings as roots.
- **Home-screen concept:** a triage queue — pending approvals (risk-sorted), blocked runs, degraded hosts — with a strong, calm **empty/zero state** ("All clear — 3 agents running cleanly") when nothing's pending; emergency stop one tap away.
- **Chat concept:** a secondary destination; dispatch is deliberate, not the home gesture.
- **Approval-flow concept:** the centerpiece — full risk-tier model, diff drill-in, severity sentences, batch (low/med), audit (see [08](08-approval-and-security-experience.md)).
- **Fleet concept:** Machines root; health feeds the triage queue (degraded host = a triage item).
- **Activity concept:** prominent — the audit trail is a first-class governance surface here.
- **Terminal concept:** read-only block transcript reached from a run; not foregrounded.
- **Onboarding concept:** demo approval is the literal first screen → the whole product is "approvals done right."
- **Upgrade concept:** monetize scale/automation; never the safety queue itself.
- **Design-system principles:** strongest restraint — monotone status, the dark terminal as a rare drill-in, calm chrome dominant.
- **Reference apps:** incident.io / PagerDuty (triage), 1Password/Bitwarden (consequential-action trust), GitHub security alerts.
- **Borrowed at the pattern level:** on-call triage queue, severity sorting, zero-state reassurance, audit-first.
- **Distinctively Lancer:** the only direction where the *first thing you see* is the governance decision — unmistakably not an AI chat app.
- **Accessibility implications:** medium — triage rows + risk badges must be icon+word+shape; strong VoiceOver story for the decision controls.
- **Technical complexity:** **Medium** — reuses `InboxView`/`ApprovalRepository` heavily but demotes Home/New Chat; needs excellent empty states or it feels empty/narrow.
- **Major risks:** feels narrow or empty when nothing's pending; can under-serve the "I want to start work" intent; dispatch becomes a second-class gesture.
- **Advantages:** maximal differentiation; strongest trust/safety signal; aligns perfectly with "lead with policy/audit/blast-radius."
- **Disadvantages:** weakest for proactive work initiation; depends entirely on zero-state quality; risks feeling like a single-purpose utility rather than a control plane.

---

## All three applied to Core Flow 1 (first launch → approve → return)

```
First launch → Understand Lancer → Pair a host → Receive an agent request → Review approval → Approve/reject → Observe completion → Return to active sessions
```

| Step | A — Command Console | B — Conversation-Led | C — Safety-Triage |
|---|---|---|---|
| Understand | Demo approval card on a seeded Command Home | Demo run in the run list | Demo approval **is** the home |
| Pair | Setup checklist (shared component) | same | same |
| Receive request | Appears in **Act Now** band + push | Inline in the run + global badge | Top of the triage queue + push |
| Review | Tap card → detail | Tap run → inline approval | Tap queue item → detail (centerpiece) |
| Approve/reject | Risk-tiered decision | same, inline | same, foregrounded |
| Observe completion | Completion summary card on Home | Run timeline → completion summary | Item clears → "All clear" zero-state |
| Return | Home dashboard | Run list | Triage queue (empty/clear) |

## All three applied to Core Flow 2 (free user hits a paid capability)

```
Free user encounters a paid capability → Understand value → View pricing → Purchase or decline → Return to task
```

| Step | A | B | C |
|---|---|---|---|
| Encounter | Taps "Add 3rd host" / a Pro feature | Taps a Pro automation in a run | Taps "Auto-approve rule" in triage |
| Understand value | Contextual `PaywallSheet(featureName:)` naming that benefit | same, from the run context | same, from the triage context |
| View pricing | One-time Pro, benefit list (no comparison table for 1 SKU) | same | same |
| Purchase/decline | StoreKit sheet; restore reachable | same | same |
| Return | Back to the dashboard, feature unlocked or not | Back to the run | Back to the triage item |

All three share the **same monetization model** (StoreKit 2 one-time Pro, contextual upsell, no onboarding paywall) — monetization is not a differentiator between directions.

## Weighted decision matrix

Scores 1–5 (5 best) × weight; weights adjusted from the plan's suggestion (raised **Fit with architecture** because this is a solo-dev incremental redesign, and **Differentiation** because "stop looking like Claude" is the explicit brief).

| Criterion | Weight | A — Command Console | B — Conversation-Led | C — Safety-Triage |
|---|--:|:--:|:--:|:--:|
| Core workflow usability | 20 | 4 (80) | 4 (80) | 3 (60) |
| Trust & safety | 15 | 4 (60) | 3 (45) | 5 (75) |
| Product differentiation | 15 | 4 (60) | 2 (30) | 5 (75) |
| Fit with Lancer's architecture | 15 | 5 (75) | 4 (60) | 4 (60) |
| Information scalability | 10 | 4 (40) | 4 (40) | 3 (30) |
| Accessibility | 10 | 4 (40) | 3 (30) | 4 (40) |
| Implementation effort (5 = least) | 5 | 5 (25) | 3 (15) | 3 (15) |
| Monetization fit | 5 | 4 (20) | 4 (20) | 4 (20) |
| Apple-platform quality | 5 | 4 (20) | 4 (20) | 4 (20) |
| **Total** | **100** | **🥇 420** | **340** | **395** |

**Result: Direction A (Command Console) wins (420)**, with **Direction C (Safety-Triage) a close second (395)** on trust/differentiation, and **Direction B (Conversation-Led) third (340)** — strong usability but penalized on differentiation (Claude-clone risk) and the weakest governance signal.

## Reading of the matrix

A and C are close, and they're close *because they agree* on the important thing: the home must be governance/attention, not chat. A wins on **fit + lower effort + scalability + balanced usability**; C wins on **pure trust + differentiation** but loses on "I want to start work" usability and depends entirely on zero-state quality. B's only real win is dispatch speed, which A captures with a prominent New-run CTA without taking on the clone risk.

**The synthesis is obvious:** ship A, and graft C's safety-first framing (risk-sorted attention, audit-forward, the demo-approval onboarding) and B's run/evidence vocabulary (state-sorted threads, evidence cards, run timeline) into it. That is the recommended direction — see [14](14-recommended-direction.md).

## Patterns that must not be mixed

- Don't combine A's dashboard home **and** B's run-list home into two competing homes — pick the dashboard, make the run list a root *within* it.
- Don't let B's "elevate the composer" pull chat back to the home gesture — that reintroduces the Claude-clone problem A/C exist to solve.
- Don't graft C's "open straight to the inbox" as the default if it means the dispatch intent gets buried — keep New-run one tap from Home.
- Don't mix glass-heavy chrome (a tempting "premium" move) with the dense-list content layer — [12](12-design-system-recommendations.md) forbids glass in content.
