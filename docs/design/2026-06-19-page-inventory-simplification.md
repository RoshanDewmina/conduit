# Conduit — Page Inventory & Simplification Notes

> Design-handoff brief for a UI/UX refresh pass. Conduit is a sidebar/drawer shell
> (no tab bar): a slide-over drawer on iPhone, `NavigationSplitView` on iPad, with
> `SidebarDestination` as the single routing enum. This document inventories each
> page, what it does, and one concrete simplification opportunity per page.
>
> Author: Claude (Opus) · 2026-06-19 · grounded in the `codex/ios27-shell-workspace` branch.

---

## 1. Sidebar / Drawer (`ConduitSidebarView.swift`)

**Purpose:** Navigation layer — the only way to move between destinations, and the ambient status surface (pending-approval badge, fleet slot count).

**Key elements:** Pixel-avatar profile header (taps to Settings), "New chat" CTA, inline search field (live-queries `ChatConversationRepository`), a grouped nav card with four rows (Needs Attention, Governance, Fleet, Settings), and a scrollable Recent Threads list that doubles as search results when a query is active.

**Simplify:** The profile header already navigates to Settings, and Settings is *also* a nav row in the primary card — two taps to the same place. Remove the gear from the profile header, or collapse Settings into the header tap alone.

---

## 2. New Chat Home (`NewChatTabView.swift`)

**Purpose:** Primary dispatch surface — compose a prompt, pick an agent, send work to a connected host; also renders the active conversation inline and shows the sessions list when idle.

**Key elements:** Three states in one view: (a) idle → embedded `SessionsListView` + floating "+" FAB; (b) compose → bottom sheet with `TextEditor`, agent/host pills, collapsible Options (model, budget cap), Send; (c) active run → chat scroll with user bubbles + streamed output and a `RunFollowUpBar`/`RunControlBar` bottom bar.

**Simplify:** The idle state embeds the full `SessionsListView`, while the sidebar's "Sessions" destination renders the *same* list standalone — the list appears in two places. Keep the sessions panel only in the Sessions destination; the New Chat idle state needs only the agent list + FAB.

---

## 3. Sessions List (`SessionsListView.swift`)

**Purpose:** Inventory of all persisted chat conversations with live connection state, status filtering, and a shortcut to conversations waiting for input.

**Key elements:** Large editorial header ("What should your agents do next?") with three summary pills (Chats / Waiting / Done), a horizontal filter bar (All / Needs input / Ready for review), and conversation cards (icon, title, host, relative time, plus a warm "Needs your approval" band when blocked).

**Simplify:** The header's second line ("Start a chat, resume recent work, or jump into anything waiting…") restates what the filter pills already say. Trim to title + pills; the copy adds height without aiding navigation.

---

## 4. Needs Attention / Inbox (`InboxFeature/InboxView.swift`)

**Purpose:** Surface pending agent approval requests for Approve/Reject; when empty, a light dashboard of today's handled count + a link to history.

**Key elements:** Title header with history button; a `LazyVStack` of `InboxApprovalCard`s (agent, tool, risk, quick Approve/Deny). Tapping opens a detail sheet (full context + "Allow always" + diff for patch approvals). An edit sheet lets the user mutate tool-input JSON before approving. Empty state = "You're all caught up" + two stat tiles + history nav row.

**Simplify:** One list row can spawn three modal layers (detail sheet → edit sheet → "Allow always" scope sheet). Merge the "edit & run" path into the detail sheet as an expand-in-place editor to remove one modal level.

---

## 5. Governance (`AppFeature/GovernanceView.swift`)

**Purpose:** Read-only proof surface — confirm the policy bridge is connected and rules enforcing; route into Settings (edit) or Inbox (decide).

**Key elements:** Connection status card (shield, live/offline), "Provider coverage" section listing Claude Code / Codex / OpenCode / Kimi as four static rows, a "Policy" section with nav rows to Settings + Inbox, and "Latest enforcement" showing the most recent audit entry.

**Simplify:** The four provider rows are static ("Policy capable" / "Connect to verify") and carry no interactive value — four rows of weight that the connection card already implies. Replace with a compact "N agents covered" line inside the connection card, or drop the section until per-provider policy divergence is real.

