# Lock-screen Approval Journey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the push-driven Live Activity express four distinct states (#2) and wire the post-unlock reveal of full approval detail (#3), so the lock-screen approval journey is legible end to end.

**Architecture:** Add one transient field (`lastDecision`) to the Live Activity `ContentState` (Swift + Go mirror) so a killed-app decision can be confirmed via push. Extract a pure, testable state-precedence resolver that the widget consumes. Wire notification/Live-Activity taps to open the existing un-redacted `InboxApprovalDetail` sheet (warm + cold), and render a real diff for `.patch` approvals. Reuses existing substrate — small by design.

**Tech Stack:** Swift 6 / SwiftUI, ActivityKit, WidgetKit, Swift Testing (`import Testing`), Go (push-backend), SPM (LancerKit, 21 targets).

## Global Constraints

- **V1 transport = the E2E relay + APNs.** No SSH dependency in any of this work.
- **The widget is pure presentation** — every state is computed from `ContentState`; no business logic in `LancerLiveActivityWidget`.
- **Redaction is a push-payload concern only.** In-app surfaces (`InboxApprovalDetail`) show the real command. Never add command text / file contents / secrets to any APNs payload or `ContentState`.
- **Reveal gate = respect app-lock.** No new biometric step for *viewing* a revealed approval. Critical *approve/allow-always* stays biometric-gated (already implemented — do not remove).
- **Date encoding is pinned.** `ContentState` dates encode as Unix fractional-seconds `float64` (Swift `JSONEncoder` default ↔ ActivityKit default decoder). A mismatch silently drops the whole update. New fields must not break this.
- **Verification:** LancerKit/widget changes → `cd Packages/LancerKit && swift build` **and** the XcodeBuildMCP app-target build (`build_sim`, scheme `Lancer`, sim `iPhone 17 Pro`) — plain `swift build` skips `#if os(iOS)` code and hides strict-concurrency breaks. push-backend changes → `cd daemon/push-backend && go test ./...`.
- **Device-only items** (cold-path ✓ on lock screen; cold deep-link) cannot be simulator-verified — implement + unit-test, then flag for owner device QA. Do not claim them verified.
- Commit after each task. Co-author trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## File Structure

- `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift` — `ContentState` (+`lastDecision`), `start(...)`.
- `Packages/LancerKit/Sources/SessionFeature/LiveActivityPresentation.swift` *(new)* — pure state-precedence resolver (testable; no UI, no ActivityKit).
- `Packages/LancerKit/Tests/LancerKitTests/LiveActivityContentStateTests.swift` — extend for `lastDecision` + presentation precedence.
- `daemon/push-backend/liveactivity.go` — Go `ContentState` mirror (+`LastDecision`), `pushLiveActivityDecision(...)`.
- `daemon/push-backend/liveactivity_test.go` — extend for the new field + decision push.
- `LancerLiveActivityWidget/LancerLiveActivityWidget.swift` — consume the resolver; render four-state treatments.
- `Packages/LancerKit/Sources/DesignSystem/Components/InboxApprovalDetail.swift` — add optional patch-diff section.
- `Packages/LancerKit/Sources/InboxFeature/InboxView.swift` — pass patch to detail; honor an "open this approval" deep-link.
- `Packages/LancerKit/Sources/NotificationsKit/Notifications.swift` — add an "open detail" buffer/notification distinct from the action buffer.
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` — drain the open-detail buffer; route to Inbox. **Hot file / owner may be live-editing — see Task 6 collision note.**

## Task Dependency Graph (for parallel dispatch)

```
T1 (lastDecision field) ──┬─► T2 (resolver) ──► T4 (widget)
                          └─► T3 (backend push)
