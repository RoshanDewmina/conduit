# Governed Approvals (cross-vendor, decide-from-anywhere) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one defining App Store feature — a **cross-vendor governed approval inbox**: your AI coding agents (Claude Code, Codex, opencode) running on *your own* machine ask permission on your phone; you decide in one tap **even when the app was closed**; a policy you set auto-handles the safe 90%; every decision is logged to an audit trail; you can glance your fleet's status and spend.

**Architecture:** Three already-built layers — iOS app (`Packages/LancerKit/`, SwiftUI), the resident daemon `lancerd` (Go, on the dev's host), and the `push-backend` control plane (Go, APNs + relay). ~85% of this feature already exists and is wired; this plan **assembles, hardens, tests, and closes the two real gaps**: (1) a **backend decision-relay** so a tapped decision reaches `lancerd` with no live SSH session (today it silently queues until SSH reconnects, then lancerd times out and auto-denies), and (2) a **governance-first information architecture** (Inbox / Fleet / Activity at the top level; the terminal demoted to a power-user depth).

**Tech Stack:** Swift 6.2 / iOS 26 / SwiftUI (`@Observable`, actors, `AsyncStream`), GRDB, Citadel SSH; Go 1.22 (`lancerd`, `push-backend`, `agent-runner`); APNs (token auth, `.p8`); xcodegen; Swift Testing (`@Test`) + Go `testing`.

---

## 0. CONTEXT — read this before touching anything

You have **zero prior context** assumed. Read this whole section first. The canonical state-of-project briefing is `docs/LANCER_PROJECT_DOSSIER.md` — skim it. Architecture invariants you must not regress are in `docs/agent-contract.md` and `CLAUDE.md`.

### 0.1 What the product is
Lancer is an iOS app for **steering** AI coding agents that run on the developer's own computer/server. The phone is where you get notified an agent needs a decision, approve/deny/edit it, see what ran autonomously, and glance the fleet. A small Go daemon, **`lancerd`**, runs on the host: it intercepts each agent tool call (via the agent's PreToolUse hook), applies a **policy** (auto-allow safe / auto-deny dangerous / **ask** the human for the ambiguous), records an **audit log**, and survives SSH disconnects. The **`push-backend`** sends APNs alerts and (after this plan) relays decisions back.

### 0.2 The ONE feature this plan ships
**Cross-vendor Governed Approvals.** Everything else (fleet glance, activity feed) is a *supporting surface* that reuses data the daemon already produces. The defining, hard-to-copy claim: *one governed approval inbox across Claude Code + Codex + opencode, on your own host, with a policy that handles the boring 90% and an audit trail — and you can decide from your phone even when you're away.* First-party tools (Anthropic Remote Control, OpenAI Codex mobile) do single-vendor mobile approvals; none govern *across* vendors on *your* host with *your* policy and audit.

### 0.3 What already exists (DO NOT rebuild — verify and wire)
- **Wire protocol carries structured fields.** `ApprovalEvent` (Go, `daemon/lancerd/approval.go:10`) and `ApprovalPendingParams` (Swift, `Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift:49`) both carry `toolName`, `toolUseID`, `agentSessionID`, `toolInput`, plus `files`/`touchesGit`/`touchesNetwork`/`matchedRule` (blast radius). All three vendor hooks pass these (`docs/lancer-hook.sh`, `docs/codex-lancer-hook.sh`, `docs/opencode-lancer-hook.sh`).
- **Rich approval card UI.** `DSApprovalCard` (`Packages/LancerKit/Sources/DesignSystem/Components/ChatComponents.swift:150`) renders agent badge, risk badge, action sentence, host/path, command block, and DENY / ALLOW ALWAYS / EDIT & RUN / APPROVE actions. `DSBlastRadiusBanner` (`.../Components/DSBlastRadiusBanner.swift:1`) renders git/network/files. `InboxView` (`Packages/LancerKit/Sources/InboxFeature/InboxView.swift`) dispatches card-per-kind.
- **Decision round-trip (connected).** `LiveInboxViewModel.decide` → `DaemonChannel.respond(approvalId:decision:editedToolInput:)` (`Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift:116`) → lancerd `agent.approval.response` → `approvalStore.resolve` (`daemon/lancerd/approval.go:74`) → hook unblocks. `.approvedAlways` already maps to wire `"approveAlways"` and lancerd persists it to `~/.lancer/policy-always.yaml`.
- **Push (alert) path.** lancerd `postApprovalPush` POSTs to `push-backend /approval` (`daemon/lancerd/server.go:594`); `handleApproval` looks up the device token and calls `pushApproval` (APNs, token auth) (`daemon/push-backend/main.go:124,226`). iOS registers via `Notifications.registerDeviceToken` and `DaemonChannel.registerDevice` (`AppRoot.swift:963`); `LancerNotificationDelegate` handles lock-screen Approve/Reject actions (`Lancer/LancerApp.swift:99`), posting `.lancerApprovalAction`, observed in `AppRoot.swift:299`.
- **Audit feed view.** `BridgeAuditFeedView(entries:)` ("while you were away") exists (`Packages/LancerKit/Sources/InboxFeature/BridgeAuditFeedView.swift:7`); fed by `DaemonChannel.tailAudit` → `[AuditLogEntry]`.
- **Fleet store + cross-vendor status.** `FleetStore` (≤3 slots; `Packages/LancerKit/Sources/AppFeature/FleetStore.swift`) with `refreshBridgeStatus()`. Per-vendor status `AgentVendorStatus` (agent, loggedIn, model, sessionCount, usageUSD; `Packages/LancerKit/Sources/LancerCore/AgentStatusProtocol.swift:14`) is produced by lancerd `collectAgentStatus` for all three vendors (`daemon/lancerd/agent_status.go:29`).
- **Notification filtering type.** `NotificationFilter` (minRisk / enabledAgents / quiet hours; `Packages/LancerKit/Sources/NotificationsKit/Notifications.swift`).
- **Policy presets (iOS-side only).** `PolicyEditorView` has Strict/Balanced/Permissive YAML presets (`Packages/LancerKit/Sources/SettingsFeature/PolicyEditorView.swift`). lancerd has `DefaultDocument()` (`daemon/lancerd/policy/types.go:76`) but **no named presets**.

### 0.4 The two real gaps this plan closes
1. **Decide-while-away is unreliable (THE differentiator).** When the app isn't foreground-connected over SSH, a tapped decision is only written to the local DB and **queued in `ApprovalRelay`** (`Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift`); it reaches lancerd only when SSH reconnects. If that doesn't happen within lancerd's 120 s wait, lancerd **auto-denies**. Fix (Milestone 2): a backend decision-relay — phone POSTs the decision to `push-backend`; `lancerd` polls `push-backend` for decisions addressed to its session and resolves them. No live SSH required.
2. **Terminal-first IA.** Today's tabs are `hosts / inbox / library / settings` with the terminal as home (`Tab` enum, `AppRoot.swift:107`). The product is a governance cockpit. Fix (Milestone 6): top-level `Inbox / Fleet / Activity / Settings`; terminal reachable from a connected session, not a root tab.

### 0.5 Where things live (quick map)
- iOS package: `Packages/LancerKit/` (`swift build` / `swift test` from there). Targets under `Sources/`: `AppFeature`, `LancerCore`, `SSHTransport`, `AgentKit`, `InboxFeature`, `SettingsFeature`, `NotificationsKit`, `SessionFeature`, `DesignSystem`, …
- App shell (AppDelegate / entry): `Lancer/LancerApp.swift`. Xcode project generated by `xcodegen generate` from `project.yml`.
- Daemons: `daemon/lancerd/` (resident), `daemon/push-backend/` (control plane), `daemon/agent-runner/` (cloud runner — untouched here).
- Tests: `Packages/LancerKit/Tests/LancerKitTests/` (Swift), `daemon/*/**_test.go` (Go).
- Hooks: `docs/lancer-hook.sh`, `docs/codex-lancer-hook.sh`, `docs/opencode-lancer-hook.sh`.

### 0.6 Build & verify commands (use throughout)
- iOS engine build: `cd Packages/LancerKit && swift build`
- iOS engine tests: `cd Packages/LancerKit && swift test`
- Full app target (catches strict-concurrency breaks SPM misses): `mcp__XcodeBuildMCP__build_sim` (scheme `Lancer`); first call `mcp__XcodeBuildMCP__session_show_defaults` once.
- lancerd: `cd daemon/lancerd && go build ./... && go test ./...`
- push-backend: `cd daemon/push-backend && go test ./...`
- Project regen: `xcodegen generate`
- **Invariant:** zero new Swift 6 concurrency warnings; never edit two files from two agents at once; never commit to `master` (work on this branch `feat/product-depth-sprint` or a child).

