# V1 Product Spec — Lancer

> **Status:** locked for V1 implementation  
> **Source:** Codex UX research session 019f1906 + ChatGPT synthesis 2026-06-30  
> **Do not implement UI until this doc and its siblings are reviewed.**

---

## What Lancer Is (V1)

An iPhone app that lets a developer supervise coding agents running on their own Mac, server, or VPS. The phone steers and approves; it is not a phone IDE.

Core V1 flow: **pair a machine → see what needs attention → review context and approve/deny/reply → watch the result in a work thread.**

---

## Navigation Roots (4)

The sidebar has exactly four primary destinations. No tab bar.

| Root | `SidebarDestination` | Existing File | Purpose | Primary Action |
|---|---|---|---|---|
| **Home** | `.home` | `LancerHomeView.swift` | Attention items + active work summary | "Ask agent to…" composer |
| **Work** | `.thread(id:)` | `SessionView.swift` | Running and recent Work Threads — list of threads; tapping one opens the Work Thread detail surface for that run | Reply / steer composer |
| **Machines** | `.machines` | `FleetView.swift` | Paired machines, status, pair another | "Pair a machine" |
| **Settings** | `.settings` | `SettingsView.swift` | Notifications, security, governance, account, diagnostics | — |

### Sidebar order

```
[machine status chip]
Home
─ [attention badge if pending]
Work
Machines
Settings
─────────────────
[recent threads list]
```

---

## Contextual Flows (not roots)

These open from within a root, from a push notification, or from first-run. They are NOT sidebar items.

### Pair Machine
- **Entry points:** first-run (no machines paired), Machines → "Pair a machine", Settings → "Add machine"
- **Flow:** Enter Setup Code → Verify Machine (confirm machine name + short trust code) → Connected (Send Test Approval / Skip) → Enable Notifications
- **Code-only.** No QR scanner, no camera permission in this flow. Both Mac and VPS use the same typed code.
- **Pairing code security model:** The setup code is a **short-lived, single-use rendezvous identifier** — it is NOT a permanent credential or secret. The code is displayed by `lancerd pair`, expires in 5–10 minutes, is redeemable once, and is rate-limited at the relay. Redeeming the code begins a key-exchange handshake: the phone and daemon exchange public keys, the user confirms the machine name and a short trust fingerprint, and the relay mints per-device revocable scoped credentials. Those credentials — not the code — are the actual trust anchor.
- **Existing base:** `OnboardingPairing.swift`, `BridgePairingView.swift`, `PairingCrypto.swift`, `PairingPayload.swift`

### Approval Review
- **Entry points:** Home attention card tap, Work Thread inline approval card, push notification deep-link
- **Route:** push notification → `SidebarDestination.needsAttention` (deep-link only; not a sidebar item) → opens Approval Review directly
- **Flow:** context summary → evidence (command / patch / files) → risk acknowledgement for high/critical → Approve / Deny / Reply with question
- **Existing base:** `DSReviewSheet.swift`, `InboxApprovalDetail.swift`, `DSApprovalBanner.swift`

### Diff Review
- **Entry points:** Approval Review "View diff" button, Work Thread "Review changes" button
- **Flow:** file summary list (impact annotated) → file detail (unified diff, Diff/Original/New toggle) → "Ask about this" → "Mark reviewed"
- **Existing base:** `DiffView.swift` (DiffFeature/)

---

## Screen Specs

### Home

**Purpose:** Answer "what needs me now?" and "what is my agent doing?"

**Layout:**
```
Lancer                    [machine chip] [search]

Needs attention           [See all]
┌──────────────────────────────────────────┐
│ ⚠ Approval needed                  High  │
│ Edit auth flow · Mac Studio              │
│                              [Review]    │
└──────────────────────────────────────────┘

Active
[ Running tests ] fix-login-redirect       2m
[ Needs reply  ] refactor-settings        now

Recent
[ Done ] add-app-lock-copy               1h

[+] Ask agent to…                    [send]
```

**Attention section rules:**
- Show only pending `AttentionItem`s (pending approvals + blocked runs + offline machines with pending work)
- Badge count on sidebar row = `AttentionItem`s pending
- "See all" opens the equivalent of `.needsAttention` as a full-screen list sheet (not a root)
- If nothing pending: hide "Needs attention" header; show "All clear" only when no active sessions either

**Composer:**
- Always visible at bottom (matches ChatGPT → ChatInputBar pattern)
- Left: machine/thread context chip (tap to change target)
- Center: "Ask agent to…" placeholder
- Right: send button

**States:**
- Loading → skeleton rows
- Empty (no machines) → onboarding card, "Pair a machine"
- All clear (no attention, no active) → quiet empty composer
- Attention pending → attention section pinned above active
- Offline → cached attention/active rows, offline badge on machine chip
- Error → retry banner with last-updated timestamp

---

### Work (Work Thread)

**Purpose (Work root):** List of running and recent Work Threads. An empty Work root shows a "Start Work" composer. The Work root is a thread browser/picker — not itself a thread.