T7 (patch diff) ───────────────────────────────── independent
T5 (warm deep-link) ──► T6 (cold deep-link + AppRoot)
```
- **T1 must land first** (T2/T3/T4 consume the field).
- **T2 ∥ T3** after T1 (different files: SessionFeature vs push-backend).
- **T4** after T2 (widget consumes the resolver).
- **T5 → T6** sequential (both touch deep-link routing; T6 touches AppRoot).
- **T7** fully independent (InboxApprovalDetail + InboxView detail-call only).

---

### Task 1: Add `lastDecision` transient to ContentState (Swift + Go mirror)

**Files:**
- Modify: `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift:32-58` (ContentState struct + init)
- Modify: `daemon/push-backend/liveactivity.go:78-88` (Go mirror struct)
- Test: `Packages/LancerKit/Tests/LancerKitTests/LiveActivityContentStateTests.swift`
- Test: `daemon/push-backend/liveactivity_test.go`

**Interfaces:**
- Produces (Swift): `ContentState.lastDecision: String?` — `"approved"` / `"rejected"` / `nil`. Added to the memberwise `init` with default `nil` (so existing call sites and Task-3 backend stay compatible).
- Produces (Go): `liveActivityContentState.LastDecision *string` with json tag `lastDecision,omitempty`.

- [ ] **Step 1: Write the failing Swift test** — append to `LiveActivityContentStateTests.swift` (uses `import Testing`):

```swift
@Test func lastDecisionRoundTripsAndDefaultsNil() throws {
    // Default is nil and omitted-friendly.
    let running = LancerSessionAttributes.ContentState(status: "connected", isStreaming: true)
    #expect(running.lastDecision == nil)

    // Set + round-trip through JSON (the wire format ActivityKit uses).
    let landed = LancerSessionAttributes.ContentState(
        status: "connected", pendingApprovals: 0, lastDecision: "approved"
    )
    let data = try JSONEncoder().encode(landed)
    let back = try JSONDecoder().decode(LancerSessionAttributes.ContentState.self, from: data)
    #expect(back.lastDecision == "approved")
}
```

- [ ] **Step 2: Run it, verify it fails to compile** — `lastDecision` does not exist yet.

Run: `cd Packages/LancerKit && swift build 2>&1 | grep -i "lastDecision\|error" | head`
Expected: a compile error referencing `lastDecision`.

- [ ] **Step 3: Add the field + init param** in `LiveActivityManager.swift`. In the `ContentState` struct (after `public var lastUpdate: Date`) add:

```swift
        /// Transient confirmation of a just-resolved decision: "approved" / "rejected" / nil.
        /// Pushed once by push-backend after a decision resolves (incl. the cold path), shown
        /// as a ✓ for ~4s, then cleared. nil in steady state.
        public var lastDecision: String?
```

In the memberwise `init(...)`, add the parameter **before** `lastUpdate` (keep `lastUpdate` last) and assign it. The init becomes:

```swift
        public init(
            status: String,
            pendingApprovals: Int = 0,
            agentName: String? = nil,
            pendingApprovalID: String? = nil,
            isStreaming: Bool = false,
            cost: Double? = nil,
            lastDecision: String? = nil,
            lastUpdate: Date = .now
        ) {
            self.status = status
            self.pendingApprovals = pendingApprovals
            self.agentName = agentName
            self.pendingApprovalID = pendingApprovalID
            self.isStreaming = isStreaming
            self.cost = cost
            self.lastDecision = lastDecision
            self.lastUpdate = lastUpdate
        }
```

- [ ] **Step 4: Run the Swift test target** (app-target — these tests are `#if os(iOS)`):

Run: `cd Packages/LancerKit && swift build`
Expected: `Build complete!` (the test compiles; runtime is exercised in the app-target test in later verification).

- [ ] **Step 5: Add the Go mirror field** in `liveactivity.go`, inside `liveActivityContentState` (after the `Cost` field, before `LastUpdate`):

```go
	// LastDecision is a transient confirmation pushed once after a decision
	// resolves ("approved"/"rejected"); omitted in steady state. Mirrors the
	// Swift ContentState.lastDecision optional.
	LastDecision *string `json:"lastDecision,omitempty"`
```

- [ ] **Step 6: Write the Go test** — append to `liveactivity_test.go`:

```go
func TestContentStateLastDecisionOmittedWhenNil(t *testing.T) {
	cs := liveActivityContentState{Status: "connected", LastUpdate: 1700000000.0}
	b, err := json.Marshal(cs)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if strings.Contains(string(b), "lastDecision") {
		t.Fatalf("nil lastDecision must be omitted, got: %s", b)
	}
	dec := "approved"
	cs.LastDecision = &dec
	b2, _ := json.Marshal(cs)
	if !strings.Contains(string(b2), `"lastDecision":"approved"`) {
		t.Fatalf("set lastDecision must serialize, got: %s", b2)
	}
}
```

(If `strings` is not already imported in the test file, add it.)

- [ ] **Step 7: Run the Go tests**

Run: `cd daemon/push-backend && go test ./... -run 'ContentState|LiveActivity' -v 2>&1 | tail -20`
Expected: `PASS`, including `TestContentStateLastDecisionOmittedWhenNil` and the existing Date-pin test still green.

- [ ] **Step 8: Commit**

