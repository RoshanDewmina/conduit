# Home/Attention Redesign — Proposed Changes & File Plan

Workflow 02 of the 6-part design-audit series. **Approved 2026-07-01 — ready for implementation.**
Full comparison report: `index.html` (this file mirrors sections 4–5 only).

## Owner decisions (resolves all open questions below)

1. Subtitle wrap at large Dynamic Type: if `"<agent> · <tool> · <host> · <age>"` doesn't fit,
   truncate/drop the **host** segment first (lowest-priority info — agent, tool, and age matter
   more for a 2-second glance), then wrap to a second line if still too long. Agent-initial tile
   stays at ≈22×22 as proposed (denser than Inbox's 30×30 — Home caps at 2 cards).
2. All-clear confirmation line: shows **whenever `pendingApprovalCount == 0`**, regardless of
   pairing state (not gated on a machine being paired). Placeholder copy
   ("You're caught up — nothing needs review.") stands — easy to tweak later, not blocking.
3. Attention badge: moves onto **Home's own sidebar row** (`SidebarNavRow(icon: "house", …)`,
   currently `badge: nil` — change to mirror what Inbox's row did:
   `state.pendingApprovalCount > 0 ? "\(state.pendingApprovalCount)" : nil`).
4. Back-navigation from `.needsAttention`: standard system back button, no bespoke "return to
   Home" override — simplest option, matches the "no speculative abstraction" rule.

## 4. Proposed changes (in scope)

### 4.1 Enrich the attention card row anatomy

**Current** (`Packages/LancerKit/Sources/AppFeature/LancerHomeView.swift`,
`approvalAttentionCard`, lines 172–208):

- Header line: risk/expiry icon + title ("Approval needed" / "Approval expired") + risk badge (trailing capsule).
- Subtitle line (`approvalSubtitle`, lines 331–335): `"<tool> · <host>"`.
- Trailing: `Review` / `View` button.
- Missing: agent name, relative age — both of which the just-redesigned Inbox
  `InboxBoardCard` (`Packages/LancerKit/Sources/InboxFeature/InboxView.swift`, lines 794–906)
  already renders (agent-initial tile, agent name, `"<host> · <relative time>"` submeta).

**Proposed row anatomy** (exact fields, in order, top to bottom):

1. Header line (unchanged position) — icon + `"Approval needed"` / `"Approval expired"` … risk
   badge trailing.
