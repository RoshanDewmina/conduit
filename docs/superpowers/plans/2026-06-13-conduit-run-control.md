# Conduit Run-Control (Two-Way Control v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add phone→agent run-control — **stop (kill), pause/resume, and set-budget** — over the existing conduitd channel, surfaced in a Run Detail screen reachable from Fleet.

**Architecture:** conduitd already tracks launched runs in a `dispatcher` (`daemon/conduitd/dispatch.go`) and exposes `agent.cancel`. We extend the process handle to support SIGSTOP/SIGCONT, add `dispatcher.pause/resume/setBudget` with continuous budget enforcement via the existing spend feed, and add three RPCs (`agent.pause`, `agent.resume`, `agent.budget.set`). On iOS, `DaemonChannel` gains three methods mirroring `cancelRun`; a `RunControlStore` (depending on a `RunControlling` protocol for testability) drives a `RunDetailView` with confirm + haptics per the consistency rules.

**Tech Stack:** Go (conduitd, stdlib + `syscall`), Swift 6 / SwiftUI (ConduitKit), XCTest, `go test`.

---

## File structure

**conduitd (Go):**
- `daemon/conduitd/dispatch.go` — MODIFY: `procHandle` type, richer `launchFunc`, `pause/resume/setBudget/enforce`, `BudgetUSD` on `dispatchRun`.
- `daemon/conduitd/dispatch_test.go` — MODIFY: fake handle, pause/resume/budget tests.
- `daemon/conduitd/server.go` — MODIFY: three RPC cases in the dispatch switch.
- `daemon/conduitd/server_test.go` — MODIFY: RPC round-trip tests.

**ConduitKit (Swift):**
- `Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift` — MODIFY: `pauseRun/resumeRun/setRunBudget`.
- `Packages/ConduitKit/Sources/AppFeature/RunControlStore.swift` — CREATE: `RunControlling` protocol + `RunControlStore`.
- `Packages/ConduitKit/Tests/AppFeatureTests/RunControlStoreTests.swift` — CREATE: fake-backed tests.
- `Packages/ConduitKit/Sources/AppFeature/RunDetailView.swift` — CREATE: the screen (mirrors board `AgentRunDetailScreen`).
- `Packages/ConduitKit/Sources/AppFeature/FleetView.swift` — MODIFY: navigate a row → `RunDetailView`.

---

## Task 1: Process handle with pause/resume (conduitd)

**Files:**
- Modify: `daemon/conduitd/dispatch.go`
- Test: `daemon/conduitd/dispatch_test.go`

- [ ] **Step 1: Write the failing test**

Add to `dispatch_test.go`:

```go
func TestProcHandlePauseResumeRecorded(t *testing.T) {
	var events []string
	d := newDispatcher()
	d.launch = func(argv []string, cwd string) (*procHandle, error) {
		return &procHandle{
			kill:   func() { events = append(events, "kill") },
			pause:  func() { events = append(events, "pause") },
			resume: func() { events = append(events, "resume") },
		}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "hi"},
		func(ApprovalEvent) (string, string) { return "allow", "test-allow" },
		func(AuditEntry) {})
	if res.Status != "running" {
		t.Fatalf("want running, got %q (%s)", res.Status, res.Message)
	}
	if !d.pause(res.RunID) || !d.resume(res.RunID) {
		t.Fatal("pause/resume returned false for a live run")
	}
	if got := strings.Join(events, ","); got != "pause,resume" {
		t.Fatalf("want pause,resume; got %q", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon/conduitd && go test -run TestProcHandlePauseResumeRecorded ./...`
Expected: FAIL — `procHandle` undefined; `d.launch` signature mismatch; `d.pause`/`d.resume` undefined.

- [ ] **Step 3: Write minimal implementation**

In `dispatch.go`, add `"syscall"` to imports, then replace the launcher + run types:

```go
// procHandle controls a launched agent process. Injectable for tests.
type procHandle struct {
	kill   func()
	pause  func()
	resume func()
}

// launchFunc starts an agent process and returns its control handle.
type launchFunc func(argv []string, cwd string) (*procHandle, error)

func realLauncher(argv []string, cwd string) (*procHandle, error) {
	cmd := exec.Command(argv[0], argv[1:]...) // explicit argv, no shell
	cmd.Dir = cwd
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	go func() { _ = cmd.Wait() }()
	proc := cmd.Process
	return &procHandle{
		kill:   func() { if proc != nil { _ = proc.Kill() } },
		pause:  func() { if proc != nil { _ = proc.Signal(syscall.SIGSTOP) } },
		resume: func() { if proc != nil { _ = proc.Signal(syscall.SIGCONT) } },
	}, nil
}
```