```bash
git add Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift \
  Packages/LancerKit/Tests/LancerKitTests/LiveActivityContentStateTests.swift \
  daemon/push-backend/liveactivity.go daemon/push-backend/liveactivity_test.go
git commit -m "feat(liveactivity): add lastDecision transient to ContentState (Swift + Go mirror)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Pure state-precedence resolver (`LiveActivityPresentation`)

**Files:**
- Create: `Packages/LancerKit/Sources/SessionFeature/LiveActivityPresentation.swift`
- Test: `Packages/LancerKit/Tests/LancerKitTests/LiveActivityPresentationTests.swift` *(new)*

**Interfaces:**
- Consumes: `LancerSessionAttributes.ContentState` (incl. `lastDecision` from Task 1).
- Produces:
  - `enum LiveActivityPrimaryState: Equatable { case needsYou(count: Int), decisionLanded(approved: Bool), running, idle }`
  - `struct LiveActivityPresentation: Equatable { let primary: LiveActivityPrimaryState; let cost: Double?; let costLevel: CostLevel }`
  - `enum CostLevel: Equatable { case none, normal, warning, over }`
  - `static func resolve(_ state: ContentState, budget: Double?) -> LiveActivityPresentation`
- Precedence: `needsYou` (pendingApprovals>0) > `decisionLanded` (lastDecision != nil) > `running` (isStreaming) > `idle`. Cost is independent overlay; `costLevel` = `.over` at ≥budget, `.warning` at ≥0.8·budget, `.normal` if cost>0 & budget nil/under, `.none` if cost nil/0.

- [ ] **Step 1: Write the failing tests** — `LiveActivityPresentationTests.swift`:

```swift
import Testing
@testable import SessionFeature

@available(iOS 16.2, *)
struct LiveActivityPresentationTests {
    typealias CS = LancerSessionAttributes.ContentState

    @Test func needsYouBeatsEverything() {
        let s = CS(status: "connected", pendingApprovals: 2, isStreaming: true,
                   cost: 1.0, lastDecision: "approved")
        let p = LiveActivityPresentation.resolve(s, budget: nil)
        #expect(p.primary == .needsYou(count: 2))
    }

    @Test func decisionLandedBeatsRunning() {
        let s = CS(status: "connected", pendingApprovals: 0, isStreaming: true, lastDecision: "rejected")
        #expect(LiveActivityPresentation.resolve(s, budget: nil).primary == .decisionLanded(approved: false))
    }

    @Test func runningWhenStreamingOnly() {
        let s = CS(status: "connected", isStreaming: true)
        #expect(LiveActivityPresentation.resolve(s, budget: nil).primary == .running)
    }

    @Test func idleWhenNothing() {
        let s = CS(status: "connected")
        #expect(LiveActivityPresentation.resolve(s, budget: nil).primary == .idle)
    }

    @Test func costLevelEscalates() {
        let warn = CS(status: "connected", cost: 8.0)
        #expect(LiveActivityPresentation.resolve(warn, budget: 10.0).costLevel == .warning)
        let over = CS(status: "connected", cost: 10.0)
        #expect(LiveActivityPresentation.resolve(over, budget: 10.0).costLevel == .over)
        let normal = CS(status: "connected", cost: 1.0)
        #expect(LiveActivityPresentation.resolve(normal, budget: nil).costLevel == .normal)
        let none = CS(status: "connected")
        #expect(LiveActivityPresentation.resolve(none, budget: nil).costLevel == .none)
    }
}
```

- [ ] **Step 2: Run, verify it fails** — `cd Packages/LancerKit && swift build 2>&1 | grep -i "LiveActivityPresentation\|error" | head` → fails (type missing).

- [ ] **Step 3: Implement the resolver** — `LiveActivityPresentation.swift`:

```swift
#if os(iOS)
import Foundation

@available(iOS 16.2, *)
public enum LiveActivityPrimaryState: Equatable {
    case needsYou(count: Int)
    case decisionLanded(approved: Bool)
    case running
    case idle
}

public enum CostLevel: Equatable { case none, normal, warning, over }

/// Pure, UI-free resolution of a ContentState into the single primary state to
/// render plus the cost overlay level. Keeps precedence logic out of the widget
/// (which stays pure presentation) and makes it unit-testable without ActivityKit.
@available(iOS 16.2, *)
public struct LiveActivityPresentation: Equatable {
    public let primary: LiveActivityPrimaryState
    public let cost: Double?
    public let costLevel: CostLevel