### 0.7 Decisions already made (don't relitigate)
- **One feature = cross-vendor Governed Approvals**; Fleet + Activity are supporting surfaces.
- **Push is in v1** (alert-when-away). APNs delivery needs the paid Apple account + production `.p8` (owner action, Milestone 7/8). Engineering completes against a **mock APNs** path; the cert is an owner step.
- **All three vendors in v1** (already supported; this plan adds parity tests).
- **Decision-relay (Milestone 2) is the defining capability** and is on the critical path. If the owner wants an even faster *first* submission, Milestone 2 may be deferred and the App Store copy changed from "decide from anywhere" to "tap to open and decide" — see Milestone 8, Task 8.1 note. Default: include it.

### 0.8 Glossary (use these exact objects)
`Approval` (`LancerCore/Approval.swift`): `id, sessionID, agent (AgentSource: claudeCode|codex|opencode|cursor|devin|unknown), kind (Kind: command|patch|fileWrite|fileDelete|network|credential|browser|callMCP|askQuestion), command?, patch?, cwd, risk (Risk: low|medium|high|critical), decision? (Decision: approved|approvedAlways|rejected|expired), toolName?, toolUseID?, agentSessionID?, toolInput?, blastRadius?`. `AgentVendorStatus`: `agent, loggedIn?, model?, sessionCount, runningCount?, usageUSD?, usagePeriod?, displayName`. `AuditLogEntry`: `timestamp, action, agent?, kind?, command?, effect?, rule?, approvalId?`.

---

## Milestone 0 — Baseline & CI green (do first, serial)

**Goal:** prove the repo is green before changing anything, and capture the baseline numbers.

### Task 0.1: Capture green baseline

**Files:** none (verification only).

- [ ] **Step 1: Build + test the iOS engine**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -20`
Expected: `Build complete!` (no errors).

- [ ] **Step 2: Run the iOS engine test suite, record the count**

Run: `cd Packages/LancerKit && swift test 2>&1 | tail -25`
Expected: all tests pass. Record the number (e.g. "327 tests, 0 failures") in a scratch note — this is your regression floor.

- [ ] **Step 3: Build + test both daemons**

Run: `cd daemon/lancerd && go build ./... && go test ./... 2>&1 | tail -20`
Then: `cd daemon/push-backend && go build ./... && go test ./... 2>&1 | tail -20`
Expected: `ok` for each package; record counts.

- [ ] **Step 4: Confirm the app target builds (strict concurrency)**

Call `mcp__XcodeBuildMCP__session_show_defaults` once; if scheme/sim unset, `mcp__XcodeBuildMCP__session_set_defaults` (scheme `Lancer`, an installed simulator runtime). Then `mcp__XcodeBuildMCP__build_sim`.
Expected: build succeeds. If it fails on a missing watchOS runtime, build the iOS app target only and note it (known footgun — see `CLAUDE.md`).

- [ ] **Step 5: Commit a baseline marker (docs only)**

```bash
git checkout -b feat/governed-approvals
git commit --allow-empty -m "chore: baseline before governed-approvals milestone (engine N tests, lancerd M, push-backend K green)"
```

---

## Milestone 1 — Cross-vendor approval parity

**Goal:** prove (with tests) that a tool call from **each** of Claude Code, Codex, and opencode produces a structured approval that round-trips to a decision, and that the iOS approval card shows the structured fields. This makes the "cross-vendor" headline true and defended by tests.

### Task 1.1: Go test — all three vendor agents normalize into a structured `ApprovalEvent`

**Files:**
- Test: `daemon/lancerd/hook_parity_test.go` (create)

- [ ] **Step 1: Write the failing test**

```go
package main

import "testing"

// Each vendor's hook invokes `lancerd agent-hook` with the same flags; this
// asserts the agent name normalization + structured fields survive into an
// ApprovalEvent for all three vendors.
func TestAgentHookBuildsStructuredEventPerVendor(t *testing.T) {
	cases := []struct {
		agentFlag string
		wantAgent string
	}{
		{"claudeCode", "claudeCode"},
		{"codex", "codex"},
		{"opencode", "opencode"},
	}
	for _, tc := range cases {
		ev := buildApprovalEventForTest(
			tc.agentFlag, "command", "rm -rf build/", "/repo",
			"high", "Bash", "tool-use-123", "sess-9", `{"command":"rm -rf build/"}`,
		)
		if ev.Agent != tc.wantAgent {
			t.Fatalf("%s: agent = %q, want %q", tc.agentFlag, ev.Agent, tc.wantAgent)
		}
		if ev.ToolName != "Bash" || ev.ToolUseID != "tool-use-123" ||
			ev.SessionID != "sess-9" || ev.ToolInput == "" {
			t.Fatalf("%s: structured fields not carried: %+v", tc.agentFlag, ev)
		}
		if ev.Kind != "command" || ev.Risk != 2 {
			t.Fatalf("%s: kind/risk wrong: kind=%s risk=%d", tc.agentFlag, ev.Kind, ev.Risk)
		}
		if ev.ApprovalID == "" || ev.Timestamp == "" {
			t.Fatalf("%s: missing id/timestamp", tc.agentFlag)
		}
	}
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd daemon/lancerd && go test ./... -run TestAgentHookBuildsStructuredEventPerVendor 2>&1 | tail -15`
Expected: FAIL — `undefined: buildApprovalEventForTest`.

- [ ] **Step 3: Extract the event-building logic so it's testable**

In `daemon/lancerd/hook.go`, refactor the inline event construction (currently lines ~50–69 inside `runAgentHook`) into a small pure helper, and call it from `runAgentHook`. Add:

```go
// buildApprovalEventForTest constructs the ApprovalEvent exactly as runAgentHook
// does, but without any socket I/O — used by tests and by runAgentHook itself.
func buildApprovalEventForTest(agent, kind, command, cwd, risk, toolName, toolUseID, sessionID, toolInput string) ApprovalEvent {
	normalizedKind := normalizeKind(kind)
	patch := ""
	if normalizedKind == "patch" {
		patch = command
	}
	return ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      normalizeAgentSource(agent),
		Kind:       normalizedKind,
		Command:    command,
		Patch:      patch,
		CWD:        cwd,
		Risk:       riskToInt(risk),
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
		ToolName:   toolName,
		ToolUseID:  toolUseID,
		SessionID:  sessionID,
		ToolInput:  toolInput,
	}
}
```

Then replace the inline `event := ApprovalEvent{...}` in `runAgentHook` with:

```go
	event := buildApprovalEventForTest(*agent, *kind, *command, *cwd, *risk, *toolName, *toolUseID, *sessionID, *toolInput)
```

(`normalizeAgentSource`, `normalizeKind`, `riskToInt`, `newUUID` already exist in `hook.go`.)

- [ ] **Step 4: Run the test — expect PASS**

Run: `cd daemon/lancerd && go test ./... -run TestAgentHookBuildsStructuredEventPerVendor 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 5: Full daemon suite still green, then commit**

Run: `cd daemon/lancerd && go test ./... 2>&1 | tail -5`
Expected: `ok`.
```bash
git add daemon/lancerd/hook.go daemon/lancerd/hook_parity_test.go
git commit -m "test(lancerd): cross-vendor structured ApprovalEvent parity (claude/codex/opencode)"
```

### Task 1.2: Swift test — `ApprovalPendingParams` from each vendor maps to a rich `Approval`

**Files:**
- Test: `Packages/LancerKit/Tests/LancerKitTests/ApprovalParityTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import LancerCore

@Suite struct ApprovalParityTests {
    private func params(agent: String) -> ApprovalPendingParams {
        let json = """
        {"id":"\(UUID().uuidString)","sessionId":"\(UUID().uuidString)","agent":"\(agent)",
         "kind":"command","command":"rm -rf build/","cwd":"/repo","risk":2,
         "toolName":"Bash","toolUseID":"tu-1","agentSessionID":"as-1",
         "toolInput":"{\\"command\\":\\"rm -rf build/\\"}",
         "files":["build/"],"touchesGit":false,"touchesNetwork":false,"matchedRule":"ask-high"}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(ApprovalPendingParams.self, from: json)
    }

    @Test("Each vendor decodes to the correct AgentSource and carries structured fields")
    func vendorMapping() {
        for (raw, expected): (String, Approval.AgentSource) in [
            ("claudeCode", .claudeCode), ("codex", .codex), ("opencode", .opencode),
        ] {
            let p = params(agent: raw)
            #expect(p.approvalAgent == expected)
            #expect(p.approvalToolName == "Bash")
            #expect(p.approvalKind == .command)
            #expect(p.approvalRisk == .high)
            #expect(p.blastRadius.files == ["build/"])
            #expect(p.blastRadius.matchedRule == "ask-high")
        }
    }
}
```

- [ ] **Step 2: Run it — expect PASS or a precise failure**

Run: `cd Packages/LancerKit && swift test --filter ApprovalParityTests 2>&1 | tail -15`
Expected: PASS (the mapping computed-properties exist on `ApprovalPendingParams`). If it FAILS, the failure pinpoints a real decode bug to fix before proceeding — fix it, do not weaken the test.