Change `dispatchRun` to hold the handle + budget + a paused-aware status:

```go
type dispatchRun struct {
	ID        string
	Agent     string
	Prompt    string
	Status    string // running | paused | cancelled | budget-exceeded
	BudgetUSD float64
	handle    *procHandle
}
```

In `dispatch()`, replace the launch + store block (the `cancel, err := d.launch(...)` section through the `d.runs[id] = ...` line):

```go
	handle, err := d.launch(argv, p.CWD)
	if err != nil {
		audit(AuditEntry{Action: "dispatch-error", Agent: p.Agent, Kind: "dispatch", Command: p.Prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	id := newUUID()
	d.mu.Lock()
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Agent, Prompt: p.Prompt, Status: "running", BudgetUSD: p.BudgetUSD, handle: handle}
	d.mu.Unlock()
```

Update `cancel()` to use the handle and add `pause`/`resume`:

```go
func (d *dispatcher) cancel(runID string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil {
		return false
	}
	if run.handle != nil {
		run.handle.kill()
	}
	run.Status = "cancelled"
	return true
}

func (d *dispatcher) pause(runID string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil || run.Status != "running" {
		return false
	}
	if run.handle != nil {
		run.handle.pause()
	}
	run.Status = "paused"
	return true
}

func (d *dispatcher) resume(runID string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	run := d.runs[runID]
	if run == nil || run.Status != "paused" {
		return false
	}
	if run.handle != nil {
		run.handle.resume()
	}
	run.Status = "running"
	return true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon/conduitd && go test -run TestProcHandlePauseResumeRecorded ./...`
Expected: PASS

- [ ] **Step 5: Run the full package to catch the launcher signature change**

Run: `cd daemon/conduitd && go build ./... && go test ./...`
Expected: PASS (any existing test that built a `cancel func()` launcher must now return `*procHandle` — update those fakes to the new shape if the build flags them).

- [ ] **Step 6: Commit**

```bash
git add daemon/conduitd/dispatch.go daemon/conduitd/dispatch_test.go
git commit -m "feat(conduitd): process handle with pause/resume + run-control state"
```

---

## Task 2: Continuous budget enforcement (conduitd)

**Files:**
- Modify: `daemon/conduitd/dispatch.go`
- Test: `daemon/conduitd/dispatch_test.go`

- [ ] **Step 1: Write the failing test**

```go
func TestSetBudgetKillsRunOverCap(t *testing.T) {
	var killed bool
	d := newDispatcher()
	d.launch = func(argv []string, cwd string) (*procHandle, error) {
		return &procHandle{kill: func() { killed = true }, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "hi"},
		func(ApprovalEvent) (string, string) { return "allow", "test-allow" },
		func(AuditEntry) {})

	// Lowering the cap below current spend must kill the run immediately.
	d.setSpentUSD(4.00)
	if !d.setBudget(res.RunID, 2.00) {
		t.Fatal("setBudget returned false for a live run")
	}
	if !killed {
		t.Fatal("run over its new cap was not killed")
	}
	if st := d.runStatus(res.RunID); st != "budget-exceeded" {
		t.Fatalf("want budget-exceeded, got %q", st)
	}
}

func TestSpendUpdateEnforcesPerRunCap(t *testing.T) {
	var killed bool
	d := newDispatcher()
	d.launch = func(argv []string, cwd string) (*procHandle, error) {
		return &procHandle{kill: func() { killed = true }, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "hi", BudgetUSD: 5.00},
		func(ApprovalEvent) (string, string) { return "allow", "ok" }, func(AuditEntry) {})
	d.setSpentUSD(4.99) // under cap — still running
	if killed {
		t.Fatal("killed under cap")
	}
	d.setSpentUSD(5.01) // crosses cap — enforce on spend update
	if !killed || d.runStatus(res.RunID) != "budget-exceeded" {
		t.Fatal("spend crossing the cap did not stop the run")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon/conduitd && go test -run 'TestSetBudget|TestSpendUpdate' ./...`
Expected: FAIL — `d.setBudget`, `d.runStatus`, and per-run enforcement undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `dispatch.go`:

