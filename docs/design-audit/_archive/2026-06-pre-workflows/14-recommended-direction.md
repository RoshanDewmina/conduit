# 14 — Recommended Direction

> The final, coherent proposal: **Direction A "Command Console," with C's safety-first framing and B's run/evidence vocabulary grafted in.** Specific enough that an implementation agent can follow it without repeating the research. Honors all hard constraints (sidebar shell, V1 relay, fail-closed).

## One-paragraph statement

Lancer is a **warm control room for AI coding agents on your own machines.** The home is an attention-first **Command Console** — what needs you, what's running, what your machines are doing — not a chat prompt. Chat exists, but as a *governed run* you drill into, with evidence cards and a visible work timeline, never as the product's front door. Every consequential action passes a **risk-tiered approval** whose friction scales with blast radius. The whole thing looks like a calm operations instrument with a dark terminal at its center — unmistakably *not* a generic AI assistant.

## Design principles (the spine)

1. **Governance is the home, not chat.** The first screen is attention + status. (Resolves the Claude-clone brief.)
2. **Friction scales with blast radius.** Low-risk = one tap; critical = biometric + explicit confirm. Never uniform.
3. **Never display state the app can't back.** No stubbed numbers, no hard-coded footers — show "—" or an empty state instead. (For a governance product, a fake safety number is worse than none.)
4. **Status is never color alone.** Always glyph + word + (qualifier) + color-as-reinforcement.
5. **Mono is a domain signal.** Terminal/code/diff/paths only — never UI chrome.
6. **Glass is navigation chrome only.** Buttons and content are solid.
7. **Safety is free, scale is paid.** Never paywall a kill switch, an approval, or audit viewing.
8. **Lead with the demo.** First run proves the governed approval loop before asking for anything.

## Navigation model

```
Sidebar / drawer (iPhone) · NavigationSplitView (iPad)
├── Command Home (default)   ← Act Now · Continue · Machines · [New run]
├── Needs Attention          ← risk-sorted approval/triage queue (C's centerpiece, as a root)
├── New Chat / Start work     ← dispatch (one tap from Home)
├── Threads / Recent work     ← state-sorted run list (B's vocabulary, as a root)
├── Machines                  ← adaptive: single-machine board / ≤3 switcher
├── Governance                ← Policy · Audit · Secrets · Doctor · Usage (grouped)
└── Settings
Drawer top: account/org + active host switcher · Search/Command
Depth (never roots): approval detail · machine detail · session/terminal · audit detail · V2 cloud
```

## Core components (build/consolidate these)

| Component | Spec | Source doc |
|---|---|---|
| `DSMachineStatus` | `{glyph} {word} · {last-seen/step}`; color reinforcement only; states incl. `running/busy` + offline last-seen; bound to single `connectionState(for:)` | [09](09-fleet-activity-and-terminal.md) |
| Approval anatomy (one shared) | summary → risk badge + **severity sentence** → command/diff hero → scope chips → collapsed details → tiered decision row | [08](08-approval-and-security-experience.md) |
| `RiskBadge` | tier **word + glyph** + color (never color-only); VoiceOver hint carries the severity sentence | [08](08-approval-and-security-experience.md) |
| Patch diff drill-in | file list → expandable hunks (Diff/Original/Modified), `+/-` gutter glyphs | [08](08-approval-and-security-experience.md)/[12](12-design-system-recommendations.md) |
| Run card / timeline | state-sorted; chips (agent/machine/repo/policy/budget/model); `Queued→Planning→Editing→Testing→Waiting→Summarizing` | [07](07-chat-and-agent-experience.md) |
| Setup-checklist | reused in onboarding, Home empty state, Settings → Connection | [10](10-onboarding-and-pairing.md) |
| `DSButton` (de-glassed) | one filled `.accent` CTA per view; `secondary`/`ghost`/`quiet`/`destructive`(outline) | [12](12-design-system-recommendations.md) |
| Audit row | `{actor} {action} {target} · {time}`, `DSDiffChips` transitions, link-back-to-session | [09](09-fleet-activity-and-terminal.md) |
| Emergency Stop | per-session header (while running) + fleet "Stop all" + deny+stop in approvals; deep-linked from push, never a Live-Activity button | [09](09-fleet-activity-and-terminal.md) |