- [ ] **Step 3: Commit**

```bash
git add Packages/LancerKit/Tests/LancerKitTests/ApprovalParityTests.swift
git commit -m "test(ios): cross-vendor ApprovalPendingParams → Approval mapping parity"
```

### Task 1.3: Approval card shows the tool name + diff affordance for patches

**Files:**
- Modify: `Packages/LancerKit/Sources/InboxFeature/InboxView.swift` (the `pendingCard(_:)` default branch, ~line 134–193 — the agent that mapped this file showed `DSApprovalCard(...)` is constructed here).

- [ ] **Step 1: Read the current default-branch construction**

Run: `cd Packages/LancerKit && grep -n "DSApprovalCard(" Sources/InboxFeature/InboxView.swift`
Read the surrounding `pendingCard` function so you match its existing argument wiring exactly.

- [ ] **Step 2: Ensure the card passes `onViewDiff` when a patch exists and surfaces the tool name in the action string**

In the default branch, where `DSApprovalCard(...)` is built, make these guarantees (adapt to the existing call — do not duplicate it):
- `action`: include the tool name when present, e.g. `approval.toolName.map { "run \($0)" } ?? defaultActionVerb(for: approval.kind)`. If a local `defaultActionVerb` helper does not exist, inline a `switch approval.kind` returning `"run a command"`, `"apply a patch"`, `"write a file"`, `"delete a file"`, `"make a network request"`, `"touch credentials"`, `"open a browser"`, `"call a tool"`, `"decide"`.
- `onViewDiff`: pass a non-nil closure **only** when `approval.patch != nil || approval.kind == .patch`, wiring it to the existing diff presentation the file already uses (search the file for an existing diff sheet/route; if none, set `onViewDiff` to a closure that sets a `@State var diffApproval: Approval?` you add, presented in a `.sheet(item:)` rendering the patch text in a `ScrollView { Text(approval.patch ?? "").font(.dsMonoPt(12)) }`).
- Keep `onAllowAlways`, `onEditAndRun`, `onDeny`, `onApprove` wired to the existing `viewModel.decide(...)` calls.

- [ ] **Step 3: Build the engine**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -8`
Expected: `Build complete!`.

- [ ] **Step 4: Visual check in the gallery**

Build+install+launch the inbox gallery route and screenshot:
`mcp__XcodeBuildMCP__build_sim` → `install_app_sim` → `launch_app_sim` with `env: { LANCER_GALLERY: "review" }` → `screenshot`.
Expected: an approval card shows the agent badge, a risk badge, an action line that names the tool, the command block, and (for a patch sample) a VIEW DIFF button. Confirm visually.

- [ ] **Step 5: Commit**

```bash
git add Packages/LancerKit/Sources/InboxFeature/InboxView.swift
git commit -m "feat(inbox): approval card names the tool and exposes View Diff for patches"
```

---

## Milestone 2 — Decide-from-anywhere (backend decision-relay) — THE defining capability

**Goal:** a decision tapped on the phone reaches `lancerd` and unblocks the agent **without a live SSH session**. Phone POSTs the decision to `push-backend`; `lancerd` polls `push-backend` for decisions addressed to its registered session and resolves them through the same path the SSH channel uses. This is what makes "decide from your phone, even when away" true.

### Task 2.1: push-backend — store phone-posted decisions, serve them to lancerd

**Files:**
- Create: `daemon/push-backend/decisions.go`
- Create (test): `daemon/push-backend/decisions_test.go`
- Modify: `daemon/push-backend/main.go` (register two routes in the mux)

- [ ] **Step 1: Write the failing test**

```go
package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDecisionRelayPostThenPoll(t *testing.T) {
	resetDecisionsForTest()

	// Phone posts a decision for an approval addressed to its session.
	body, _ := json.Marshal(map[string]string{
		"approvalId": "appr-1", "decision": "approve", "sessionId": "sess-A",
	})
	rec := httptest.NewRecorder()
	handlePostDecision(rec, httptest.NewRequest(http.MethodPost, "/approval/decision", bytes.NewReader(body)))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("post: status = %d, want 204", rec.Code)
	}

	// lancerd polls for that session; gets exactly one decision and it drains.
	rec2 := httptest.NewRecorder()
	handlePollDecisions(rec2, httptest.NewRequest(http.MethodGet, "/decisions?sessionId=sess-A", nil))
	if rec2.Code != http.StatusOK {
		t.Fatalf("poll: status = %d, want 200", rec2.Code)
	}
	var out struct {
		Decisions []decisionRecord `json:"decisions"`
	}
	_ = json.Unmarshal(rec2.Body.Bytes(), &out)
	if len(out.Decisions) != 1 || out.Decisions[0].ApprovalID != "appr-1" || out.Decisions[0].Decision != "approve" {
		t.Fatalf("poll returned %+v", out.Decisions)
	}

	// Second poll is empty (decisions drained on read).
	rec3 := httptest.NewRecorder()
	handlePollDecisions(rec3, httptest.NewRequest(http.MethodGet, "/decisions?sessionId=sess-A", nil))
	var out2 struct {
		Decisions []decisionRecord `json:"decisions"`
	}
	_ = json.Unmarshal(rec3.Body.Bytes(), &out2)
	if len(out2.Decisions) != 0 {
		t.Fatalf("second poll not empty: %+v", out2.Decisions)
	}
}

func TestDecisionРelayRejectsMissingFields(t *testing.T) {
	resetDecisionsForTest()
	body, _ := json.Marshal(map[string]string{"decision": "approve"}) // no approvalId/sessionId
	rec := httptest.NewRecorder()
	handlePostDecision(rec, httptest.NewRequest(http.MethodPost, "/approval/decision", bytes.NewReader(body)))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}
```

(Note: rename the second test function to `TestDecisionRelayRejectsMissingFields` — the Cyrillic `Р` above is a deliberate tripwire; use ASCII when you type it.)

- [ ] **Step 2: Run it — expect compile failure**

Run: `cd daemon/push-backend && go test ./... -run TestDecisionRelay 2>&1 | tail -15`
Expected: FAIL — `undefined: handlePostDecision`, `resetDecisionsForTest`, `decisionRecord`.

- [ ] **Step 3: Implement `decisions.go`**

```go
package main

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

// decisionRecord is a phone-posted approval decision awaiting pickup by the
// lancerd resident that owns the session. In-memory is sufficient: a decision
// only needs to outlive lancerd's ~120s approval wait.
type decisionRecord struct {
	ApprovalID      string `json:"approvalId"`
	Decision        string `json:"decision"` // approve | approveAlways | deny
	EditedToolInput string `json:"editedToolInput,omitempty"`
	SessionID       string `json:"sessionId"`
	CreatedAt       int64  `json:"createdAt"`
}

var decisions = struct {
	sync.Mutex
	bySession map[string][]decisionRecord
}{bySession: make(map[string][]decisionRecord)}

func resetDecisionsForTest() {
	decisions.Lock()
	decisions.bySession = make(map[string][]decisionRecord)
	decisions.Unlock()
}

// handlePostDecision: POST /approval/decision { approvalId, decision, sessionId, editedToolInput? }
func handlePostDecision(w http.ResponseWriter, r *http.Request) {
	var rec decisionRecord
	if err := json.NewDecoder(r.Body).Decode(&rec); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if rec.ApprovalID == "" || rec.SessionID == "" || rec.Decision == "" {
		http.Error(w, "approvalId, sessionId, decision required", http.StatusBadRequest)
		return
	}
	rec.CreatedAt = time.Now().Unix()
	decisions.Lock()
	decisions.bySession[rec.SessionID] = append(decisions.bySession[rec.SessionID], rec)
	decisions.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

// handlePollDecisions: GET /decisions?sessionId=... -> { decisions: [...] } and drains them.
func handlePollDecisions(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("sessionId")
	if sessionID == "" {
		http.Error(w, "sessionId required", http.StatusBadRequest)
		return
	}
	decisions.Lock()
	pending := decisions.bySession[sessionID]
	delete(decisions.bySession, sessionID)
	decisions.Unlock()
	if pending == nil {
		pending = []decisionRecord{}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"decisions": pending})
}
```

- [ ] **Step 4: Register the routes in `main.go`**

Find the mux setup (the agent located it at `daemon/push-backend/main.go:57-72`). Add alongside the existing `mux.HandleFunc("/approval", handleApproval)`:

```go
	mux.HandleFunc("/approval/decision", handlePostDecision)
	mux.HandleFunc("/decisions", handlePollDecisions)