```go
func (d *dispatcher) runStatus(runID string) string {
	d.mu.Lock()
	defer d.mu.Unlock()
	if run := d.runs[runID]; run != nil {
		return run.Status
	}
	return ""
}

// setBudget updates a run's cap and enforces it immediately.
func (d *dispatcher) setBudget(runID string, usd float64) bool {
	d.mu.Lock()
	run := d.runs[runID]
	if run == nil {
		d.mu.Unlock()
		return false
	}
	run.BudgetUSD = usd
	d.mu.Unlock()
	d.enforceBudgets()
	return true
}

// enforceBudgets kills any running run whose accumulated spend meets its cap.
func (d *dispatcher) enforceBudgets() {
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, run := range d.runs {
		if run.Status != "running" && run.Status != "paused" {
			continue
		}
		if run.BudgetUSD > 0 && d.spentUSD >= run.BudgetUSD {
			if run.handle != nil {
				run.handle.kill()
			}
			run.Status = "budget-exceeded"
		}
	}
}
```

Make `setSpentUSD` enforce after updating spend:

```go
func (d *dispatcher) setSpentUSD(v float64) {
	d.mu.Lock()
	d.spentUSD = v
	d.mu.Unlock()
	d.enforceBudgets()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon/conduitd && go test -run 'TestSetBudget|TestSpendUpdate' ./...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/dispatch.go daemon/conduitd/dispatch_test.go
git commit -m "feat(conduitd): continuous per-run budget enforcement + setBudget"
```

---

## Task 3: Run-control RPCs (conduitd server)

**Files:**
- Modify: `daemon/conduitd/server.go`
- Test: `daemon/conduitd/server_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server_test.go` (follow the existing harness that builds a `*server` and calls `handleRPC`/`dispatch`; mirror how `TestAgentCancel`-style tests construct the server. If the existing cancel test uses a helper like `newTestServer(t)`, reuse it):

```go
func TestRunControlRPCs(t *testing.T) {
	s := newTestServer(t) // existing helper used by the agent.cancel test
	s.dispatcher.launch = func(argv []string, cwd string) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	run := s.dispatcher.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"},
		func(ApprovalEvent) (string, string) { return "allow", "ok" }, func(AuditEntry) {})

	if got := callRPC(t, s, "agent.pause", map[string]any{"runId": run.RunID}); got["paused"] != true {
		t.Fatalf("agent.pause: %v", got)
	}
	if got := callRPC(t, s, "agent.resume", map[string]any{"runId": run.RunID}); got["resumed"] != true {
		t.Fatalf("agent.resume: %v", got)
	}
	if got := callRPC(t, s, "agent.budget.set", map[string]any{"runId": run.RunID, "budgetUSD": 1.0}); got["ok"] != true {
		t.Fatalf("agent.budget.set: %v", got)
	}
}
```

> If `callRPC`/`newTestServer` helpers don't exist, add a `callRPC(t, s, method, params)` that marshals a `jsonrpcMsg`, calls the same dispatch entrypoint `agent.cancel` uses, and returns the decoded result map — copy the body of the existing cancel test.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon/conduitd && go test -run TestRunControlRPCs ./...`
Expected: FAIL — `method not found` for the three new methods.

- [ ] **Step 3: Write minimal implementation**

In `server.go`, add three cases next to `case "agent.cancel":`:

