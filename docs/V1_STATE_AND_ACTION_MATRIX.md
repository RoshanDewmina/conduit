# V1 State and Action Matrix — Lancer

> **Status:** locked for V1 implementation  
> **Companion:** V1_PRODUCT_SPEC.md, V1_IMPLEMENTATION_PLAN.md  
> **Critical:** Lancer's largest current defect is contradictory state — not missing UI.  
> Every visible status must have exactly one authoritative source listed here.

---

## Entities

1. `AttentionItem` (view-layer projection)
2. `Approval` (LancerCore/Approval.swift)
3. `Run` / agent run (AgentStatusSnapshot + RunOutputStore.Run)
4. `MachineStatus` (Session.ConnectionState derived from FleetStore.Slot)
5. `ReplyDelivery` (ApprovalActionIntent + relay ACK)

---

## 1. AttentionItem

**Source of truth:** computed projection over `FleetStore.slots[*].inboxVM.approvals` and per-slot `connectionState(for:)` + `bridgeStatus`. This is a view-layer projection — NOT persisted, NOT a separate store.  
**Displayed on:** Home "Needs Attention" section, sidebar badge count

| State | Display | Available Actions | Notes |
|---|---|---|---|
| **pending** | Attention card with risk badge | Review (opens Approval Review), Stop | Default |
| **expired** | Faded card, "Expired" label | Return to thread | `isExpired == true`; no decision actions |
| **resolved** | Not shown | — | Remove when `approval.decision != nil && decision != .expired` |
| **offline-machine** | "Machine offline" card | Retry connection, Dismiss | Only when the offline machine has pending or active blocked work |
| **remotely-resolved-while-open** | Sheet switches to read-only | Return to thread | `approval.decision` set externally while sheet open — no second decision allowed |

**Stable identity:** `approval.id.uuidString` / `"run-<runID>"` / `"offline-<hostID>"`. Recomputing the projection must not change IDs — SwiftUI diffs by `id`.

**Deduplication:** same `id` = same item. The projection replaces the old value in-place; no manual dedup needed.

**Sorting:** `.critical` → `.high` → `.medium` → `.low`; tie-break by `createdAt` ascending.

**Removal conditions:**
- Approval resolved (decision != nil, not expired): remove.
- Approval expired: keep as read-only item with `isExpired = true`.
- Blocked run unblocked: remove the `blockedRun` item.
- Offline machine reconnects OR no pending work remains: remove the `offlineMachine` item.

**Offline-machine condition:** An offline machine only appears here when it has pending approvals or blocked runs. A machine that is simply offline with no pending work is visible in Machines view only.

---

## 2. Approval

**Source of truth:** `ApprovalRepository` (persistent) + `ApprovalIngest` (live stream)  
**Displayed on:** Home attention cards, Work Thread inline, Approval Review screen

| State | `decision` value | Display | Available Actions |
|---|---|---|---|
| **pending** | `nil` | Full Approval Review | Approve, Deny, Reply with question, Stop agent |
| **approved** | `.approved` | "Approved ✓" label + timestamp | Return to thread |
| **auto-approved** | `.approvedAlways` | "Auto-approved" label | Return to thread, Review policy |
| **denied** | `.rejected` | "Denied" label + timestamp | Return to thread |
| **expired** | `.expired` | "Expired — not actioned" | Return to thread |

### Approval.Kind → default risk inference (UI display hint)

| Kind | Risk floor |
|---|---|
| `.askQuestion` | `.low` |
| `.patch`, `.fileWrite` | `.medium` |
| `.command`, `.network`, `.browser` | `.high` |
| `.fileDelete`, `.credential`, `.callMCP` | `.high` |

Actual `Approval.Risk` from daemon overrides the floor. UI always uses `approval.risk`.

### Approval Review — gate rules

| `risk` | Gate before Approve enables |
|---|---|
| `.low` | None — Approve available immediately |
| `.medium` | Evidence section must be expanded (files/command visible) |
| `.high` | Diff Review must be opened and at least one high-impact file marked reviewed |
| `.critical` | Same as high + biometric authentication (`LAContext.evaluatePolicy`) |

---

## 3. Run / Agent Run

**Source of truth:** `AgentStatusSnapshot` (from daemon `agent.status` event via `FleetStore.Slot.bridgeStatus`)  
**Status field:** `AgentStatusSnapshot.status` — values from `AgentStatusProtocol.swift`  
**Displayed on:** Home active-runs section, Work Thread header