```

- [ ] **Step 5: Run the tests — expect PASS**

Run: `cd daemon/push-backend && go test ./... -run TestDecisionRelay 2>&1 | tail -8`
Expected: PASS (both).

- [ ] **Step 6: Full push-backend suite green, commit**

Run: `cd daemon/push-backend && go test ./... 2>&1 | tail -5`
```bash
git add daemon/push-backend/decisions.go daemon/push-backend/decisions_test.go daemon/push-backend/main.go
git commit -m "feat(push-backend): decision relay — phone posts decision, lancerd polls"
```

### Task 2.2: lancerd — poll push-backend for decisions and resolve approvals

**Files:**
- Create: `daemon/lancerd/decision_poll.go`
- Create (test): `daemon/lancerd/decision_poll_test.go`
- Modify: `daemon/lancerd/server.go` (construct the poller; start it on `lancer.device.register`)

- [ ] **Step 1: Confirm the resolve signature and server fields**

Run: `cd daemon/lancerd && grep -n "func (s \*approvalStore) resolve" approval.go && grep -n "approvals \*approvalStore" server.go && grep -n "case \"lancer.device.register\"" server.go`
Expected: `resolve(id, decision, editedToolInput string) (ApprovalEvent, bool)`; `s.approvals`; the register case at ~`server.go:397`.

- [ ] **Step 2: Write the failing test**

```go
package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestDecisionPollerResolves(t *testing.T) {
	// Fake push-backend that serves one decision then empties.
	served := int32(0)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if atomic.AddInt32(&served, 1) == 1 {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"decisions": []map[string]string{
					{"approvalId": "a-1", "decision": "approve", "editedToolInput": ""},
				},
			})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"decisions": []any{}})
	}))
	defer srv.Close()

	got := make(chan [3]string, 1)
	resolve := func(id, decision, edited string) (ApprovalEvent, bool) {
		got <- [3]string{id, decision, edited}
		return ApprovalEvent{}, true
	}

	p := newDecisionPoller(resolve)
	p.pollIntervalForTest = 20 * time.Millisecond
	p.ensureRunning(srv.URL, "sess-A")
	defer p.stopForTest()

	select {
	case v := <-got:
		if v[0] != "a-1" || v[1] != "approve" {
			t.Fatalf("resolved with %+v", v)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("poller did not resolve the decision in time")
	}
}
```

- [ ] **Step 3: Run it — expect compile failure**

Run: `cd daemon/lancerd && go test ./... -run TestDecisionPollerResolves 2>&1 | tail -15`
Expected: FAIL — `undefined: newDecisionPoller`.

- [ ] **Step 4: Implement `decision_poll.go`**

```go
package main

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type backendDecision struct {
	ApprovalID      string `json:"approvalId"`
	Decision        string `json:"decision"`
	EditedToolInput string `json:"editedToolInput,omitempty"`
}

// decisionPoller pulls phone-posted decisions from push-backend and resolves the
// matching pending approvals — the path that works when no SSH client is attached.
type decisionPoller struct {
	resolve             func(id, decision, edited string) (ApprovalEvent, bool)
	pollIntervalForTest time.Duration

	mu      sync.Mutex
	running bool
	stop    chan struct{}
}

func newDecisionPoller(resolve func(id, decision, edited string) (ApprovalEvent, bool)) *decisionPoller {
	return &decisionPoller{resolve: resolve}
}

func (p *decisionPoller) interval() time.Duration {
	if p.pollIntervalForTest > 0 {
		return p.pollIntervalForTest
	}
	return 3 * time.Second
}

// ensureRunning starts the poll loop once for a given backend URL + session.
func (p *decisionPoller) ensureRunning(backendURL, sessionID string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running || backendURL == "" || sessionID == "" {
		return
	}
	p.running = true
	p.stop = make(chan struct{})
	go p.loop(backendURL, sessionID, p.stop)
}

func (p *decisionPoller) stopForTest() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running {
		close(p.stop)
		p.running = false
	}
}

func (p *decisionPoller) loop(backendURL, sessionID string, stop chan struct{}) {
	ticker := time.NewTicker(p.interval())
	defer ticker.Stop()
	endpoint := strings.TrimRight(backendURL, "/") + "/decisions?sessionId=" + url.QueryEscape(sessionID)
	client := &http.Client{Timeout: 10 * time.Second}
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			resp, err := client.Get(endpoint)
			if err != nil {
				continue
			}
			var body struct {
				Decisions []backendDecision `json:"decisions"`
			}
			_ = json.NewDecoder(resp.Body).Decode(&body)
			resp.Body.Close()
			for _, d := range body.Decisions {
				p.resolve(d.ApprovalID, d.Decision, d.EditedToolInput)
			}
		}
	}
}
```

- [ ] **Step 5: Run the test — expect PASS**

Run: `cd daemon/lancerd && go test ./... -run TestDecisionPollerResolves 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 6: Wire the poller into the server**

In `daemon/lancerd/server.go`: add a field to `server` and construct the poller wherever `newServer`/`&server{...}` is built (grep `func newServer` or `&server{`), passing `s.approvals.resolve`:

```go
// add to type server struct { ... }
	poller *decisionPoller
```
```go
// where the server is constructed, after s.approvals is set:
	s.poller = newDecisionPoller(s.approvals.resolve)
```

Then in the `lancer.device.register` case (after `s.device = &info` / unlock), start polling:

```go
		s.poller.ensureRunning(info.PushBackendURL, info.SessionID)
```

- [ ] **Step 7: Build + full suite + commit**

Run: `cd daemon/lancerd && go build ./... && go test ./... 2>&1 | tail -8`
Expected: `ok`.
```bash
git add daemon/lancerd/decision_poll.go daemon/lancerd/decision_poll_test.go daemon/lancerd/server.go
git commit -m "feat(lancerd): poll push-backend for phone decisions; resolve without live SSH"
```

### Task 2.3: iOS — post decisions to the backend when no live channel

**Files:**
- Modify: `Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift`
- Create (test): `Packages/LancerKit/Tests/LancerKitTests/ApprovalRelayBackendTests.swift`
- Modify: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` (configure the relay with backend URL + session id)

- [ ] **Step 1: Write the failing test (build the POST body deterministically)**

```swift
import Testing
import Foundation
@testable import SessionFeature
@testable import LancerCore