```go
	case "agent.pause":
		var p struct {
			RunID string `json:"runId"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.writeResult(msg.ID, map[string]bool{"paused": s.dispatcher.pause(p.RunID)})

	case "agent.resume":
		var p struct {
			RunID string `json:"runId"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.writeResult(msg.ID, map[string]bool{"resumed": s.dispatcher.resume(p.RunID)})

	case "agent.budget.set":
		var p struct {
			RunID     string  `json:"runId"`
			BudgetUSD float64 `json:"budgetUSD"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.writeResult(msg.ID, map[string]bool{"ok": s.dispatcher.setBudget(p.RunID, p.BudgetUSD)})
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon/conduitd && go test -run TestRunControlRPCs ./... && go vet ./...`
Expected: PASS, vet clean.

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/server.go daemon/conduitd/server_test.go
git commit -m "feat(conduitd): agent.pause / agent.resume / agent.budget.set RPCs"
```

---

## Task 4: DaemonChannel run-control methods (iOS)

**Files:**
- Modify: `Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift`

- [ ] **Step 1: Write the implementation** (mirrors `cancelRun`, immediately below it at line ~264)

```swift
    @discardableResult
    public func pauseRun(runId: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.pause", params: ["runId": runId])
        return (try Self.decodeResultObject(data)["paused"] as? Bool) ?? false
    }

    @discardableResult
    public func resumeRun(runId: String) async throws -> Bool {
        let data = try await sendRPC(method: "agent.resume", params: ["runId": runId])
        return (try Self.decodeResultObject(data)["resumed"] as? Bool) ?? false
    }

    @discardableResult
    public func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool {
        let data = try await sendRPC(method: "agent.budget.set", params: ["runId": runId, "budgetUSD": budgetUSD])
        return (try Self.decodeResultObject(data)["ok"] as? Bool) ?? false
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd Packages/ConduitKit && swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift
git commit -m "feat(ios): DaemonChannel pause/resume/setRunBudget RPC calls"
```

---

## Task 5: RunControlStore + protocol (iOS, TDD)

**Files:**
- Create: `Packages/ConduitKit/Sources/AppFeature/RunControlStore.swift`
- Test: `Packages/ConduitKit/Tests/AppFeatureTests/RunControlStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppFeature

final class RunControlStoreTests: XCTestCase {
    final class FakeChannel: RunControlling {
        var calls: [String] = []
        func pauseRun(runId: String) async throws -> Bool { calls.append("pause:\(runId)"); return true }
        func resumeRun(runId: String) async throws -> Bool { calls.append("resume:\(runId)"); return true }
        func stopRun(runId: String) async throws -> Bool { calls.append("stop:\(runId)"); return true }
        func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { calls.append("budget:\(runId):\(budgetUSD)"); return true }
    }

    @MainActor
    func testPauseThenResumeUpdatesStatus() async {
        let fake = FakeChannel()
        let store = RunControlStore(channel: fake, runId: "r1")
        await store.pause()
        XCTAssertEqual(store.status, .paused)
        await store.resume()
        XCTAssertEqual(store.status, .running)
        XCTAssertEqual(fake.calls, ["pause:r1", "resume:r1"])
    }

    @MainActor
    func testStopIsTerminalAndSetsBudget() async {
        let fake = FakeChannel()
        let store = RunControlStore(channel: fake, runId: "r1")
        await store.setBudget(2.50)
        await store.stop()
        XCTAssertEqual(store.status, .stopped)
        XCTAssertEqual(fake.calls, ["budget:r1:2.5", "stop:r1"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/ConduitKit && swift test --filter RunControlStoreTests`
Expected: FAIL — `RunControlling`, `RunControlStore`, `RunStatus` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `RunControlStore.swift`:

```swift
import Foundation
import SSHTransport

public enum RunStatus: Equatable { case running, paused, stopped, budgetExceeded }

/// Run-control surface the store depends on (DaemonChannel conforms in app code; faked in tests).
public protocol RunControlling: Sendable {
    func pauseRun(runId: String) async throws -> Bool
    func resumeRun(runId: String) async throws -> Bool
    func stopRun(runId: String) async throws -> Bool
    func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool
}

@MainActor
public final class RunControlStore: ObservableObject {
    @Published public private(set) var status: RunStatus = .running
    @Published public private(set) var lastError: String?

    private let channel: RunControlling
    private let runId: String

    public init(channel: RunControlling, runId: String, status: RunStatus = .running) {
        self.channel = channel
        self.runId = runId
        self.status = status
    }

    public func pause() async { await run { if try await channel.pauseRun(runId: runId) { status = .paused } } }
    public func resume() async { await run { if try await channel.resumeRun(runId: runId) { status = .running } } }
    public func stop() async { await run { if try await channel.stopRun(runId: runId) { status = .stopped } } }
    public func setBudget(_ usd: Double) async { await run { _ = try await channel.setRunBudget(runId: runId, budgetUSD: usd) } }

    private func run(_ op: () async throws -> Void) async {
        do { try await op() } catch { lastError = error.localizedDescription }
    }
}
```

- [ ] **Step 4: Conform DaemonChannel to RunControlling**

`DaemonChannel` already has `pauseRun`, `resumeRun`, `setRunBudget` (Task 4). Add a `stopRun` alias + the conformance. In `DaemonChannel.swift`, below `cancelRun`:

```swift
    @discardableResult
    public func stopRun(runId: String) async throws -> Bool { try await cancelRun(runId: runId) }
```

In `RunControlStore.swift` (or a small extension file), declare the conformance:

```swift
extension SSHTransport.DaemonChannel: RunControlling {}
```

- [ ] **Step 5: Run test + build to verify**

Run: `cd Packages/ConduitKit && swift test --filter RunControlStoreTests && swift build`
Expected: PASS, build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Packages/ConduitKit/Sources/AppFeature/RunControlStore.swift Packages/ConduitKit/Tests/AppFeatureTests/RunControlStoreTests.swift Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift
git commit -m "feat(ios): RunControlStore + RunControlling protocol (TDD)"
```

---

## Task 6: Run Detail screen (iOS UI)

**Files:**
- Create: `Packages/ConduitKit/Sources/AppFeature/RunDetailView.swift`
- Modify: `Packages/ConduitKit/Sources/AppFeature/FleetView.swift`

> Visual reference: the board's `AgentRunDetailScreen` (`docs/audit/migration-board/cc-screens-3.jsx`).
> Obey `docs/audit/CONDUIT_UI_CONSISTENCY_RULES.md`: destructive-left Stop, single footer, haptics.

- [ ] **Step 1: Write the failing test** (control-enablement logic, no UI rendering)

Add to `RunControlStoreTests.swift`:

```swift
    @MainActor
    func testControlAvailability() {
        let store = RunControlStore(channel: FakeChannel(), runId: "r1")
        XCTAssertTrue(store.canPause)   // running → can pause, can stop
        XCTAssertTrue(store.canStop)
        XCTAssertFalse(store.canResume)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/ConduitKit && swift test --filter testControlAvailability`
Expected: FAIL — `canPause/canResume/canStop` undefined.

- [ ] **Step 3: Add the computed flags to `RunControlStore`**

```swift
    public var canStop: Bool { status == .running || status == .paused }
    public var canPause: Bool { status == .running }
    public var canResume: Bool { status == .paused }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/ConduitKit && swift test --filter testControlAvailability`
Expected: PASS

- [ ] **Step 5: Create `RunDetailView.swift`**

```swift
import SwiftUI
import DesignSystem

public struct RunDetailView: View {
    @StateObject private var store: RunControlStore
    @State private var showBudgetSheet = false
    @State private var confirmStop = false

    public init(channel: RunControlling, runId: String, status: RunStatus = .running) {
        _store = StateObject(wrappedValue: RunControlStore(channel: channel, runId: runId, status: status))
    }

    public var body: some View {
        ScrollView { /* header card + live output tail — match AgentRunDetailScreen */ }
            .safeAreaInset(edge: .bottom) { controls }
            .confirmationDialog("Stop this run?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop run", role: .destructive) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    Task { await store.stop() }
                }
            }
            .sheet(isPresented: $showBudgetSheet) { BudgetSheet { usd in Task { await store.setBudget(usd) } } }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            DSButton("Stop", role: .destructive, enabled: store.canStop) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(); confirmStop = true
            }
            if store.canResume {
                DSButton("Resume", enabled: true) {
                    UISelectionFeedbackGenerator().selectionChanged(); Task { await store.resume() }
                }
            } else {
                DSButton("Pause", enabled: store.canPause) {
                    UISelectionFeedbackGenerator().selectionChanged(); Task { await store.pause() }
                }
            }
            DSButton("Budget", enabled: store.status == .running || store.status == .paused) {
                UISelectionFeedbackGenerator().selectionChanged(); showBudgetSheet = true
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 28)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }
}
```

> `DSButton` exists in `DesignSystem`; match its real initializer signature (`label`, `role`/`kind`, `enabled`, `action`) — adjust the calls above to the actual API when wiring. `BudgetSheet` is a small `View` with a numeric field + "Set cap" button; build it inline in this file following the `.presentationDetents([.medium])` + grabber pattern (R7.1).

- [ ] **Step 6: Wire navigation from Fleet**

In `FleetView.swift`, make each agent row a `NavigationLink` to `RunDetailView(channel: daemonChannel, runId: agent.runId, status: ...)`. Use the existing `DaemonChannel` the Fleet store already holds. Fire `UISelectionFeedbackGenerator().selectionChanged()` on tap.

- [ ] **Step 7: Build the app target (catches strict-concurrency breaks SPM misses)**

Run via XcodeBuildMCP `build_sim` (scheme Conduit) — per CLAUDE.md, the app build catches strict-concurrency issues `swift build` won't. Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add Packages/ConduitKit/Sources/AppFeature/RunDetailView.swift Packages/ConduitKit/Sources/AppFeature/RunControlStore.swift Packages/ConduitKit/Sources/AppFeature/FleetView.swift Packages/ConduitKit/Tests/AppFeatureTests/RunControlStoreTests.swift
git commit -m "feat(ios): Run Detail screen with stop/pause/resume/budget + haptics"
```