**Purpose (Work Thread detail):** One surface for a single agent run — start, watch, steer, stop, continue. Opened by tapping a thread in the Work root or via a deep-link.

User-facing name: **Work Thread** (detail). Internal/backend: "session" / "run". Do not show `sessionID` or `runId` in the UI.

**Layout:**
```
Fix login redirect bug              [Running] [Stop]

lancer-ios · Mac Studio
Branch: fix/oauth-redirect · 2 min ago

Current step
Running tests after editing AuthView.swift

Changes                   [Review diff]
3 files changed
1 approval needed         [Review]

Activity
Agent: Found redirect loop in OAuth callback
Agent: Edited AuthView.swift
Agent: Running tests…
You: Also check the logout path

[+] Reply or steer agent…              [send]
```

**Rules:**
- Composer always visible; placeholder changes by state ("Reply…" / "Ask a follow-up…" / "Start a new task…")
- Stop is separated from approve/reply — uses destructive styling
- Approval cards are inline summaries; the full Approval Review opens as a push/sheet
- Diffs, logs, artifacts open as sheets — never the default view
- Completed threads keep same layout; composer becomes "Ask a follow-up…"
- Observed/bareMirror sessions (not started by Lancer): read-only transcript, no composer until "Take Control" is tapped AND adapter guarantees reliable control

**States:**
- Running → live current step, Stop available
- Waiting for user → approval/question card pinned at top, composer focused
- Blocked/error → plain explanation, reply/retry/stop
- Completed → activity log, follow-up composer
- External/observed → read-only transcript, "Take Control" shown when adapter confirms reliability
- Offline (machine dropped mid-run) → last known state frozen, reconnect prompt

---

### Approval Review

**Purpose:** Show enough context for a confident, deliberate decision. Never allow high-risk approval without reading evidence.

**Risk tiers:**

| Tier | `Approval.Risk` | Actions available |
|---|---|---|
| Low | `.low` | Approve button enabled immediately |
| Medium | `.medium` | Must expand the evidence section (files/command shown) before Approve enables |
| High | `.high` | Must open and mark Diff Review reviewed before Approve enables |
| Critical | `.critical` | High requirements + biometric authentication before Approve enables |

**Biometrics scope:** Biometric authentication (`LAContext.evaluatePolicy`) is a local pre-flight confirmation only. It does not enforce the approval at the security boundary. The daemon (`lancerd`) is the authoritative policy-enforcement point — it validates and logs the decision server-side regardless of what the phone does. Biometric failure must prevent the Approve action from firing locally, but the daemon never trusts the phone's biometric outcome.

**Layout:**
```
Approve agent action?            ⚠ High risk

Agent wants to:
Run migration and edit auth callback files

Why it matters
Changes login behavior and runs a database command.

Requested by
lancer-ios · Mac Studio · fix/oauth-redirect

Evidence  (expand required for medium+)
Files changed        3      [View diff →]
Command              npm run migrate
Tests                Not run yet
Risk                 Auth + database

Agent context
"I found the redirect loop and need to update…"

Expiry      4 min remaining

[Reply with question]
[Deny]
[Approve ▸]          ← disabled until evidence reviewed (medium+)
```

**Safety rules:**
- `Deny` and `Reply` always enabled
- `Stop agent` in overflow/danger zone, never adjacent to `Approve`
- High-risk approvals never one-tap from Home card or push notification
- Expired approvals show read-only history; no action buttons

---

### Diff Review

**Purpose:** File-level evidence inspection before an approval decision.

**Default view (file list):**
```
Review changes

3 files changed   +42 −18

AuthView.swift       +21 −8   ⚠ High impact
SessionStore.swift   +12 −3
README.md            +9 −7

Risk notes
- Changes login redirect behavior
- Touches session persistence

[Review required files]
```

**File view:**
```
AuthView.swift              [Diff | Original | New]

@@ handleOAuthCallback
- redirect(to: previousURL)
+ redirect(to: validatedReturnURL)

Agent note
"Prevents redirecting to stale OAuth callback URL."

[Ask about this]  [Mark reviewed ✓]
```

**Rules:**
- High-impact files must be opened and marked reviewed before returning to Approval Review unlocks Approve
- Default to unified diff, never side-by-side on phone
- Collapse unchanged context aggressively (3-line window)
- Full file view: segmented Diff/Original/New toggle
- "Ask about this" sends a reply in the parent Work Thread

---

### Machines

**Purpose:** Paired machines, per-machine status, pair another machine, emergency stop.

**Layout:**
```
Machines                        [Pair machine +]

Mac Studio                      ● Connected
fix-login-redirect · running
refactor-settings · idle

hetzner-vps-1                   ● Relay
No active agents

[Pair another machine]
```

**Rules:**
- Network/relay details hidden by default (LAN, WebSocket, Tailscale not shown to users)
- Machine name + connection status is all that surfaces normally
- Tap machine → Machine Detail (per-machine: active runs, last seen, revoke/remove, pair another)
- Emergency Stop in Machine Detail danger zone — stops all agent runs on that machine

---

### Settings

**Purpose:** Notifications, security, governance, account, diagnostics.