@Suite struct ApprovalRelayBackendTests {
    @Test("Backend decision POST body has approvalId, decision wire value, sessionId")
    func postBody() throws {
        let data = ApprovalRelay.backendDecisionBody(
            approvalID: "appr-7",
            decision: .approvedAlways,
            sessionID: "sess-A",
            editedToolInput: nil
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["approvalId"] as? String == "appr-7")
        #expect(obj["decision"] as? String == "approveAlways")
        #expect(obj["sessionId"] as? String == "sess-A")
        #expect(obj["editedToolInput"] == nil)
    }
}
```

- [ ] **Step 2: Run it — expect compile failure**

Run: `cd Packages/LancerKit && swift test --filter ApprovalRelayBackendTests 2>&1 | tail -12`
Expected: FAIL — `backendDecisionBody` not found.

- [ ] **Step 3: Implement the body builder + backend POST in `ApprovalRelay`**

Add to `ApprovalRelay` (it is `@MainActor public final class`):

```swift
    /// Backend coordinates for posting decisions when no DaemonChannel is attached.
    private var backendURL: String = ""
    private var sessionID: String = ""

    public func configureBackend(url: String, sessionID: String) {
        self.backendURL = url
        self.sessionID = sessionID
    }

    /// Pure builder so the wire shape is unit-testable.
    public static func backendDecisionBody(
        approvalID: String,
        decision: Approval.Decision,
        sessionID: String,
        editedToolInput: String?
    ) -> Data {
        var obj: [String: Any] = [
            "approvalId": approvalID,
            "decision": DaemonChannel.decisionWireValue(for: decision),
            "sessionId": sessionID,
        ]
        if let edited = editedToolInput, !edited.isEmpty { obj["editedToolInput"] = edited }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private func postDecisionToBackend(approvalID: String, decision: Approval.Decision, editedToolInput: String?) async {
        guard !backendURL.isEmpty, !sessionID.isEmpty,
              let url = URL(string: backendURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/approval/decision")
        else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.backendDecisionBody(
            approvalID: approvalID, decision: decision, sessionID: sessionID, editedToolInput: editedToolInput
        )
        _ = try? await URLSession.shared.data(for: req)
    }
```

`ApprovalRelay.swift` imports `SSHTransport`? It already imports `SSHTransport` (it references `DaemonChannel`). `DaemonChannel.decisionWireValue` is `public static`. Good.

Now change the `else` branch in `enqueue(...)` (the "channel not yet available" path) from only queueing to **both** posting to the backend and queueing as the fallback:

```swift
        if let ch = channel {
            try? await ch.respond(approvalId: approvalID, decision: decision)
        } else {
            // No live SSH channel: deliver via the backend relay so lancerd can
            // resolve it without us reconnecting; also queue as a belt-and-suspenders
            // drain for the next SSH attach.
            await postDecisionToBackend(approvalID: approvalID, decision: decision, editedToolInput: nil)
            queue.append((approvalID: approvalID, decision: decision))
        }
```

- [ ] **Step 4: Run the unit test — expect PASS**

Run: `cd Packages/LancerKit && swift test --filter ApprovalRelayBackendTests 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 5: Configure the relay from AppRoot**

In `AppRoot.swift`, in `startSession(host:env:)` right after `await ApprovalRelay.shared.setChannel(channel)` (~line 968), and also once at app configuration, set the backend coordinates so the away-path works even before any channel:

```swift
                await ApprovalRelay.shared.configureBackend(url: backendURL, sessionID: deviceSessionID)
```

Also call it in `configureCloudServices(env:)` (~line 799) so the relay has the URL + a stable session id even when no session has started:

```swift
        await ApprovalRelay.shared.configureBackend(
            url: url,
            sessionID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
```

- [ ] **Step 6: Route the in-app/global inbox decision through the relay when disconnected**

In `configureGlobalInbox(env:)` (`AppRoot.swift:542`), the `onDecision` closure forwards to `slot.channel.respond` or `self.daemonChannel`. Add a final fallback when neither exists:

```swift
            // No connected channel anywhere → deliver via the backend relay.
            await ApprovalRelay.shared.enqueue(
                approvalID: id.uuidString,
                decision: decision,
                db: env.database,
                hostID: ""    // unknown host at global scope; audit records the decision regardless
            )
```
Place this after the existing `self.daemonChannel` branch (so connected paths still win).

- [ ] **Step 7: Build engine + app target**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -8` (expect `Build complete!`)
Then `mcp__XcodeBuildMCP__build_sim` (expect success; zero new concurrency warnings).

- [ ] **Step 8: Commit**

```bash
git add Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift Packages/LancerKit/Sources/AppFeature/AppRoot.swift Packages/LancerKit/Tests/LancerKitTests/ApprovalRelayBackendTests.swift
git commit -m "feat(ios): post approval decisions to backend relay when no live SSH channel"
```

### Task 2.4: Document the new relay flow

**Files:**
- Modify: `docs/lancerd-resident.md` (add a "Decision relay" subsection)

- [ ] **Step 1: Append the section**

Add at the end of `docs/lancerd-resident.md`:

```markdown
## Decision relay (decide while detached)

When the phone is not attached over SSH, approval decisions reach the resident via push-backend instead of the framed socket:

1. lancerd escalates → `postApprovalPush` POSTs `/approval` (APNs alert) AND the poller is already running (started at `lancer.device.register`).
2. The phone POSTs `POST /approval/decision { approvalId, decision, sessionId, editedToolInput? }`.
3. lancerd's `decisionPoller` GETs `/decisions?sessionId=…` every ~3s, draining decisions, and calls `approvalStore.resolve` — unblocking the waiting hook with no SSH session.
4. The SSH framed `agent.approval.response` path still works when attached; `resolve` is idempotent (first caller wins).

In-memory on the backend is sufficient — a decision only needs to outlive lancerd's 120 s approval wait.
```

- [ ] **Step 2: Commit**

```bash
git add docs/lancerd-resident.md
git commit -m "docs: describe the lancerd↔push-backend decision relay"
```

---

## Milestone 3 — Governed policy presets (the "governed" half)

**Goal:** named presets (`cautious` / `balanced` / `bypass`) that exist on the **bridge** (so autonomy is real and consistent), plus a one-tap autonomy quick-set in the app that pushes the chosen preset YAML to lancerd. Today presets are iOS-side strings only; this makes them first-class and tested.

### Task 3.1: lancerd — named preset documents

**Files:**
- Modify: `daemon/lancerd/policy/types.go` (add `PresetDocument(name)`)
- Create (test): `daemon/lancerd/policy/presets_test.go`

- [ ] **Step 1: Write the failing test**

```go
package policy

import "testing"

func TestPresetDocuments(t *testing.T) {
	for _, name := range []string{"cautious", "balanced", "bypass"} {
		doc, ok := PresetDocument(name)
		if !ok {
			t.Fatalf("preset %q not found", name)
		}
		if doc.Default == "" {
			t.Fatalf("preset %q has empty default", name)
		}
	}
	// cautious must deny network + credentials.
	c, _ := PresetDocument("cautious")
	if !hasDenyKind(c, "network") || !hasDenyKind(c, "credential") {
		t.Fatalf("cautious must deny network+credential: %+v", c.Rules)
	}
	// bypass auto-allows low-risk commands.
	b, _ := PresetDocument("bypass")
	if !hasEffectKind(b, "allow", "command") {
		t.Fatalf("bypass must allow commands: %+v", b.Rules)
	}
	if _, ok := PresetDocument("nope"); ok {
		t.Fatal("unknown preset should return ok=false")
	}
}

func hasDenyKind(d Document, kind string) bool {
	for _, r := range d.Rules {
		if r.Effect == "deny" && r.Kind == kind {
			return true
		}
	}
	return false
}
func hasEffectKind(d Document, effect, kind string) bool {
	for _, r := range d.Rules {
		if r.Effect == effect && r.Kind == kind {
			return true
		}
	}
	return false
}
```

- [ ] **Step 2: Run it — expect compile failure**

Run: `cd daemon/lancerd && go test ./policy/ -run TestPresetDocuments 2>&1 | tail -12`
Expected: FAIL — `undefined: PresetDocument`.

- [ ] **Step 3: Implement `PresetDocument`**

Add to `daemon/lancerd/policy/types.go`:

```go
// PresetDocument returns a named, human-recognizable policy preset. These map 1:1
// to the iOS autonomy quick-set. Unknown names return ok=false.
func PresetDocument(name string) (Document, bool) {
	switch name {
	case "cautious":
		return Document{
			Default: string(EffectAsk),
			Rules: []Rule{
				{ID: "deny-credential", Effect: "deny", Kind: "credential"},
				{ID: "deny-network", Effect: "deny", Kind: "network"},
				{ID: "deny-critical", Effect: "deny", MinRisk: "critical"},
				{ID: "deny-high", Effect: "deny", MinRisk: "high"},
				{ID: "ask-rest", Effect: "ask"},
			},
		}, true
	case "balanced":
		return DefaultDocument(), true
	case "bypass":
		return Document{
			Default: string(EffectAsk),
			Rules: []Rule{
				{ID: "deny-credential", Effect: "deny", Kind: "credential"},
				{ID: "deny-network", Effect: "deny", Kind: "network"},
				{ID: "deny-critical", Effect: "deny", MinRisk: "critical"},
				{ID: "allow-command", Effect: "allow", Kind: "command", MaxRisk: "high"},
				{ID: "allow-patch", Effect: "allow", Kind: "patch"},
				{ID: "allow-write", Effect: "allow", Kind: "fileWrite"},
				{ID: "ask-rest", Effect: "ask"},
			},
		}, true
	default:
		return Document{}, false
	}
}
```

- [ ] **Step 4: Run the test — expect PASS, then full suite**

Run: `cd daemon/lancerd && go test ./policy/ -run TestPresetDocuments 2>&1 | tail -6` (expect PASS)
Run: `cd daemon/lancerd && go test ./... 2>&1 | tail -5` (expect `ok`)

- [ ] **Step 5: Commit**

```bash
git add daemon/lancerd/policy/types.go daemon/lancerd/policy/presets_test.go
git commit -m "feat(lancerd): named policy presets (cautious/balanced/bypass)"
```

### Task 3.2: iOS — autonomy quick-set pushes a preset to the bridge

**Files:**
- Modify: `Packages/LancerKit/Sources/SettingsFeature/PolicyEditorView.swift` (map preset names → the existing YAML constants; align to cautious/balanced/bypass labels)
- Verify wiring through the existing `BridgeSessionActions.savePolicyYAML` / `reloadPolicy` already surfaced in `AppRoot.bridgeSessionActions()` (`AppRoot.swift:570`).

- [ ] **Step 1: Align the three preset buttons to the bridge preset names and push-on-tap**

In `PolicyEditorView`, the three preset buttons currently only set `yamlText`. Rename their labels to **Cautious**, **Balanced**, **Bypass** to match the bridge presets (keep the existing YAML string constants as the bodies; `balancedPreset` ↔ Balanced, `strictPreset` ↔ Cautious, `permissivePreset` ↔ Bypass), and after setting `yamlText`, if `onSave` is present, immediately save+reload so the autonomy change reaches the host:

```swift
            Section("Autonomy preset") {
                Button("Cautious — ask on writes, deny network & secrets") { applyPreset(Self.strictPreset) }
                Button("Balanced — fail-closed ask (recommended)") { applyPreset(Self.balancedPreset) }
                Button("Bypass — auto-allow most, still deny secrets/network") { applyPreset(Self.permissivePreset) }
            }
```

Add the helper:

```swift
    private func applyPreset(_ yaml: String) {
        yamlText = yaml
        guard let onSave else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await onSave(yaml)
                statusMessage = "Autonomy updated on the bridge."
            } catch {
                statusMessage = "Couldn't reach the bridge — preset staged but not saved."
            }
        }
    }