---

## Task 7: Audit trail for run-control (conduitd)

**Files:**
- Modify: `daemon/conduitd/dispatch.go`
- Test: `daemon/conduitd/dispatch_test.go`

Run-control actions must appear in the audit feed (the Activity tab shows them). The `dispatcher` methods currently don't audit.

- [ ] **Step 1: Write the failing test**

```go
func TestPauseIsAudited(t *testing.T) {
	var entries []AuditEntry
	d := newDispatcher()
	d.audit = func(e AuditEntry) { entries = append(entries, e) }
	d.launch = func(argv []string, cwd string) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/tmp", Prompt: "x"},
		func(ApprovalEvent) (string, string) { return "allow", "ok" }, func(AuditEntry) {})
	d.pause(res.RunID)
	found := false
	for _, e := range entries {
		if e.Action == "run-paused" {
			found = true
		}
	}
	if !found {
		t.Fatal("pause was not audited")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon/conduitd && go test -run TestPauseIsAudited ./...`
Expected: FAIL — `d.audit` field undefined.

- [ ] **Step 3: Write minimal implementation**

Add an optional `audit func(AuditEntry)` to `dispatcher` (defaults to no-op in `newDispatcher`), and call it in `pause`/`resume`/`cancel`/`enforceBudgets`:

```go
// in dispatcher struct:
	audit func(AuditEntry)

// in newDispatcher():
	return &dispatcher{runs: map[string]*dispatchRun{}, launch: realLauncher, audit: func(AuditEntry) {}}

// inside pause(), before `return true`:
	d.audit(AuditEntry{Action: "run-paused", Agent: run.Agent, Kind: "run-control", ApprovalID: runID})
```