**Sections:**
- Notifications (alert preferences, push relay status)
- Security (app lock / biometrics, device management, SSH keys, TOFU host keys)
- Governance (policy presets, policy editor, audit log, drift report, team roles) ← was its own root, now a section
- Account (sign in / sign out, recovery, multiple devices)
- Advanced (appearance, provider API keys, diagnostics / DoctorView, sync status)
- About / Legal

---

## Exact Terminology

| Internal / old term | V1 user-facing term |
|---|---|
| Session | Work Thread (surface); "run" in activity copy |
| Inbox / Approval Inbox | Needs Attention (section on Home) |
| Fleet | Machines |
| Host | Machine |
| lancerd pair | "Run lancer pair on your machine" |
| Agent source | Hidden (not shown to user) |
| Relay | Hidden (implementation detail) |
| sessionID / runId | Hidden (never shown) |
| bareMirror | "Observed" (shown only in thread header) |
| approvedAlways | "Auto-approve similar" (only after deliberate low-risk approval) |

---

## `AttentionItem` Definition

This type does not exist yet and must be created. It is a view-layer aggregation over existing models — a computed projection, NOT a store. Do not persist it; recompute on every relevant state change.

```swift
enum AttentionKind: Sendable {
    case approval(Approval)                           // Approval.decision == nil
    case blockedRun(hostID: HostID, hostName: String, runID: String, title: String)  // waiting for input
    case offlineMachine(hostID: HostID, hostName: String)  // offline AND has pending/active work
}

struct AttentionItem: Identifiable, Sendable {
    let id: String            // stable, unique; see identity rules below
    let kind: AttentionKind
    let severity: Approval.Risk   // for sorting; .critical > .high > .medium > .low
    let createdAt: Date
    var isExpired: Bool
}
```

**Stable identity rules (critical — UI must not flash on re-projection):**
- `case approval`: `id = approval.id.uuidString` — the ApprovalID UUID is already globally stable.
- `case blockedRun`: `id = "run-\(runID)"` — stable for the lifetime of the run.
- `case offlineMachine`: `id = "offline-\(hostID)"` — stable for the pairing.

**Deduplication:** A new projection that emits an item with the same `id` replaces the previous item silently. The consumer (SwiftUI list) diffes by `id`; no manual dedup needed as long as IDs are stable.

**Priority sorting:** `.critical` → `.high` → `.medium` → `.low`; tie-break by `createdAt` ascending (oldest first within a severity band). Implement as `Comparable` on `Approval.Risk` already defined in LancerCore.

**Removal conditions:**
- `case approval`: Remove when `approval.decision != nil` AND `approval.decision != .expired`. Expired approvals remain as read-only items (`isExpired = true`).
- `case blockedRun`: Remove when `AgentStatusSnapshot.status` is no longer `.waitingForInput`.
- `case offlineMachine`: Remove when `connectionState != .offline` OR all pending approvals for that slot are resolved.

**Expiry handling:** When `approval.decision == .expired`, keep the item in the list with `isExpired = true`. Show a faded card with no action buttons; the only action is "Return to thread." Do not remove expired items immediately — they give the user context on what the agent did after timeout.

**Remote resolution while review is open:** If the daemon resolves an approval while the Approval Review sheet is open (i.e., `approval.decision` changes from `nil` to a value via the `ApprovalRepository` live stream), the sheet must switch to read-only mode immediately. Do not allow the user to submit a second decision. Show: "This approval was already resolved — [Approved/Denied] at [time]."

**Offline machine condition:** An offline machine only generates an `AttentionItem` when it has pending or active work that a human must unblock. A machine that is offline with no pending approvals and no blocked runs is shown in Machines view but does NOT appear in the Needs Attention section.

**Source of truth for population:**
- `case approval` → `FleetStore.Slot.inboxVM.approvals` where `approval.isPending || approval.decision == .expired`
- `case blockedRun` → `FleetStore.Slot.bridgeStatus.status == .waitingForInput`
- `case offlineMachine` → `FleetStore.Slot` where `connectionState(for:) == .offline` AND `inboxVM.approvals.contains(where: \.isPending)`

Do not duplicate the underlying models. `AttentionItem` is a projection, not a store.

---

## Deferred from V1

- Governance as a sidebar root
- Audit chain verification / export (AuditVerifyExportView)
- Advanced policy builder (PolicyEditorView) — keep presets (PolicyPresetsView)
- Apple Watch integration (WatchApprovalTransfer)
- Full-screen terminal (LiveTerminalView visible only via Work Thread → Logs drawer)
- Port forward view (PortForwardView)
- Diff side-by-side layout
- Session history browse / ChatArchiveView as primary surface
- Billing / PaywallSheet (structure only, no commerce)
- Hosted agent provisioning (ProvisioningWizard, SelfHostVsHostedView)
- CI / git webhook events
- Multi-machine emergency stop from Home
- Search (UI only deferred; keep backend search in `SidebarShellState`)
- QR scanner in pairing flow (QRScannerView stays in codebase, removed from onboarding entry)