```

- [ ] **Step 2: Build the engine**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -8`
Expected: `Build complete!`.

- [ ] **Step 3: Visual check**

Launch the policy editor surface (it's reachable from Settings via `PolicyEditorBridgeScreen`; for a quick visual, the gallery may have a `cc-policy`-style route — grep `DebugGalleryView.swift` for a policy route, else screenshot the Settings → Edit bridge policy path with a connected mock). Confirm three clearly-labeled autonomy presets and a status line.

- [ ] **Step 4: Commit**

```bash
git add Packages/LancerKit/Sources/SettingsFeature/PolicyEditorView.swift
git commit -m "feat(ios): autonomy presets (Cautious/Balanced/Bypass) push to the bridge on tap"
```

---

## Milestone 4 — Activity ("while you were away") as a real surface + notification filtering

**Goal:** surface the autonomous-decision audit feed and let the user mute by risk/agent/quiet-hours. The view (`BridgeAuditFeedView`) and filter type (`NotificationFilter`) already exist; this wires a load path and a filter UI, with a test on the filter logic.

### Task 4.1: Test the notification filter's decision logic

**Files:**
- Create (test): `Packages/LancerKit/Tests/LancerKitTests/NotificationFilterTests.swift`

- [ ] **Step 1: Write the failing/￼characterization test**

```swift
import Testing
@testable import NotificationsKit
@testable import LancerCore

@Suite struct NotificationFilterTests {
    @Test("minRisk gates low-risk approvals")
    func minRisk() {
        var f = NotificationFilter()
        f.minRisk = .high
        #expect(f.shouldDeliver(risk: .low, agent: .claudeCode) == false)
        #expect(f.shouldDeliver(risk: .high, agent: .claudeCode) == true)
        #expect(f.shouldDeliver(risk: .critical, agent: .codex) == true)
    }

    @Test("enabledAgents whitelist excludes others")
    func agents() {
        var f = NotificationFilter()
        f.enabledAgents = ["claudeCode"]
        #expect(f.shouldDeliver(risk: .high, agent: .claudeCode) == true)
        #expect(f.shouldDeliver(risk: .high, agent: .codex) == false)
    }
}
```

- [ ] **Step 2: Run it**

Run: `cd Packages/LancerKit && swift test --filter NotificationFilterTests 2>&1 | tail -10`
Expected: PASS (the logic exists). If a case FAILS, it's a real bug — fix `shouldDeliver`, keep the test.

- [ ] **Step 3: Commit**

```bash
git add Packages/LancerKit/Tests/LancerKitTests/NotificationFilterTests.swift
git commit -m "test(ios): notification filter risk/agent gating"
```

### Task 4.2: Activity screen that loads the bridge audit tail

**Files:**
- Create: `Packages/LancerKit/Sources/InboxFeature/ActivityView.swift`
- (Uses existing `BridgeAuditFeedView`, `BridgeSessionActions.tailAudit`, `AuditLogEntry`.)

- [ ] **Step 1: Create `ActivityView`**

```swift
#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

/// "While you were away" — the autonomous decisions lancerd made for you.
/// Loads the bridge audit tail via BridgeSessionActions; degrades gracefully
/// when no bridge is connected.
public struct ActivityView: View {
    private let actions: BridgeSessionActions
    @State private var entries: [AuditLogEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @Environment(\.lancerTokens) private var t

    public init(actions: BridgeSessionActions) {
        self.actions = actions
    }

    public var body: some View {
        List {
            if let loadError {
                Section { Text(loadError).font(.caption).foregroundStyle(t.text3) }
            }
            Section {
                BridgeAuditFeedView(entries: entries)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .overlay { if isLoading && entries.isEmpty { ProgressView() } }
        .task { await load() }
    }

    private func load() async {
        guard actions.isConnected, let tail = actions.tailAudit else {
            loadError = "Connect to a host to see what your agents did while you were away."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await tail(100)
            loadError = entries.isEmpty ? nil : nil
        } catch {
            loadError = "Couldn't load activity from the bridge."
        }
    }
}
#endif
```

Note: confirm `BridgeSessionActions` exposes `isConnected: Bool` and `tailAudit: ((Int) async throws -> [AuditLogEntry])?` (the agent report showed `tailAudit` wired in `AppRoot.bridgeSessionActions()`). If property names differ, grep `Sources/LancerCore/BridgeSessionActions.swift` and adapt.

- [ ] **Step 2: Build**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -8`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Packages/LancerKit/Sources/InboxFeature/ActivityView.swift
git commit -m "feat(ios): Activity (while-you-were-away) screen over bridge audit tail"
```

---

## Milestone 5 — Fleet glance (cross-vendor status + spend)

**Goal:** a top-level surface that shows, across all connected hosts/vendors, each agent's status and today's spend, plus an aggregate strip. Data comes from `FleetStore` + `AgentStatusSnapshot` (already produced for all three vendors). Includes a pure-logic test for the aggregation.

### Task 5.1: Fleet aggregation helper (testable)

**Files:**
- Create: `Packages/LancerKit/Sources/LancerCore/FleetSummary.swift`
- Create (test): `Packages/LancerKit/Tests/LancerKitTests/FleetSummaryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import LancerCore

@Suite struct FleetSummaryTests {
    @Test("aggregates vendor count, logged-in, and total spend")
    func summary() {
        let snaps = [
            AgentStatusSnapshot(agents: [
                AgentVendorStatus(agent: "claudeCode", loggedIn: true, model: "claude-sonnet-4.6", sessionCount: 2, usageUSD: 3.18),
                AgentVendorStatus(agent: "codex", loggedIn: true, model: "gpt-5.1-codex", sessionCount: 1, usageUSD: 0.74),
                AgentVendorStatus(agent: "opencode", loggedIn: false, sessionCount: 0),
            ]),
            AgentStatusSnapshot(agents: [
                AgentVendorStatus(agent: "claudeCode", loggedIn: true, model: "claude-opus", sessionCount: 1, usageUSD: 1.10),
            ]),
        ]
        let s = FleetSummary(snapshots: snaps)
        #expect(s.loggedInVendors == 2)         // claudeCode + codex distinct, logged in
        #expect(s.activeSessions == 4)          // 2+1+0 + 1
        #expect(abs(s.totalSpendUSD - 5.02) < 0.001)
    }
}
```

- [ ] **Step 2: Run it — expect compile failure**

Run: `cd Packages/LancerKit && swift test --filter FleetSummaryTests 2>&1 | tail -12`
Expected: FAIL — `FleetSummary` not found.

- [ ] **Step 3: Implement `FleetSummary`**

```swift
import Foundation

/// Aggregate glance across all connected bridges' agent-status snapshots.
public struct FleetSummary: Sendable, Equatable {
    public let loggedInVendors: Int
    public let activeSessions: Int
    public let totalSpendUSD: Double

    public init(snapshots: [AgentStatusSnapshot]) {
        var loggedIn = Set<String>()
        var sessions = 0
        var spend = 0.0
        for snap in snapshots {
            for a in snap.agents {
                if a.loggedIn == true { loggedIn.insert(a.agent) }
                sessions += a.sessionCount
                spend += a.usageUSD ?? 0
            }
        }
        self.loggedInVendors = loggedIn.count
        self.activeSessions = sessions
        self.totalSpendUSD = spend
    }
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `cd Packages/LancerKit && swift test --filter FleetSummaryTests 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LancerKit/Sources/LancerCore/FleetSummary.swift Packages/LancerKit/Tests/LancerKitTests/FleetSummaryTests.swift
git commit -m "feat(core): FleetSummary aggregation across bridge status snapshots"
```

### Task 5.2: Fleet screen

**Files:**
- Create: `Packages/LancerKit/Sources/AppFeature/FleetView.swift`
- (Uses `FleetStore`, `AgentVendorStatus`, `FleetSummary`, DesignSystem.)

- [ ] **Step 1: Create `FleetView`**

```swift
#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

/// Cross-vendor fleet glance: per-agent status + spend, with an aggregate strip.
/// The "is everything okay / what's it costing" surface.
public struct FleetView: View {
    private let store: FleetStore
    private let onConnectHost: () -> Void
    @State private var summary = FleetSummary(snapshots: [])

    @Environment(\.lancerTokens) private var t

    public init(store: FleetStore, onConnectHost: @escaping () -> Void) {
        self.store = store
        self.onConnectHost = onConnectHost
    }

    public var body: some View {
        List {
            Section {
                summaryStrip
            }
            if store.slots.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No agents connected", systemImage: "server.rack")
                    } description: {
                        Text("Connect a host running lancerd to see your agents, their status, and spend.")
                    } actions: {
                        Button("Connect a host", action: onConnectHost)
                    }
                }
            } else {
                ForEach(store.slots) { slot in
                    Section(slot.hostName) {
                        if let snap = slot.bridgeStatus {
                            ForEach(snap.agents) { agent in
                                agentRow(agent)
                            }
                        } else {
                            Text("Refreshing…").font(.caption).foregroundStyle(t.text3)
                        }
                    }
                }
            }
        }
        .navigationTitle("Fleet")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var summaryStrip: some View {
        HStack(spacing: 16) {
            stat("\(summary.loggedInVendors)", "vendors")
            stat("\(summary.activeSessions)", "sessions")
            stat(String(format: "$%.2f", summary.totalSpendUSD), "today")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.dsMonoPt(16)).foregroundStyle(t.text)
            Text(label).font(.caption2).foregroundStyle(t.text3)
        }
    }

    private func agentRow(_ a: AgentVendorStatus) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.displayName).font(.dsSansPt(14)).foregroundStyle(t.text)
                Text(a.model ?? (a.loggedIn == true ? "logged in" : "not logged in"))
                    .font(.dsMonoPt(11)).foregroundStyle(t.text3)
            }
            Spacer()
            if let usd = a.usageUSD {
                Text(String(format: "$%.2f", usd)).font(.dsMonoPt(12)).foregroundStyle(t.text2)
            }
            Circle()
                .fill(a.loggedIn == true ? t.ok : t.text4)
                .frame(width: 8, height: 8)
        }
    }

    private func refresh() async {
        await store.refreshBridgeStatus()
        summary = FleetSummary(snapshots: store.slots.compactMap(\.bridgeStatus))
    }
}
#endif
```

- [ ] **Step 2: Build**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -8`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Packages/LancerKit/Sources/AppFeature/FleetView.swift
git commit -m "feat(ios): Fleet glance — cross-vendor agent status + spend"
```

---

## Milestone 6 — Information architecture reset (governance cockpit)

**Goal:** make the app open into the governance product. New top-level tabs: **Inbox / Fleet / Activity / Settings**. "Hosts" folds into Fleet's connect path; the terminal stays reachable from a connected session (already a `fullScreenCover`), not a root tab. Library/snippets move under Settings.

> This changes a working app's navigation. Do it as one focused milestone, verify each tab renders, and keep the terminal entry intact.

### Task 6.1: Redefine the `Tab` enum

**Files:**
- Modify: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` (the `Tab` enum at ~line 107, the `compactRoot` tab items at ~line 599, and `tabContent`/`rootDestination`).