    public static func resolve(
        _ state: LancerSessionAttributes.ContentState,
        budget: Double?
    ) -> LiveActivityPresentation {
        let primary: LiveActivityPrimaryState
        if state.pendingApprovals > 0 {
            primary = .needsYou(count: state.pendingApprovals)
        } else if let d = state.lastDecision {
            primary = .decisionLanded(approved: d == "approved")
        } else if state.isStreaming {
            primary = .running
        } else {
            primary = .idle
        }

        let level: CostLevel
        if let c = state.cost, c > 0 {
            if let b = budget, b > 0 {
                if c >= b { level = .over }
                else if c >= 0.8 * b { level = .warning }
                else { level = .normal }
            } else {
                level = .normal
            }
        } else {
            level = .none
        }

        return LiveActivityPresentation(primary: primary, cost: state.cost, costLevel: level)
    }
}
#endif
```

- [ ] **Step 4: Run the build** — `cd Packages/LancerKit && swift build` → `Build complete!`

- [ ] **Step 5: Run the tests via the app target** (these are `#if os(iOS)`):

Run: `mcp__XcodeBuildMCP__test_sim` with scheme `LancerKitTests`, sim `iPhone 17 Pro`, `only: ["LancerKitTests/LiveActivityPresentationTests"]`.
Expected: all 5 tests pass. (If the scheme routes to the UI-test target as it did during the V1 merge, note that limitation and rely on the resolver being exercised by `swift build` + the precedence being plain value logic.)

- [ ] **Step 6: Commit**

```bash
git add Packages/LancerKit/Sources/SessionFeature/LiveActivityPresentation.swift \
  Packages/LancerKit/Tests/LancerKitTests/LiveActivityPresentationTests.swift
git commit -m "feat(liveactivity): pure state-precedence resolver for the widget

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Backend pushes `lastDecision` on resolution

**Files:**
- Modify: `daemon/push-backend/liveactivity.go` (add `pushLiveActivityDecision`)
- Test: `daemon/push-backend/liveactivity_test.go`
- Modify: the decision-handling path in `daemon/push-backend/decisions.go` (call the new push after a decision resolves) — read it first to find where a decision is recorded.

**Interfaces:**
- Produces: `func pushLiveActivityDecision(sessionID, decision string) error` — `decision` is `"approved"` or `"rejected"`; pushes a content-state with `LastDecision` set, `PendingApprovals: 0`, `Event: "update"`, priority 10. No-ops if no activity token (mirrors `pushLiveActivityApproval`).

- [ ] **Step 1: Write the failing test** — append to `liveactivity_test.go`:

```go
func TestPushLiveActivityDecisionSetsLastDecision(t *testing.T) {
	// Capture the payload by registering a token then marshaling what the
	// content-state would contain. We assert the builder, not the network.
	dec := "approved"
	cs := liveActivityContentState{
		Status: "connected", PendingApprovals: 0, LastDecision: &dec,
		LastUpdate: 1700000000.0,
	}
	b, _ := json.Marshal(cs)
	if !strings.Contains(string(b), `"lastDecision":"approved"`) {
		t.Fatalf("decision push must carry lastDecision, got: %s", b)
	}
	if strings.Contains(string(b), "command") {
		t.Fatalf("decision push must not carry command text, got: %s", b)
	}
}
```

- [ ] **Step 2: Run, verify it passes structurally** but the function doesn't exist yet — `cd daemon/push-backend && go test ./... -run LastDecision -v`. (This test asserts the content-state shape; Step 3 adds the function it documents.)

- [ ] **Step 3: Implement `pushLiveActivityDecision`** in `liveactivity.go` (after `pushLiveActivityApproval`):

```go
// pushLiveActivityDecision sends a transient "decision landed" content-state so
// the lock screen / Dynamic Island can confirm a just-resolved approval — including
// the cold path, where a killed-app Approve is resolved server-side and only a push
// can confirm it. The widget shows a ✓ for ~4s; a subsequent update/end clears it.
// PRIVACY: carries only the decision verb, never command text.
func pushLiveActivityDecision(sessionID, decision string) error {
	liveActivityRegistry.RLock()
	rec, ok := liveActivityRegistry.sessions[sessionID]
	var activityToken string
	if ok {
		activityToken = rec.activityToken
	}
	liveActivityRegistry.RUnlock()
	if !ok || activityToken == "" {
		return nil
	}

	stale := time.Now().Add(30 * time.Minute).Unix()
	d := decision
	contentState := liveActivityContentState{
		Status:           "connected",
		PendingApprovals: 0,
		IsStreaming:      false,
		LastDecision:     &d,
		LastUpdate:       float64(time.Now().UnixNano()) / 1e9,
	}
	payload := liveActivityPayload{
		APS: liveActivityAPS{
			Timestamp:    time.Now().Unix(),
			Event:        "update",
			ContentState: contentState,
			StaleDate:    &stale,
		},
	}
	return sendLiveActivityPush(activityToken, payload, 10)
}
```

- [ ] **Step 4: Wire the call** — read `daemon/push-backend/decisions.go`, find where an approval decision is recorded/forwarded (the handler that receives approve/reject), and after it resolves successfully, call:

```go
	// Confirm the decision on the lock-screen Live Activity (incl. cold path).
	if err := pushLiveActivityDecision(sessionID, decisionVerb); err != nil {
		log.Printf("live-activity decision push failed: %v", err)
	}