Add the analogous `"run-resumed"`, `"run-stopped"`, and `"run-budget-exceeded"` audit calls in `resume`, `cancel`, and `enforceBudgets` respectively. Wire `s.dispatcher.audit` to the server's real audit sink wherever `newDispatcher()` is constructed in `server.go` (search for `newDispatcher(`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon/conduitd && go test ./... && go vet ./...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/dispatch.go daemon/conduitd/dispatch_test.go daemon/conduitd/server.go
git commit -m "feat(conduitd): audit run-control actions (pause/resume/stop/budget)"
```

---

## Self-review

**Spec coverage:** kill → Task 1 (`cancel` via handle) + existing `agent.cancel`; pause/resume → Tasks 1, 3, 4, 5, 6; set-budget → Tasks 2, 3, 4, 5, 6; UI surface → Task 6; auditability → Task 7. Nudge / model-switch are explicitly **out of scope** (deferred per the ledger) — no tasks, by design.

**Type consistency:** `procHandle{kill,pause,resume}`, `launchFunc → (*procHandle, error)`, `dispatchRun{Status, BudgetUSD, handle}`, RPCs `agent.pause`/`agent.resume`/`agent.budget.set` with results `{paused}`/`{resumed}`/`{ok}`, iOS `pauseRun`/`resumeRun`/`setRunBudget`/`stopRun`, `RunControlling`, `RunControlStore`, `RunStatus{running,paused,stopped,budgetExceeded}` — used identically across tasks.

**Placeholder scan:** real code in every code step. Two spots require matching an existing API at wiring time and are flagged inline, not left vague: the `server_test.go` helper names (`newTestServer`/`callRPC` — copy from the existing `agent.cancel` test) and `DSButton`'s exact initializer (match the real `DesignSystem` signature). Both are "match the existing pattern," not undefined behavior.

**Risk note:** SIGSTOP/SIGCONT are Unix-only; conduitd targets macOS/Linux hosts, so this is fine. Budget enforcement is event-driven (on `setSpentUSD` from the spend feed) — continuous polling/metering is a T1 concern, not duplicated here.