- [ ] **Step 1: Replace the `Tab` cases**

Change `public enum Tab` to:

```swift
public enum Tab: Hashable, Sendable {
    case inbox
    case fleet
    case activity
    case settings

    static let rootTabs: [Tab] = [.inbox, .fleet, .activity, .settings]

    var title: String {
        switch self {
        case .inbox:    "Inbox"
        case .fleet:    "Fleet"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox:    "tray"
        case .fleet:    "square.stack.3d.up"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gear"
        }
    }
}
```

- [ ] **Step 2: Update the tab bar items + binding in `compactRoot`**

In `compactRoot`, replace the `tabItems` array and the `tabID` get/set mapping to use `inbox / fleet / activity / settings` (mirror the existing structure exactly, swapping `hosts`→`fleet` and `library`→`activity`):

```swift
    let tabItems: [DSTabItem] = [
        DSTabItem(id: "inbox",    icon: .inbox,    label: "Inbox", badge: inboxBadge),
        DSTabItem(id: "fleet",    icon: .server,   label: "Fleet"),
        DSTabItem(id: "activity", icon: .list,     label: "Activity"),
        DSTabItem(id: "settings", icon: .settings, label: "Settings"),
    ]
```
…and the `tabID` Binding get/set switch over the same four ids (default → `.inbox`).

- [ ] **Step 3: Update `tabContent` and `rootDestination` to the new cases**

In `tabContent`, switch over `.inbox/.fleet/.activity/.settings`. In `rootDestination(_:env:)`:
- `.inbox`: the existing inbox content (unchanged).
- `.fleet`: `FleetView(store: fleetStore, onConnectHost: { addHostPresented = true })`.
- `.activity`: `ActivityView(actions: bridgeSessionActions())`.
- `.settings`: the existing `SettingsView(...)` (unchanged) — add a "Library" / "Snippets" / "SSH Keys" / "Hosts" navigation section here if those were only reachable from the old `library`/`hosts` tabs (grep how `library` rendered and move that destination under Settings).

- [ ] **Step 4: Set the launch tab to `.inbox`**

Find where `selectedTab` is initialized (default was likely `.hosts`); set the default to `.inbox`. Also update any `selectedTab = .hosts` assignments left over from session start (e.g. `AppRoot.swift:937`) to `.fleet` (so after connecting you land on the fleet, where the new session shows) — confirm with a grep `selectedTab = .hosts` and change each to a sensible new case (`.fleet`).

- [ ] **Step 5: Build engine + app target**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -8` (expect complete)
Then `mcp__XcodeBuildMCP__build_sim` (expect success).

- [ ] **Step 6: Verify each tab renders in the simulator**

`build_sim` → `install_app_sim` → `launch_app_sim` (no gallery env, real app) → `screenshot`. Then drive the tab bar with `mcp__ios-simulator__ui_describe_all` / `ui_tap` to switch Inbox → Fleet → Activity → Settings, screenshotting each. Expected: four tabs, Inbox is home, Fleet shows the empty-state "Connect a host", Activity shows its empty state, Settings reachable. Confirm the terminal is still reachable: connect to a host (or mock) and confirm the live-session `fullScreenCover` still opens.

- [ ] **Step 7: Commit**

```bash
git add Packages/LancerKit/Sources/AppFeature/AppRoot.swift
git commit -m "feat(ios): governance-first IA — Inbox/Fleet/Activity/Settings; terminal demoted to session depth"
```

### Task 6.2: Update the onboarding end-state to land on Inbox

**Files:**
- Modify: `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` (onboarding `onContinue` / provisioning `onComplete` set `selectedTab`).

- [ ] **Step 1: Point onboarding completion at the new tabs**

In `readyRoot(env:)`, the onboarding `onContinue` sets `selectedTab = .hosts`; change to `.fleet` (so the user sees their host connect there) and keep `addHostPresented = true`. The provisioning `onComplete` similarly: `selectedTab = .fleet`.

- [ ] **Step 2: Build + commit**

Run: `cd Packages/LancerKit && swift build 2>&1 | tail -6`
```bash
git add Packages/LancerKit/Sources/AppFeature/AppRoot.swift
git commit -m "feat(ios): onboarding lands on Fleet after first host connect"
```

---

## Milestone 7 — Push end-to-end (alert when away)

**Goal:** prove the push alert path with a mock APNs server (no cert needed), and document the owner steps for the real `.p8`. The wiring (register token → lancerd POST `/approval` → backend `pushApproval`) already exists; this hardens and tests it.

### Task 7.1: push-backend — test the approval push payload with an injectable sender

**Files:**
- Modify: `daemon/push-backend/main.go` (make the APNs send function a package var so tests can swap it)
- Create (test): `daemon/push-backend/approval_push_test.go`

- [ ] **Step 1: Make the sender injectable**

In `main.go`, introduce a package-level indirection so tests can intercept without real APNs:

```go
// pushApprovalFn is the seam tests swap to avoid real APNs calls.
var pushApprovalFn = pushApproval
```
Then in `handleApproval`, call `pushApprovalFn(token, ev)` instead of `pushApproval(token, ev)`.

- [ ] **Step 2: Write the failing test**

```go
package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandleApprovalRoutesToRegisteredToken(t *testing.T) {
	// Register a token for the session.
	registry.Lock()
	registry.tokens["sess-A"] = "device-token-xyz"
	registry.Unlock()

	var gotToken string
	var gotEvent approvalEvent
	orig := pushApprovalFn
	pushApprovalFn = func(token string, ev approvalEvent) error {
		gotToken = token
		gotEvent = ev
		return nil
	}
	defer func() { pushApprovalFn = orig }()

	body, _ := json.Marshal(approvalEvent{
		ID: "appr-1", SessionID: "sess-A", Command: "rm -rf build/", Risk: "high", HostName: "devbox",
	})
	rec := httptest.NewRecorder()
	handleApproval(rec, httptest.NewRequest(http.MethodPost, "/approval", bytes.NewReader(body)))

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if gotToken != "device-token-xyz" {
		t.Fatalf("routed to token %q", gotToken)
	}
	if gotEvent.ID != "appr-1" || gotEvent.Command != "rm -rf build/" {
		t.Fatalf("event not forwarded: %+v", gotEvent)
	}
}