```

where `decisionVerb` is `"approved"` or `"rejected"` derived from the decision in that handler, and `sessionID` is the resolved session. Match the file's existing logging style.

- [ ] **Step 5: Run the Go tests + build**

Run: `cd daemon/push-backend && go build ./... && go test ./... 2>&1 | tail -10`
Expected: `ok  lancer/push-backend`.

- [ ] **Step 6: Commit**

```bash
git add daemon/push-backend/liveactivity.go daemon/push-backend/liveactivity_test.go daemon/push-backend/decisions.go
git commit -m "feat(liveactivity): push lastDecision on resolution (cold-path confirmation)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Widget renders the four states

**Files:**
- Modify: `LancerLiveActivityWidget/LancerLiveActivityWidget.swift`

**Interfaces:**
- Consumes: `LiveActivityPresentation.resolve(context.state, budget:)` (Task 2). For now pass `budget: nil` (cost escalation degrades to `.normal`; see Risk note — budget source is a plan-time open question resolved as "pass nil until ContentState carries a budget").

- [ ] **Step 1: Add a decision-landed color + extend `statusColor`** — in `LancerLiveActivityWidget.swift`, replace the body of `statusColor(for:)` so decision-landed shows green and precedence matches the resolver:

```swift
    private func statusColor(for state: LancerSessionAttributes.ContentState) -> Color {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou:
            return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1) // amber (warn)
        case .decisionLanded(let approved):
            return approved
                ? Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1)  // green (approved)
                : Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1)  // red (rejected)
        case .running:
            return Color(.sRGB, red: 0.318, green: 0.573, blue: 0.929, opacity: 1) // blue (streaming)
        case .idle:
            switch state.status {
            case "reconnecting": return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1)
            case "error":        return Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1)
            case "suspended":    return Color(.sRGB, red: 0.373, green: 0.357, blue: 0.329, opacity: 1)
            default:             return Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1)
            }
        }
    }
```

- [ ] **Step 2: Extend `statusLabel`** so decision-landed reads as a confirmation:

```swift
    private func statusLabel(for state: LancerSessionAttributes.ContentState) -> String {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou(let count): return count == 1 ? "1 pending" : "\(count) pending"
        case .decisionLanded(let approved): return approved ? "Approved ✓" : "Rejected ✓"
        case .running: return "streaming"
        case .idle:
            switch state.status {
            case "connected":    return "connected"
            case "reconnecting": return "reconnecting"
            case "error":        return "error"
            case "suspended":    return "suspended"
            default:             return state.status
            }
        }
    }
```

- [ ] **Step 3: Extend `shortStatus`** (compact trailing / minimal) for the ✓:

```swift
    private func shortStatus(for state: LancerSessionAttributes.ContentState) -> String {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou(let count): return "\(count)"
        case .decisionLanded:      return "✓"
        case .running:             return "..."
        case .idle:                return String(state.status.prefix(3)).lowercased() + "..."
        }
    }
```

- [ ] **Step 4: Cost escalation tint** — where cost is rendered (lock screen ~line 114-119, expanded trailing ~line 42-45), tint by `costLevel`. Add a helper and apply it to the cost `Text`'s `.foregroundStyle`:

```swift
    private func costColor(for state: LancerSessionAttributes.ContentState) -> Color {
        switch LiveActivityPresentation.resolve(state, budget: nil).costLevel {
        case .over:    return Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1) // red
        case .warning: return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1) // amber
        default:       return .secondary
        }
    }
```

Replace the cost `Text(...).foregroundStyle(.secondary)` occurrences in the lock-screen and expanded-trailing regions with `.foregroundStyle(costColor(for: context.state))`. (With `budget: nil`, level is `.normal` → `.secondary`, so this is a no-op until a budget is supplied — wiring is in place, behavior preserved.)

- [ ] **Step 5: Verify the app-target build** (the widget only truly compiles here):

Run: `mcp__XcodeBuildMCP__build_sim` (scheme `LancerWatchWidget` is NOT this — use scheme `LancerLiveActivityWidget` or the app `Lancer` which embeds it). Prefer scheme `Lancer`.
Expected: `SUCCEEDED`, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add LancerLiveActivityWidget/LancerLiveActivityWidget.swift
git commit -m "feat(liveactivity): widget renders needs-you/running/decision-landed/cost states

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Warm deep-link — tap opens the detail sheet