## Representative screen structures

**Command Home.** Top: relay/fleet status (live, never hard-coded). **Act Now** (risk-sorted: pending approvals → blocked runs → offline hosts) — cards, with a calm "All clear — N agents running cleanly" zero-state (C's graft). **Continue** — state-sorted recent runs (list). **Machines** — compact summary. Floating: **New run** CTA + AgentIsland (glass chrome).

**Approval detail.** Plain summary → risk badge + severity sentence → command (mono `$`) or diff drill-in → scope chips (cwd/host/#files/touches-git/network) → collapsed Details (session/policy rule) → tiered decision: low/med one deliberate tap; high action-sheet confirm; critical mandatory biometric, Deny as default.

**Run (chat) thread.** Header chips (agent/machine/repo/policy/budget/model). Body = block transcript + evidence cards (diff/test/file/approval) + work timeline. Persistent follow-up composer + Stop (while running). Long output collapses with "Show full output."

**Machines.** N=1 → rich board (status header, agents-on-host, stat tiles, per-machine activity, terminal entry, drift, disconnect). N≥2 → switcher list + focused board. V1: relay-status chip shows connection mode on tap. Do **not** ship a DIRECT affordance in V1 — DIRECT (SSH power-user) is post-V1 and V1 is relay-only.

## Visual hierarchy

Calm warm-sand chrome (default dark) → solid `surface` content cards (border elevation, no shadows) → the **dark terminal as the hero working surface** (always-dark, tighter radii). One filled terracotta accent per view. Monotone status + severity vocabulary. Glass only on sidebar / AgentIsland / status bar / sheet grabbers.

## Interaction rules

- Cards for urgent Act-Now items + compact summaries; **lists** for approvals, runs, machines, audit, logs.
- Sheets (native `.sheet` + detents) for approvals/reviews/switchers/filters; pushes for chat/terminal/detail; native `confirmationDialog`/alert for destructive confirms.
- Status ordering: approval-needing-decision → blocked agent → offline host → degraded relay → running → recent.
- One-handed: Approve/Stop/Send in the bottom third.

## Onboarding (the front door)

Demo approval → choose mode (account / self-hosted offline, visually equal) → install bridge (checklist, copyable command, "already installed", "not at my computer"→demo) → pair (QR primary / manual code; pre-camera explanation; relay status/expiry/retry/recovery) → verify first value (doctor/demo; checklist completion; target <3 min installed / <6 min fresh) → policy (Conservative/Balanced/Fast with examples) → contextual notifications + biometric → Command Home. **Resolve the pairing mental-model conflict first** (pick desktop-generates-code OR phone-generates, use it everywhere).

## Monetization

StoreKit 2 one-time Pro; **wire the dead paywall** at scale/automation triggers (3rd host, Pro feature tap) + persistent Settings row; **no onboarding paywall**; never paywall safety; Lancer Cloud stays V2 (US link-out). Fix the "SwiftData/RevenueCat" trust copy to match the real GRDB/StoreKit/Stripe stack.

## Accessibility (gates, not polish)

Dynamic Type via `dsSans/dsMono/dsDisplay` to AX5; contrast ≥4.5:1 body in both schemes + Increase Contrast; every status icon+word+shape; Reduce Transparency → solid; Reduce Motion → static island/PixelBox; VoiceOver hints carry consequence; 44×44 targets; Approve/Deny separated.

## What NOT to do

- Don't reintroduce a tab bar or a `Control`/`Activity` root.
- Don't make chat the home gesture (the clone trap).
- Don't show any safety/trust number the app can't back live.
- Don't put glass on buttons/content, or mono in UI chrome.
- Don't gate emergency stop, approvals, or audit viewing behind Pro.
- Don't ship a paywall in onboarding, or fake scarcity.
- Don't batch-approve high/critical; don't offer fake undo; don't let Watch approve high/critical.
- Don't expose V2 hosted-cloud surfaces in V1 navigation.

## Patterns that must stay consistent app-wide

One approval anatomy everywhere · one severity vocabulary (risk 0–3) · one status descriptor · one filled accent button per view · one header pattern (fix the double back-chevron) · mono confined to code surfaces · glass confined to chrome · safety always free.