---

## 6. Fleet (`AppFeature/FleetView.swift`)

**Purpose:** Manage connected SSH hosts; monitor live agent status, running loops, and usage per slot; reconnect or add hosts.

**Key elements:** Header with host count + "+" add-host; contextual banners (local-agent warning, pending-approval nudge); an active-loops section (→ `LoopDetailView`); a per-host slot section (status dot, relay badge, health badge, inline terminal chip, per-agent rows); a "Saved hosts" reconnect list; a "Usage & limits" (`QuotaGuardView`) entry.

**Simplify:** The pending-approval banner here and the "Needs Attention" sidebar badge surface the same signal in two contexts — and the banner doesn't even open Inbox directly (the sidebar row does). Remove the Fleet banner; it duplicates urgency without routing clarity.

---

## 7. Settings (`SettingsFeature/SettingsView.swift`)

**Purpose:** Device-level configuration — keys, appearance, relay pairing, data access, app reset.

**Top-level sub-screens (4 sections):** GENERAL → Notifications, Appearance, Security & Privacy (`TrustPrivacyView`), Provider Keys; POLICY & HOSTS → Relay Pairing (`E2ERelayPairingView`), Health Check (`DoctorView`); DATA → Audit & Proof, Secrets (shown only with a repo / daemon channel); DANGER ZONE → Reset App.

**Simplify:** "Policy & Hosts" holds only Relay Pairing + Health Check with no actual policy rows (policy editing lives via Governance → Settings link), leaving a thin two-row section. Merge those into General, or rename to a clear "Connection" section.

---

## 8. Session / Chat Thread + Workspace Launcher (`SessionFeature`, `AppFeature/SessionWorkspaceContainer.swift`)

**Purpose:** Live SSH block-terminal session (Warp-style PTY blocks via `SessionView`) plus a launcher sheet for supplementary workspace tools (files, browser preview, diff review, environment info).

**Key elements:** `SessionWorkspaceContainer` wraps `SessionView` and presents a `WorkspaceLauncherView` bottom sheet (`.height(356)`) on the workspace button; the launcher offers terminal / environment / review / browser / files, each opening as another `DSReviewSheet` at medium/large detent. `SessionView` renders the full block transcript (`ChatTranscriptView`/`ToolCardView`) over the SSH PTY.

**Simplify:** Every launcher destination opens a *second* sheet on top of the launcher (single `@State route` can't hold two sheets). A tab-within-sheet, or one adaptive sheet that swaps content on selection, removes the two-tap / double-modal overhead.

---

## 9. Onboarding / Connect (`OnboardingFeature`)

**Purpose:** First-run three-step flow: value prop → bridge pairing (QR or 6-digit code via `E2ERelayClient`) → default policy level; exits to Fleet on completion, or skips to New Chat for returning users.

**Key elements:** `OnboardingRedesignView` drives a step counter (0–2) with a shared header (back chevron + step dots + skip), a scrollable block per step, and a sticky footer CTA. Step 1 live-drives the relay client + QR; step 2 presents `OnboardingCautionLevel` tiers. A `ProvisioningWizard` sheet handles SSH host add-and-connect as an alternate path.

**Simplify:** The "already use Conduit" path lands on Fleet but is only a faint header text link shared across steps — a reinstalling user must walk all three steps unless they notice it. Promote "I've already set up Conduit" to a dedicated first-screen button.

---

## Cross-cutting themes for the refresh

- **De-duplicate signals:** the sessions list (New Chat ↔ Sessions), Settings (sidebar header ↔ nav row), and pending approvals (Fleet banner ↔ sidebar badge) each appear in two places. Pick one home for each.
- **Flatten modals:** Inbox and the Workspace launcher both stack sheets-on-sheets. Prefer expand-in-place or adaptive single sheets.
- **Earn every section:** Governance's static provider rows and Settings' thin "Policy & Hosts" section add height without information. Collapse to summary lines until the underlying data is per-item distinct.
- **Type/identity:** display headlines now use Instrument Sans bold (the prior Playwrite script face was removed); the refresh should settle the final display treatment intentionally rather than inherit this interim choice.