**Files:**
- Modify: `Packages/LancerKit/Sources/NotificationsKit/Notifications.swift` (add `.lancerOpenApproval` notification name + an `OpenApprovalBuffer`)
- Modify: `Packages/LancerKit/Sources/InboxFeature/InboxView.swift` (observe the open-approval signal → set `detailApproval`)

**Interfaces:**
- Produces: `Notification.Name.lancerOpenApproval` (userInfo `["approvalId": String]`); `OpenApprovalBuffer.shared` with `record(approvalID:)` / `drain() -> [String]` (mirrors `ApprovalActionBuffer`, but for *review* intent not *decide*).
- Consumes (InboxView): an `approvalId` → look up the matching `Approval` in the view model's list → set `detailApproval`.

- [ ] **Step 1: Add the notification name + buffer** in `Notifications.swift`. After `lancerApprovalAction` (line 10) add:

```swift
    /// Posted when the user taps a notification/Live-Activity BODY (not an action
    /// button) to REVIEW an approval. userInfo: ["approvalId": String]. Distinct
    /// from lancerApprovalAction, which decides. Opens the detail sheet.
    static let lancerOpenApproval = Notification.Name("dev.lancer.openApproval")
```

After `ApprovalActionBuffer` (line 78) add a sibling buffer:

```swift
/// Buffers a cold-launch "open this approval's detail" intent (a notification/
/// Live-Activity body tap), mirroring ApprovalActionBuffer but for review, not
/// decision. AppRoot drains it once the graph is ready and routes to the Inbox.
public final class OpenApprovalBuffer: @unchecked Sendable {
    public static let shared = OpenApprovalBuffer()
    private let lock = NSLock()
    private var pending: [String] = []
    private init() {}
    public func record(approvalID: String) {
        lock.lock(); defer { lock.unlock() }
        pending.append(approvalID)
    }
    public func drain() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let snapshot = pending; pending.removeAll(); return snapshot
    }
}
```

- [ ] **Step 2: Route the body tap in the delegate** — find `LancerNotificationDelegate`'s `userNotificationCenter(_:didReceive:)` in `Notifications.swift`. When `response.actionIdentifier == UNNotificationDefaultActionIdentifier` (body tap, not Approve/Reject), post `.lancerOpenApproval` with the `approvalId` from `userInfo` AND record it on `OpenApprovalBuffer.shared` (for the cold case). Add, in that method:

```swift
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let approvalId = response.notification.request.content.userInfo["approvalId"] as? String {
            OpenApprovalBuffer.shared.record(approvalID: approvalId)
            NotificationCenter.default.post(
                name: .lancerOpenApproval, object: nil,
                userInfo: ["approvalId": approvalId]
            )
        }
```

(Leave the existing Approve/Reject action-identifier handling untouched.)

- [ ] **Step 3: Observe in InboxView** — in `InboxView.swift`, add an `.onReceive` for `.lancerOpenApproval` that finds the approval and sets `detailApproval`. Near the other view-state, add:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .lancerOpenApproval)) { note in
            guard let idString = note.userInfo?["approvalId"] as? String,
                  let uuid = UUID(uuidString: idString) else { return }
            if let match = vm.approvals.first(where: { $0.id.rawValue == uuid }) {
                detailApproval = match
            }
        }
```

(Confirm `vm.approvals` is the published list and `Approval.id.rawValue` is the `UUID` — adjust the key path if the VM exposes a different accessor.)

- [ ] **Step 4: Write a routing unit test** — `Packages/LancerKit/Tests/LancerKitTests/OpenApprovalBufferTests.swift`:

```swift
import Testing
@testable import NotificationsKit

struct OpenApprovalBufferTests {
    @Test func recordsAndDrainsOnce() {
        let b = OpenApprovalBuffer.shared
        _ = b.drain() // clear
        b.record(approvalID: "ABC")
        b.record(approvalID: "DEF")
        #expect(b.drain() == ["ABC", "DEF"])
        #expect(b.drain() == []) // drained once
    }
}
```

- [ ] **Step 5: Build + run**

Run: `cd Packages/LancerKit && swift build` → `Build complete!`
Run: `mcp__XcodeBuildMCP__test_sim` scheme `LancerKitTests`, `only: ["LancerKitTests/OpenApprovalBufferTests"]` → PASS (or note the scheme-routing limitation).

- [ ] **Step 6: Commit**

```bash
git add Packages/LancerKit/Sources/NotificationsKit/Notifications.swift \
  Packages/LancerKit/Sources/InboxFeature/InboxView.swift \
  Packages/LancerKit/Tests/LancerKitTests/OpenApprovalBufferTests.swift