func TestHandleApprovalDropsUnknownSession(t *testing.T) {
	registry.Lock()
	delete(registry.tokens, "ghost")
	registry.Unlock()
	called := false
	orig := pushApprovalFn
	pushApprovalFn = func(string, approvalEvent) error { called = true; return nil }
	defer func() { pushApprovalFn = orig }()

	body, _ := json.Marshal(approvalEvent{ID: "x", SessionID: "ghost"})
	rec := httptest.NewRecorder()
	handleApproval(rec, httptest.NewRequest(http.MethodPost, "/approval", bytes.NewReader(body)))
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202", rec.Code)
	}
	if called {
		t.Fatal("should not push to an unregistered session")
	}
}
```

- [ ] **Step 3: Run — expect failure then pass**

Run: `cd daemon/push-backend && go test ./... -run TestHandleApproval 2>&1 | tail -12`
Expected: first FAIL if `pushApprovalFn` not yet added; after Step 1, PASS.

- [ ] **Step 4: Full suite + commit**

Run: `cd daemon/push-backend && go test ./... 2>&1 | tail -5`
```bash
git add daemon/push-backend/main.go daemon/push-backend/approval_push_test.go
git commit -m "test(push-backend): approval push routes to the registered token; drops unknown sessions"
```

### Task 7.2: Document the owner push-cert steps

**Files:**
- Modify: `docs/ship-gate-owner-steps.md` (ensure a clear APNs section)

- [ ] **Step 1: Add/condense the APNs owner steps**

Append a section (if not already precise):

```markdown
## APNs production push (owner, ~15 min — needs paid Apple account)

1. App Store Connect → Keys → create an **APNs Auth Key (.p8)**; note Key ID + Team ID.
2. Deploy push-backend with env: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH=/secrets/AuthKey.p8`, `APNS_BUNDLE_ID=dev.lancer.mobile`.
3. Set the app's `LANCER_PUSH_BACKEND_URL` (Info.plist / scheme) to the deployed URL.
4. On a **physical device** (APNs is no-op in the simulator): connect a host, background the app, trigger an approval on the host → expect a push within ~2s with the command + risk; tapping Approve resolves it via the decision relay (Milestone 2) even though the app was backgrounded.
```

- [ ] **Step 2: Commit**

```bash
git add docs/ship-gate-owner-steps.md
git commit -m "docs: APNs production push owner steps + decision-relay device test"
```

---

## Milestone 8 — Ship-gate (App Store submittable)

**Goal:** the iOS app archives cleanly, metadata is aligned to the governed-approvals positioning, and every remaining owner action is a single documented step. Engineering gets to "one human action away."

### Task 8.1: Verify entitlements + write the App Store positioning copy

**Files:**
- Verify: `project.yml` (entitlements already point at `Lancer.entitlements` with `aps-environment: production` + iCloud — confirm).
- Create: `docs/app-store-metadata-governed-approvals.md`

- [ ] **Step 1: Confirm entitlements + team**

Run: `grep -n "entitlements\|aps-environment\|DEVELOPMENT_TEAM\|com.apple.developer.icloud" project.yml | head`
Expected: `Lancer/Lancer.entitlements`, `aps-environment: production`, a `DEVELOPMENT_TEAM`. If the team is still the free personal team (`39HM2X8GS6`), note `TODO(owner): confirm paid-account team id`.

- [ ] **Step 2: Write the metadata draft (positioning = cross-vendor governed approvals)**

Create `docs/app-store-metadata-governed-approvals.md`:

```markdown
# App Store metadata — Governed Approvals v1

**Name:** Lancer — Agent Approvals
**Subtitle:** Govern Claude Code, Codex & opencode from your phone

**Promotional text:**
Your AI coding agents ask permission on your phone. Decide in one tap — even when you're away. Safe actions auto-handle by your policy; everything's logged.

**Description (opening):**
Lancer is mission control for the AI coding agents running on *your own* machine. A small bridge on your host enforces the policy *you* set — auto-allowing safe actions, blocking dangerous ones, and tapping you only for the calls that genuinely need a human. When it does, you get a notification with the exact command, the files it touches, and a risk read — and you approve, deny, or edit it in seconds, even when the app was closed. Works across Claude Code, OpenAI Codex, and opencode, with a full audit trail of every decision. Your code never leaves your host.

**Keywords:** claude code, codex, opencode, ai agent, approvals, ssh, devops, audit, policy, governance

**What to capture in screenshots (6.7"/6.1"/5.5" + iPad):**
1. Inbox with a high-risk approval card (command + blast radius).
2. A decision being made (Approve/Deny/Edit/Allow-always).
3. Fleet glance (cross-vendor status + spend).
4. Activity (while-you-were-away) feed.
5. Autonomy presets (Cautious/Balanced/Bypass).

**Decision-relay copy note:** the "even when you're away / app was closed" claim is true **only with Milestone 2 shipped**. If Milestone 2 is deferred, change the promo + description to "Open and decide in a tap" and drop "even when the app was closed."

**Privacy nutrition label:** device token (for push) + crash diagnostics if enabled; **no source code leaves the device** (state this). Verify against actual data flows before submission.
```

- [ ] **Step 3: Commit**

```bash
git add docs/app-store-metadata-governed-approvals.md
git commit -m "docs: App Store metadata for Governed Approvals v1"
```

### Task 8.2: Generate screenshots from the simulator

**Files:** none (artifacts to `docs/screenshots/`).

- [ ] **Step 1: Capture the five surfaces**

Boot a required-size simulator; `build_sim` → `install_app_sim` → `launch_app_sim`. Use the gallery (`LANCER_GALLERY: review`) for populated approval cards, and the real app for Fleet/Activity empty+populated. Screenshot each of the five surfaces in Task 8.1 Step 2 (light and dark via `mcp__XcodeBuildMCP__set_sim_appearance`). Save to `docs/screenshots/governed-approvals/`.

- [ ] **Step 2: Commit**

```bash
git add docs/screenshots/governed-approvals
git commit -m "docs: App Store screenshots for Governed Approvals v1"
```

### Task 8.3: Release archive dry-run + owner handoff

**Files:**
- Modify: `docs/ship-gate-owner-steps.md` (final owner checklist)

- [ ] **Step 1: Confirm a Release build compiles**

Run `mcp__XcodeBuildMCP__build_sim` with the Release configuration if supported by defaults; otherwise document the archive command. Confirm zero errors and zero new concurrency warnings.

- [ ] **Step 2: Write the final owner checklist**

Ensure `docs/ship-gate-owner-steps.md` ends with an ordered, one-action-each list:
1. Enroll/confirm paid Apple Developer account; set `DEVELOPMENT_TEAM`; `xcodegen generate`.
2. App Store Connect: app record, enable Push + CloudKit, create the IAP, privacy label, upload screenshots from `docs/screenshots/governed-approvals/`.
3. Deploy `push-backend` with APNs `.p8` env (Task 7.2) + set `LANCER_PUSH_BACKEND_URL`.
4. Physical-device validation: connect host, background app, trigger approval → push → tap Approve → decision relay resolves (Milestone 2).
5. `fastlane beta` → TestFlight; after testing, `fastlane release`.

- [ ] **Step 3: Final full-suite verification**

Run all four suites (engine swift test, lancerd go test, push-backend go test, app `build_sim`). Expected: ≥ baseline counts from Milestone 0, zero failures, zero new warnings.

- [ ] **Step 4: Commit + open PR**

```bash
git add docs/ship-gate-owner-steps.md
git commit -m "docs: final ship-gate owner checklist for Governed Approvals v1"
```
Open a PR from `feat/governed-approvals` → `feat/product-depth-sprint` (NOT master) summarizing the milestones, the two gaps closed (decision relay + IA), and the owner checklist.

---

## Self-review notes (for the executor)
- **Spec coverage:** Approvals round-trip (M1, M2), cross-vendor (M1 parity tests for all three), governed/policy (M3), decide-while-away (M2 — the differentiator), audit/Activity (M4), fleet+cost (M5), IA reset (M6), push (M7), App Store (M8). All five FRONTEND_DESIGN_BRIEF "design-for-first" surfaces (decision, queue, fleet+usage, activity, onboarding) are covered.
- **Type consistency:** `decisionWireValue(for:)`, `respond(approvalId:decision:editedToolInput:)`, `tailAudit(limit:)`, `fetchAgentStatus`, `refreshBridgeStatus`, `FleetStore.Slot.bridgeStatus`, `AgentVendorStatus.displayName`, `AuditLogEntry`, `ApprovalEvent`/`ApprovalDecision`/`approvalStore.resolve`, `PresetDocument` — all used as defined in source (verified 2026-06-11). Where a property name is assumed (`BridgeSessionActions.isConnected`/`tailAudit`), the step says to grep-confirm and adapt.
- **Tripwire:** Task 2.1 Step 1 contains a deliberate Cyrillic `Р` in a test function name — type it as ASCII `TestDecisionRelayRejectsMissingFields`.
- **Critical-path note:** M0→M1→M2→M3→M7→M8 is the minimum shippable cut (governed cross-vendor approvals + decide-while-away + push + store). M4/M5/M6 make it a product; include them unless the owner wants the fastest possible first submission, in which case ship connected-only and adjust copy per Task 8.1 Step 2.
```