2. **New:** small agent-initial tile (≈22×22, one visual step down from Inbox's 30×30 tile —
   Home's card is denser and capped at 2 items) leading the subtitle line.
3. Subtitle line, extended from 2 parts to 3: `"<agent name> · <tool> · <host> · <relative age>"`.
   - Agent name: `approval.agent.displayName` — **already exists** as a private extension in
     `LancerHomeView.swift` (lines 788–808), just not read by `approvalAttentionCard` today.
   - Relative age: `relativeTimeLabel(_:)` — **already exists** in `LancerHomeView.swift`
     (lines 337–342), currently only called from `approvalReviewSheet`, not the card.
   - Agent initial: no direct equivalent on `Approval.AgentSource` yet; `InboxView`'s
     `agentInitial(_:)` mapping (C / Cx / Cu / O / D / A) is `private` to `InboxFeature` — mirror
     the same 6-case switch locally in `AppFeature` rather than cross-module reach-through (both
     are trivial, no new abstraction).
4. Trailing: `Review` / `View` button (unchanged).

No new component is introduced — this reuses helpers that already exist in the file plus a
one-line mirror of an existing mapping. Consistent with the "no dead code / no speculative
abstraction" rule in `AGENTS.md`.

**Resolved:** see "Owner decisions" §1 above — truncate host first, then wrap.

### 4.2 Give "all clear" a real module

**Current:** `homeHeadline` (lines 465–467) returns `"All clear tonight."` when
`pendingApprovalCount == 0`; the machines section below still renders as today — either
`connectMachineCard` (lines 384–411, "Connect a machine" / "Pair a host to dispatch and supervise
agents.") when no machines are paired, or the live `MachineTreeCard` tree when a machine is paired.
Fresh capture (`screenshots/current-all-clear.png`) confirms this is genuinely text-only: headline
+ empty-state card, nothing else.

**Assessment:** the existing `connectMachineCard` already covers the "no machines" case reasonably
well (icon, copy, CTA chevron) — it does not need a rebuild. The gap is specifically when
**all-clear AND a machine is already paired**: today that state (see
`screenshots/current-seeded-machine.png`) is just the headline + machine tree, with zero
acknowledgment that the user is caught up beyond the headline sentence. Per Mobbin references
(Notion / Substack / Threads "all caught up" — section 3), the fix is a **calm confirmation line**,
not a new illustrated empty-state module (owner's Todoist/GitHub "calm, not cartoon" direction from
the original audit still holds).

**Proposed all-clear module** (exact content): a single-line, low-emphasis confirmation row
inserted between the headline and `YOUR MACHINES`, shown whenever
`fleetStore.attentionItems.isEmpty`:
- Icon: small checkmark (`checkmark.circle` or similar, `t.ok` tone, no illustration).
- Copy: `"You're caught up — nothing needs review."` (placeholder wording — **owner should confirm
  exact copy**, see open questions).
- No CTA on this row itself (the machine card/tree below already carries the next action: pair or
  open a machine).

**Resolved:** see "Owner decisions" §2 above — always shows when all-clear; placeholder copy stands.

### 4.3 Fold Inbox into Home

**Current:**
- `LancerSidebarView.primaryNavigation` (`Packages/LancerKit/Sources/AppFeature/LancerSidebarView.swift`,
  lines 185–211) renders three primary rows: Home, **Inbox** (badge = `state.pendingApprovalCount`),
  Machines.
- Home's "See all" button (`attentionSection`, lines 138–158) already exists and calls
  `onOpenInbox()` only when `items.count > 2`.
- `onOpenInbox` is wired in `AppRoot.swift` (line 1466) to
  `sidebarState.navigate(to: .needsAttention)` — the **same** destination the sidebar's Inbox row
  navigates to. `.needsAttention` is a case on `SidebarDestination`
  (`SidebarShellState.swift`, line 10), independent of whether it's exposed as a sidebar row.

**Proposed:**
- Remove the `SidebarNavRow(icon: "sparkles", title: "Inbox", …)` block (lines 194–201) from
  `primaryNavigation`, leaving Home and Machines as the two remaining primary rows (governance is
  already folded into Settings per commit 814c219c, so this leaves a 3-root IA: Home, Machines,
  Settings — not the 4-root IA the original audit doc proposed, since Inbox is no longer a root at all).
- No new navigation wiring needed for "See all" — `onOpenInbox` already pushes `.needsAttention`,
  which already renders the existing `InboxFeature/InboxView.swift` full list. The only change is
  that this destination becomes reachable **only** via Home's "See all", not via a persistent
  sidebar row.
- `InboxView` itself is unchanged — it's already the correct full-list screen.

**Resolved:** see "Owner decisions" §3–4 above — badge moves to Home's sidebar row; standard back
navigation, no bespoke affordance.

## 5. File-level plan

| File | Change |
| --- | --- |
| `Packages/LancerKit/Sources/AppFeature/LancerHomeView.swift` | Rework `approvalAttentionCard` (lines 172–208) to add the agent-initial tile + extend `approvalSubtitle` (lines 331–335) to 3 segments incl. relative age; add a new small all-clear confirmation row view, inserted in `body` (lines 67–93) between `greeting` and `machinesSection` when `fleetStore.attentionItems.isEmpty`; add a local 6-case agent-initial mapping mirroring `InboxView`'s. |
| `Packages/LancerKit/Sources/AppFeature/LancerSidebarView.swift` | Remove the Inbox `SidebarNavRow` from `primaryNavigation` (lines 194–201); change the Home `SidebarNavRow`'s `badge: nil` (line ~190) to `badge: state.pendingApprovalCount > 0 ? "\(state.pendingApprovalCount)" : nil`, mirroring what the Inbox row did. |
| `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` | No functional change expected — `onOpenInbox` (line 1466) already wires "See all" to `.needsAttention`; re-verify after the sidebar row removal that this destination is still reachable and that `sidebarState.pendingApprovalCount`/badge wiring (lines 644–652) still makes sense with Inbox no longer a sidebar row. |
| `Packages/LancerKit/Sources/AppFeature/SidebarShellState.swift` | No change expected — `.needsAttention` stays a valid `SidebarDestination` case, just no longer surfaced as a `SidebarSection` primary row. |
| `Packages/LancerKit/Sources/InboxFeature/InboxView.swift` | No change — already the correct full-list screen; confirm its own back-navigation still makes sense when it's reached only from Home. |

No daemon, push-backend, or agent-runner changes are implied by this pass — this is Home/sidebar UI
only.