git commit -m "feat(inbox): warm deep-link — notification/Live-Activity body tap opens detail

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Cold deep-link — drain the open-approval buffer in AppRoot

**Files:**
- Modify: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`

**⚠️ Collision note:** `AppRoot.swift` is a hot file the owner may be live-editing. Before editing, run `git status --short` — if `AppRoot.swift` shows uncommitted changes, STOP and report; do not overwrite. Make the change minimal and additive.

**Interfaces:**
- Consumes: `OpenApprovalBuffer.shared.drain()` (Task 5), `.lancerOpenApproval` (Task 5). Routes to the Inbox sidebar destination and re-posts `.lancerOpenApproval` so the (now-mounted) `InboxView` observer fires.

- [ ] **Step 1: Drain on launch** — find where `AppRoot` drains `ApprovalActionBuffer` (search `ApprovalActionBuffer.shared.drain` in AppRoot.swift). Immediately after that drain, add a drain of the open-approval buffer that navigates to Inbox and re-emits the open signal:

```swift
            for approvalID in OpenApprovalBuffer.shared.drain() {
                // Cold launch: route to Inbox, then re-post so the now-mounted
                // InboxView observer opens the detail sheet. Review intent only —
                // never auto-decides (that's ApprovalActionBuffer's separate job).
                navigateToInbox()
                NotificationCenter.default.post(
                    name: .lancerOpenApproval, object: nil,
                    userInfo: ["approvalId": approvalID]
                )
            }
```

- [ ] **Step 2: Implement/confirm `navigateToInbox()`** — if AppRoot already has a way to select the Inbox sidebar destination (search `SidebarDestination` / `selectedTab = .inbox`), call it. If not, set the sidebar selection to the Inbox destination directly (match the existing destination-selection pattern). Keep it to one line that selects Inbox.

- [ ] **Step 3: Also handle the warm case at AppRoot level** — ensure there's a live `.lancerOpenApproval` subscriber that calls `navigateToInbox()` (so a body tap while the app is on a different surface switches to Inbox before the sheet opens). Add near the existing notification subscribers in `configureE2ERelayBridge` or the root `.task`:

```swift
        Task { @MainActor in
            for await _ in NotificationCenter.default.notifications(named: .lancerOpenApproval) {
                navigateToInbox()
            }
        }
```

- [ ] **Step 4: Verify app-target build**

Run: `mcp__XcodeBuildMCP__build_sim` scheme `Lancer`, sim `iPhone 17 Pro`.
Expected: `SUCCEEDED`, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add Packages/LancerKit/Sources/AppFeature/AppRoot.swift
git commit -m "feat(inbox): cold deep-link — drain open-approval buffer, route to Inbox

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Diff render for `.patch` approvals in the detail sheet

**Files:**
- Modify: `Packages/LancerKit/Sources/DesignSystem/Components/InboxApprovalDetail.swift` (add an optional patch param + diff section)
- Modify: `Packages/LancerKit/Sources/InboxFeature/InboxView.swift:206-262` (pass `approval.patch` into the detail)

**Interfaces:**
- Produces (InboxApprovalDetail): a new init param `patch: String? = nil` (added LAST in the init, defaulted, so existing call sites compile). When non-nil and parseable, render a `DiffView`.
- Consumes: `DiffKit.UnifiedDiffParser.parse(_:) -> UnifiedDiff?` and `DiffFeature.DiffView(diff:)` — already used by `InboxView` (it imports both).

**Note:** `InboxApprovalDetail` lives in `DesignSystem`. Confirm `DesignSystem` can depend on `DiffKit`+`DiffFeature` (Package.swift). If that edge does NOT exist / would be circular, instead render the diff in `InboxView`'s `detailSheet` wrapper (which already imports DiffKit/DiffFeature) by composing the `DiffView` above/below `InboxApprovalDetail`, and skip the param. Pick whichever keeps the dependency graph clean — decide by reading `Package.swift` first.

- [ ] **Step 1: Decide placement** — read `Package.swift`: does the `DesignSystem` target depend on `DiffKit`/`DiffFeature`? If yes → add the param to `InboxApprovalDetail` (Steps 2-3). If no → compose the diff in `InboxView.detailSheet` instead (Step 4 variant). Record the decision in the commit message.

- [ ] **Step 2 (DesignSystem path): Add the param + section** to `InboxApprovalDetail.swift`. Add `let patch: String?` to the stored props, `patch: String? = nil` as the last init param (and assign it). In `body`, where the command block renders, add below it:

```swift
            if let patch, let diff = UnifiedDiffParser.parse(patch), !diff.files.isEmpty {
                DiffView(diff: diff)
                    .frame(maxHeight: 280)
            }