| `status` | User-facing label | Color | Available Actions |
|---|---|---|---|
| `.working` | "Running" | green `.ok` | Stop, Reply |
| `.waitingForInput` | "Needs input" | amber `.warn` | Reply (focused composer), Stop |
| `.recentlyActive` | "Recently active" | accent `.accent` | Continue, Stop |
| `.idle` | "Idle" | grey `.off` | Start new task |
| `.completed` | "Done" | grey `.off` | View history, Ask follow-up |

**Run error state** (`RunOutputStore.Run.status == "failed"` / `isTerminal == true`):
- Display: "Failed" label with inline reason
- Actions: Retry (re-dispatch with same prompt), Reply to debug, View logs

**External/observed run** (`Session.SessionOrigin == .bareMirror`):
- Display: "Observed" badge in thread header; read-only transcript
- Actions: None until "Take Control" tapped
- "Take Control" enabled only when adapter confirms reliable control (verified via daemon capability flag)

---

## 4. MachineStatus

**Source of truth:** `Session.ConnectionState.derive(session:relay:)` (LancerCore/Session.swift)  
**Inputs:** `FleetStore.Slot.sessionViewModel.session.status` + `FleetStore.Slot.relayState`  
**Displayed on:** Home machine chip, Machines root, Work Thread machine label, Approval Review banner, AttentionItem cards

**Canonical projection — one consumer:** ALL views that need a machine status MUST read it via `FleetStore.connectionState(for: slot)`. No view or ViewModel is permitted to derive machine status independently from raw relay/session state. If `connectionState(for:)` does not return what a view needs, fix that function — do not shadow it with a second derivation.

| `ConnectionState` | User-facing label | Icon/Color | Available Actions |
|---|---|---|---|
| `.connected` | "Connected" | ● green | Disconnect, Emergency Stop |
| `.relayPaired` | "Relay" | ⟳ accent | — (relay is working) |
| `.connecting` | "Connecting…" | spinner | Cancel |
| `.offline` | "Offline · last seen [time]" | ● grey | Retry, Diagnose |
| `.failed` | "Unreachable" | ● red | Retry, Diagnose, Check settings |

**Machine-offline-during-approval** (fixture case 7):
- `ConnectionState` transitions to `.offline` while Approval Review is open
- Display: banner in Approval Review: "Machine offline — decision will be sent when reconnected"
- Actions: Keep reviewing, Cancel review (returns to Home/Work Thread)
- The approval decision is queued locally and sent when the connection restores

---

## 5. ReplyDelivery

**Source of truth:** `ApprovalActionIntent` + relay ACK from `ApprovalRelay`  
**Displayed on:** Work Thread activity log, Approval Review post-decision

This type does not exist explicitly — must be inferred from ApprovalActionIntent + relay state. Define as:

```swift
enum ReplyDeliveryStatus: Sendable {
    case sending
    case delivered
    case failed(reason: String)
    case expiredBeforeDelivery  // approval expired while reply was in-flight
}
```

| State | Display in Activity | Available Actions |
|---|---|---|
| `.sending` | "Sending…" inline indicator | — |
| `.delivered` | "Sent ✓" with timestamp | — |
| `.failed(reason)` | "Failed to deliver — [reason]" | Retry, Dismiss |
| `.expiredBeforeDelivery` | "Approval expired before reply was sent" | Return to thread |

---

## Fixture Cases

These 7 cases must be demonstrable with a test/preview fixture before implementation is claimed done. Each maps to the state matrix above.

### Fixture 1: Medium approval (standard file edit)

```
Approval.kind     = .patch
Approval.risk     = .medium
Approval.command  = nil
Approval.patch    = "diff --git a/AuthView.swift ..."
decision          = nil
```

Expected UX:
- Home: attention card "Approval needed · Medium risk · [Review]"
- Approval Review: Evidence section collapsed initially; Approve button greyed until expanded
- After expand: Approve button enables
- After approve: decision = .approved; Work Thread shows "Approved ✓"

---

### Fixture 2: Critical approval (auth + database migration) — requires biometrics

```
Approval.kind     = .command
Approval.risk     = .critical
Approval.command  = "npm run migrate && rm -rf node_modules/.cache"
Approval.patch    = "diff --git a/auth/callback.ts ..."
decision          = nil
```