```

Add `import DiffKit` and `import DiffFeature` at the top of the file.

- [ ] **Step 3 (DesignSystem path): Pass the patch** in `InboxView.swift:209` — add `patch: approval.patch,` to the `InboxApprovalDetail(...)` call.

- [ ] **Step 4 (InboxView path, only if Step 1 says DesignSystem can't depend on DiffKit):** in `InboxView.detailSheet`, wrap the returned `InboxApprovalDetail` in a `VStack` and append, for `approval.kind == .patch`:

```swift
            if approval.kind == .patch, let patch = approval.patch,
               let diff = UnifiedDiffParser.parse(patch), !diff.files.isEmpty {
                DiffView(diff: diff).frame(maxHeight: 280)
            }
```

- [ ] **Step 5: Write a parse test** — `Packages/LancerKit/Tests/LancerKitTests/PatchDiffRenderTests.swift`:

```swift
import Testing
import DiffKit

struct PatchDiffRenderTests {
    @Test func parsesAUnifiedPatch() {
        let patch = """
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,2 +1,2 @@
        -old line
        +new line
         context
        """
        let diff = UnifiedDiffParser.parse(patch)
        #expect(diff != nil)
        #expect(diff?.files.isEmpty == false)
    }
}
```

- [ ] **Step 6: Build + test**

Run: `cd Packages/LancerKit && swift build` → `Build complete!`
Run: `mcp__XcodeBuildMCP__build_sim` scheme `Lancer` → `SUCCEEDED`.
Run: `mcp__XcodeBuildMCP__test_sim` `only: ["LancerKitTests/PatchDiffRenderTests"]` → PASS (or note scheme routing).

- [ ] **Step 7: Commit**

```bash
git add Packages/LancerKit/Sources/DesignSystem/Components/InboxApprovalDetail.swift \
  Packages/LancerKit/Sources/InboxFeature/InboxView.swift \
  Packages/LancerKit/Tests/LancerKitTests/PatchDiffRenderTests.swift
git commit -m "feat(inbox): render real diff for patch approvals in the detail sheet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final Verification (after all tasks)

- [ ] `cd Packages/LancerKit && swift build` → clean.
- [ ] `mcp__XcodeBuildMCP__build_sim` scheme `Lancer` → SUCCEEDED, 0 warnings.
- [ ] `cd daemon/push-backend && go build ./... && go test ./...` → pass.
- [ ] `cd daemon/lancerd && go build ./...` → pass (no regressions; lancerd unchanged but build to be safe).
- [ ] Flag for owner device QA (cannot be simulator-verified): (1) cold-path ✓ — killed-app Approve → green ✓ on lock screen; (2) cold deep-link — killed-app body tap → app launches to Inbox detail sheet; (3) warm Live-Activity body tap → detail opens. Extend the device prompt in the prior session.

## Self-Review (completed by author)

- **Spec coverage:** §1 `lastDecision` → T1. §2 four states + precedence + cost overlay → T2 (resolver) + T4 (render). §3.1 deep-link warm/cold → T5/T6. §3.2 reveal = existing sheet, app-lock gate (no new code) → satisfied by reusing `InboxApprovalDetail` (no task needed; explicitly *not* adding a gate). §3.3 patch diff → T7. §4 boundaries/testing → tasks carry tests; verification gate in Global Constraints. §5 open questions: (1) lastDecision clear = explicit push then update/end — handled in T3's ~4s/stale-date comment; (2) InboxFeature→DiffKit edge — confirmed already declared (Package.swift:168-169); (3) cost budget source — resolved as `budget: nil` for now (T4 Step 4 note), wiring in place; (4) cold tap-body vs button — T5 uses `UNNotificationDefaultActionIdentifier` for review, leaves action buffer for decide.
- **Placeholder scan:** none — every code step shows real code; the one branch (T7 Step 1) is a documented decision, not a TODO.
- **Type consistency:** `ContentState.lastDecision: String?` (T1) consumed as `state.lastDecision` (T2 resolver, T4 widget). `LiveActivityPresentation.resolve(_:budget:)` defined T2, called T4. `OpenApprovalBuffer`/`.lancerOpenApproval` defined T5, consumed T6. `UnifiedDiffParser.parse`/`DiffView` used T7 — match existing InboxView usage.