Expected UX:
- Approval Review: "Critical risk" banner
- Must open Diff Review and mark high-impact file reviewed
- Then "Authenticate to approve" triggers Face ID / Touch ID
- `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...)`
- On auth success: Approve action fires; on failure: Approve stays disabled

---

### Fixture 3: Agent question (clarification needed, no file change)

```
Approval.kind     = .askQuestion
Approval.risk     = .low
Approval.question = "Should I use async/await or completion handlers for the new API?"
Approval.choices  = ["async/await", "Completion handlers", "Ask me later"]
decision          = nil
```

Expected UX:
- Home: "Agent question" attention card
- Approval Review shows question text + choice picker
- User taps a choice → `answeredChoice` set, `decision = .approved`
- No diff/evidence gate required (risk = .low)

---

### Fixture 4: Already-handled request (opened from history)

```
Approval.risk     = .medium
decision          = .approved
decidedAt         = Date().addingTimeInterval(-300) // 5 min ago
```

Expected UX:
- Approval Review opens in read-only history mode
- "Approved · 5 minutes ago" label
- No action buttons (Approve/Deny/Reply all hidden)
- "Return to thread" is the only action

---

### Fixture 5: Expired request

```
Approval.risk     = .high
decision          = .expired
decidedAt         = Date().addingTimeInterval(-60)
```

Expected UX:
- Home attention card shows "Expired" label (faded, no action button)
- Approval Review shows "This approval request expired before it was actioned"
- "Return to thread" is the only action
- Work Thread shows "Approval expired — agent may have taken a default action"

---

### Fixture 6: Reply delivery failure

```
Approval.kind    = .askQuestion
Approval.risk    = .low
decision         = .approved (user replied)
ReplyDeliveryStatus = .failed(reason: "Relay connection lost")
```

Expected UX:
- Work Thread activity: "Failed to deliver — Relay connection lost" with [Retry] inline
- Retry re-attempts via `ApprovalActionIntent` with idempotency key
- On retry success: "Sent ✓" replaces failure state
- Max 3 automatic retries; after that, manual Retry only

---

### Fixture 7: Machine disconnect during Approval Review

```
ConnectionState was .connected
ConnectionState transitions to .offline mid-review
Approval.risk    = .high
decision         = nil
```

Expected UX:
- Approval Review shows banner: "Machine offline — your decision will be sent when reconnected"
- Review can still be completed (evidence is already loaded)
- Approve/Deny buttons remain enabled
- Decision is queued in `ApprovalActionIntent` with offline flag
- When `ConnectionState` returns to `.connected` or `.relayPaired`: decision fires automatically
- Work Thread shows "Approval sent after reconnect ✓"

---

## Cross-Cutting Rules

1. **One source of truth per status.** If two stores both emit a status for the same entity, the tie-break rule is: daemon event wins over local cache; `ConnectionState.derive()` wins over raw relay state. Never display both.

2. **Expired state is final.** Once `decision == .expired`, never allow re-action. Show history only.

3. **Delivery semantics: at-least-once with idempotency.** The phone delivers decisions using at-least-once delivery — a decision may be sent more than once (retries, reconnect flush, redundant dispatch). Every `ApprovalActionIntent` carry a stable idempotency key (the `approvalID` UUID string). The daemon processes decisions idempotently: the DB write is guarded on `decision IS NULL`, so duplicate deliveries of the same `approvalID` are no-ops. The user sees exactly one outcome. "Exactly-once delivery" is not a goal; idempotent daemon processing + at-least-once delivery = one visible outcome.

4. **Biometric gate — local confirmation only.** `.critical` approvals require `LAContext.evaluatePolicy` success before the Approve action fires. A biometric failure must not silently fall through to approve. The gate must be synchronous with the Approve tap. IMPORTANT: biometrics is a local UX pre-flight — it is NOT the security enforcement boundary. The daemon (`lancerd`) is the authoritative policy enforcer; it validates and logs the decision server-side and never trusts the phone's claimed biometric outcome. Biometric failure prevents a bad-faith tap from reaching the daemon; it does not substitute for daemon-side policy checks.

5. **Offline queue.** `ReplyDelivery.failed` and machine-offline decisions are queued locally and retried automatically on next reconnect, with a visible "pending send" indicator in the Work Thread.

6. **Read-only external sessions.** `SessionOrigin == .bareMirror` sessions never allow Approve/Deny/Reply/Stop until "Take Control" is confirmed AND the daemon confirms the adapter supports reliable interruption.
