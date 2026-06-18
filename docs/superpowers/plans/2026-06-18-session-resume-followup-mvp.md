# Session-Resume Follow-Up MVP — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing (dead) follow-up bar actually continue an agent conversation from the phone, for Claude + opencode, over both SSH and the E2E relay.

**Architecture:** A follow-up re-launches the vendor CLI with its continue flag (`claude --continue`, `opencode run --continue`) in the run's original cwd as a **fresh process with a new `runId`**, re-passing the policy + budget gates. iOS models a conversation as an ordered list of turn `runId`s and routes the follow-up through the run's own transport. No server, no tmux, no `seq`-counter refactor. Codex is deferred behind a smoke check (its `continueArgv` returns "unsupported" so it cannot hang).

**Tech Stack:** Go (daemon `conduitd`, `go test`), Swift 6.2 / SwiftUI (ConduitKit SPM package + Xcode app target via XcodeBuildMCP).

## Global Constraints

- Explicit argv only — never `sh -c "<interpolated>"` (`agentArgv` security property in `daemon/conduitd/dispatch.go`).
- Every process launch (including continues) MUST re-pass the policy gate AND budget gate. Never special-case a continue to skip them.
- Works over BOTH transports: SSH (`agent.run.continue` RPC in `server.go`) and E2E relay (`agentRunContinue` case in `e2e_router.go`), both funnelling into ONE `dispatcher.continueRun`.
- **New `runId` per turn.** Do NOT change `launchFunc`, do NOT thread a shared `seq` counter, do NOT touch `tmuxLauncher`.
- Codex continue is NOT shipped in this MVP — `continueArgv` returns `(nil, false)` for codex; the caller returns a structured "continue not supported" error.
- iOS: Swift 6.2 strict concurrency, zero new warnings. Verify with the **app target** (`mcp__XcodeBuildMCP__build_sim`), not only `swift build` (SPM compiles macOS and skips `#if os(iOS)` UI code).
- Daemon verify: `go test ./daemon/conduitd/...`.
- Owner execution model (CLAUDE.md): Claude plans + verifies; opencode `deepseek-v4-flash` agents may execute. Daemon (Go) and iOS (Swift) tasks touch disjoint files and can run in parallel; within iOS, `AppRoot.swift` is touched by Task 8 only.

> **Already done (not tasks):** The 3 security blockers (BiometricGate early-returns, AppRoot `if false` app-lock, relay key in UserDefaults) are FIXED and the app-target build is green. The inline-chat UI (`NewChatTabView` inline state, `ActiveChatRun` for both transports, `RunControls.swift`) already exists.

---

## File Structure

**Daemon (Go, `daemon/conduitd/`)**
- `dispatch.go` — add `CWD`/`Model` to `dispatchRun`; add `continueArgv`; add `dispatcher.continueRun`.
- `dispatch_test.go` — unit tests for the above.
- `server.go` — add `runContinue` helper + `agent.run.continue` RPC case.
- `server_test.go` — RPC-level test.
- `e2e_router.go` — add `agentRunContinue` case + `runContinueResult` reply.
- `e2e_router_test.go` — relay-path test (create if absent).

**iOS (Swift, `Packages/ConduitKit/Sources/`)**
- `ConduitCore/ConduitDProtocol.swift` — `RunContinueParams`.
- `SSHTransport/DaemonChannel.swift` — `continueRun(runId:prompt:)`.
- `SessionFeature/E2ERelayBridge.swift` — make `sendRunContinue` non-fire-and-forget.
- `AppFeature/AppRoot.swift` — route follow-up by transport; surface errors.
- `AppFeature/NewChatTabView.swift` — conversation = ordered turns; append continued `runId`.

---

## Task 1: Store `CWD` + `Model` on a dispatched run

**Files:**
- Modify: `daemon/conduitd/dispatch.go` (`dispatchRun` struct ~266-274; `dispatch()` run-store ~642)
- Test: `daemon/conduitd/dispatch_test.go`

**Interfaces:**
- Produces: `dispatchRun` now has fields `CWD string` and `Model string`, populated by `dispatch()`.

- [ ] **Step 1: Write the failing test**

Add to `daemon/conduitd/dispatch_test.go`:
```go
func TestDispatchStoresCWDAndModel(t *testing.T) {
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Model: "sonnet", Prompt: "hi"},
		allowEval, noAudit)
	if res.Status != "started" {
		t.Fatalf("want started, got %q (%s)", res.Status, res.Message)
	}
	run := d.runs[res.RunID]
	if run == nil || run.CWD != "/repo" || run.Model != "sonnet" {
		t.Fatalf("want CWD=/repo Model=sonnet, got %+v", run)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./daemon/conduitd/ -run TestDispatchStoresCWDAndModel`
Expected: FAIL — `run.CWD`/`run.Model` undefined (compile error).

- [ ] **Step 3: Add the fields and populate them**

In `dispatch.go`, the `dispatchRun` struct — add two fields:
```go
type dispatchRun struct {
	ID        string
	Agent     string
	Prompt    string
	CWD       string // working dir of the original launch; reused for continues
	Model     string // model of the original launch; reused for continues
	Status    string // running | paused | cancelled | budget-exceeded
	BudgetUSD float64
	SessionID string // reserved for future resume-by-id
	handle    *procHandle
}
```
In `dispatch()`, the run-store line (currently `d.runs[id] = &dispatchRun{ID: id, Agent: p.Agent, Prompt: p.Prompt, Status: "running", BudgetUSD: p.BudgetUSD, handle: handle}`):
```go
	d.runs[id] = &dispatchRun{ID: id, Agent: p.Agent, Prompt: p.Prompt, CWD: p.CWD, Model: p.Model, Status: "running", BudgetUSD: p.BudgetUSD, handle: handle}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./daemon/conduitd/ -run TestDispatchStoresCWDAndModel`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/dispatch.go daemon/conduitd/dispatch_test.go
git commit -m "feat(conduitd): store cwd+model on dispatched run for continue"
```

---

## Task 2: `continueArgv` — per-vendor continue-most-recent argv

**Files:**
- Modify: `daemon/conduitd/dispatch.go` (add `continueArgv` near `agentArgv` ~33-65)
- Test: `daemon/conduitd/dispatch_test.go`

**Interfaces:**
- Produces: `func continueArgv(agent, prompt, model string) ([]string, bool)` — `false` means continue unsupported for that agent (codex/unknown).

- [ ] **Step 1: Write the failing test**

```go
func TestContinueArgv(t *testing.T) {
	claude, ok := continueArgv("claudeCode", "next step", "")
	if !ok {
		t.Fatal("claude continue should be supported")
	}
	want := []string{"claude", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--continue", "-p", "next step"}
	if !reflect.DeepEqual(claude, want) {
		t.Fatalf("claude argv mismatch:\n got %v\nwant %v", claude, want)
	}
	oc, ok := continueArgv("opencode", "next step", "gpt-5")
	if !ok || !reflect.DeepEqual(oc, []string{"opencode", "run", "--continue", "--model", "gpt-5", "next step"}) {
		t.Fatalf("opencode argv mismatch: %v ok=%v", oc, ok)
	}
	if _, ok := continueArgv("codex", "x", ""); ok {
		t.Fatal("codex continue must be unsupported in MVP (would hang headless)")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./daemon/conduitd/ -run TestContinueArgv`
Expected: FAIL — `continueArgv` undefined.

- [ ] **Step 3: Implement `continueArgv`**

Add below `agentArgv` in `dispatch.go`:
```go
// continueArgv builds an explicit, shell-free argv that continues the most-recent
// vendor session in the run's cwd with a new prompt. Returns ok=false for agents
// whose headless continue is unsafe/unsupported in this MVP (codex hangs without a
// TTY unless its sandbox is disabled — deferred behind a smoke check).
func continueArgv(agent, prompt, model string) ([]string, bool) {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		argv := []string{"claude", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--continue", "-p", prompt}
		if model != "" {
			argv = append(argv[:len(argv)-2], "--model", model, "-p", prompt)
		}
		return argv, true
	case "opencode":
		argv := []string{"opencode", "run", "--continue"}
		if model != "" {
			argv = append(argv, "--model", model)
		}
		return append(argv, prompt), true
	default:
		return nil, false
	}
}
```
NOTE: the claude `--model` branch reuses `argv[:len(argv)-2]` to drop the trailing `-p prompt`, then re-appends `--model model -p prompt` so the prompt stays last (claude requires `-p` last in this form). The test pins the no-model claude order and the with-model opencode order exactly; the claude-with-model path follows the same prompt-last rule.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./daemon/conduitd/ -run TestContinueArgv`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/dispatch.go daemon/conduitd/dispatch_test.go
git commit -m "feat(conduitd): continueArgv for claude+opencode (codex deferred)"
```

---

## Task 3: `dispatcher.continueRun` — gated re-launch with a new runId

**Files:**
- Modify: `daemon/conduitd/dispatch.go` (add method after `resume()` ~698)
- Test: `daemon/conduitd/dispatch_test.go`

**Interfaces:**
- Consumes: `continueArgv` (Task 2); `dispatchRun.CWD/Model` (Task 1); `policyEvalFunc`, `dispatchResult`, `newUUID()`.
- Produces: `func (d *dispatcher) continueRun(runID, prompt string, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult` — returns `{RunID: <new id>, Status: "started"}` on success; `Status:"error"` for unknown run / unsupported agent; `"denied"`/`"needsApproval"`/`"budgetExceeded"` from the gates.

- [ ] **Step 1: Write the failing tests**

```go
func TestContinueRunNewRunIDAndGate(t *testing.T) {
	var launches int
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		launches++
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "start"}, allowEval, noAudit)
	cont := d.continueRun(first.RunID, "next", allowEval, noAudit)
	if cont.Status != "started" {
		t.Fatalf("want started, got %q (%s)", cont.Status, cont.Message)
	}
	if cont.RunID == "" || cont.RunID == first.RunID {
		t.Fatalf("continue must allocate a NEW runId, got %q (first %q)", cont.RunID, first.RunID)
	}
	if launches != 2 {
		t.Fatalf("want 2 launches, got %d", launches)
	}
}

func TestContinueRunDeniedDoesNotLaunch(t *testing.T) {
	var contLaunched bool
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.dispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "start"}, allowEval, noAudit)
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		contLaunched = true
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	res := d.continueRun(first.RunID, "next", denyEval, noAudit)
	if res.Status != "denied" {
		t.Fatalf("want denied, got %q", res.Status)
	}
	if contLaunched {
		t.Fatal("a policy-denied continue must NOT launch")
	}
}

func TestContinueRunUnknownRun(t *testing.T) {
	d := newDispatcher()
	if res := d.continueRun("nope", "x", allowEval, noAudit); res.Status != "error" {
		t.Fatalf("want error for unknown run, got %q", res.Status)
	}
}

func TestContinueRunCodexUnsupported(t *testing.T) {
	d := newDispatcher()
	d.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := d.dispatch(dispatchParams{Agent: "codex", CWD: "/repo", Prompt: "start"}, allowEval, noAudit)
	if res := d.continueRun(first.RunID, "next", allowEval, noAudit); res.Status != "error" {
		t.Fatalf("want error (codex continue unsupported), got %q", res.Status)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./daemon/conduitd/ -run TestContinueRun`
Expected: FAIL — `continueRun` undefined.

- [ ] **Step 3: Implement `continueRun`**

Append to `dispatch.go`:
```go
// continueRun re-launches the vendor CLI to continue an existing run's conversation
// with a new prompt, as a FRESH process under a NEW runId (avoids the per-launch seq
// collision in RunOutputStore). It re-passes the budget + policy gates exactly like
// dispatch(); a follow-up prompt is new attacker-influenceable input.
func (d *dispatcher) continueRun(runID, prompt string, evalFn policyEvalFunc, audit func(AuditEntry)) dispatchResult {
	d.mu.Lock()
	run := d.runs[runID]
	d.mu.Unlock()
	if run == nil {
		return dispatchResult{Status: "error", Message: "unknown run: " + runID}
	}

	argv, ok := continueArgv(run.Agent, prompt, run.Model)
	if !ok {
		return dispatchResult{Status: "error", Message: "continue not supported for agent: " + run.Agent}
	}

	// Budget gate (shared daily total vs this run's cap).
	d.mu.Lock()
	spent := d.spentUSD
	d.mu.Unlock()
	if run.BudgetUSD > 0 && spent >= run.BudgetUSD {
		audit(AuditEntry{Action: "continue-budget-exceeded", Agent: run.Agent, Kind: "dispatch", Command: prompt})
		return dispatchResult{Status: "budgetExceeded", Message: fmt.Sprintf("daily spend $%.2f >= cap $%.2f", spent, run.BudgetUSD)}
	}

	// Policy gate (fail-closed at medium risk, same as dispatch).
	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      normalizeAgentSource(run.Agent),
		Kind:       "command",
		Command:    "[continue] " + strings.Join(argv, " "),
		CWD:        run.CWD,
		Risk:       1,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	effect, rule := evalFn(event)
	switch effect {
	case "deny":
		audit(AuditEntry{Action: "continue-denied", Agent: run.Agent, Kind: "dispatch", Command: prompt, Effect: "deny", Rule: rule})
		return dispatchResult{Status: "denied", Decision: "deny", Rule: rule}
	case "ask":
		audit(AuditEntry{Action: "continue-needs-approval", Agent: run.Agent, Kind: "dispatch", Command: prompt, Effect: "ask", Rule: rule})
		return dispatchResult{Status: "needsApproval", Decision: "ask", Rule: rule}
	}

	id := newUUID()
	handle, err := d.launch(argv, run.CWD, id, d.emit)
	if err != nil {
		audit(AuditEntry{Action: "continue-error", Agent: run.Agent, Kind: "dispatch", Command: prompt, Effect: "allow", Rule: rule})
		return dispatchResult{Status: "error", Message: err.Error()}
	}
	d.mu.Lock()
	d.runs[id] = &dispatchRun{ID: id, Agent: run.Agent, Prompt: prompt, CWD: run.CWD, Model: run.Model, Status: "running", BudgetUSD: run.BudgetUSD, handle: handle}
	d.mu.Unlock()
	audit(AuditEntry{Action: "continue-launched", Agent: run.Agent, Kind: "dispatch", Command: prompt, Effect: "allow", Rule: rule, ApprovalID: id})
	return dispatchResult{RunID: id, Status: "started", Decision: "allow", Rule: rule}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./daemon/conduitd/ -run TestContinueRun`
Expected: PASS (all four)

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/dispatch.go daemon/conduitd/dispatch_test.go
git commit -m "feat(conduitd): dispatcher.continueRun re-launches with new runId + gates"
```

---

## Task 4: `agent.run.continue` RPC (SSH path)

**Files:**
- Modify: `daemon/conduitd/server.go` (add `runContinue` helper near `runDispatch` ~352; add RPC case near `agent.dispatch` ~664)
- Test: `daemon/conduitd/server_test.go`

**Interfaces:**
- Consumes: `dispatcher.continueRun` (Task 3); `s.policyEffect`, `s.auditEntry`.
- Produces: `func (s *server) runContinue(runID, prompt string) dispatchResult`; RPC method `"agent.run.continue"` accepting `{runId, prompt}`, returning a `dispatchResult`.

- [ ] **Step 1: Write the failing test**

Mirror the existing dispatch RPC test in `server_test.go` (the fake `s.dispatcher.launch` at ~line 100 is the pattern):
```go
func TestAgentRunContinueRPC(t *testing.T) {
	s := newServer(t.TempDir())
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := s.runDispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "start"})
	if first.Status != "started" {
		t.Fatalf("dispatch failed: %q", first.Status)
	}
	res := s.runContinue(first.RunID, "next")
	if res.Status != "started" || res.RunID == first.RunID || res.RunID == "" {
		t.Fatalf("continue RPC: want started+new runId, got %+v", res)
	}
}
```
(If `newServer` requires policy wiring for "allow", follow whatever the existing dispatch RPC test does to get an allow effect — copy that setup verbatim.)

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./daemon/conduitd/ -run TestAgentRunContinueRPC`
Expected: FAIL — `s.runContinue` undefined.

- [ ] **Step 3: Implement helper + RPC case**

Near `runDispatch` in `server.go`:
```go
// runContinue continues an existing run with a new prompt (used by RPC + relay).
func (s *server) runContinue(runID, prompt string) dispatchResult {
	return s.dispatcher.continueRun(runID, prompt, s.policyEffect, s.auditEntry)
}
```
In `handleMessage`, add a case alongside `agent.dispatch`:
```go
	case "agent.run.continue":
		var p struct {
			RunID  string `json:"runId"`
			Prompt string `json:"prompt"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.RunID == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.writeResult(msg.ID, s.runContinue(p.RunID, p.Prompt))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./daemon/conduitd/ -run TestAgentRunContinueRPC`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/server.go daemon/conduitd/server_test.go
git commit -m "feat(conduitd): agent.run.continue RPC (SSH path)"
```

---

## Task 5: `agentRunContinue` relay case (E2E path)

**Files:**
- Modify: `daemon/conduitd/e2e_router.go` (`handleMessage` switch ~85-144; the `default` at ~142)
- Test: `daemon/conduitd/e2e_router_test.go` (create if absent)

**Interfaces:**
- Consumes: `server.runContinue` (Task 4); `relayClient` interface (`sendMessage`).
- Produces: relay message type `"agentRunContinue"` `{runId, prompt}` handled; reply `"runContinueResult"` carrying the `dispatchResult` (new runId). Streamed output continues to flow via the existing `agentRunOutput`/`agentRunStatus` fan-out under the new runId — no new notification mapping needed.

- [ ] **Step 1: Write the failing test**

In `e2e_router_test.go` (mirror how other relay cases are tested; use a fake `relayClient` that records `sendMessage` calls):
```go
type fakeRelay struct{ sent []string }
func (f *fakeRelay) isPaired() bool { return true }
func (f *fakeRelay) stop()          {}
func (f *fakeRelay) sendMessage(t string, p []byte) error { f.sent = append(f.sent, t); return nil }

func TestRelayAgentRunContinue(t *testing.T) {
	s := newServer(t.TempDir())
	s.dispatcher.launch = func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		return &procHandle{kill: func() {}, pause: func() {}, resume: func() {}}, nil
	}
	first := s.runDispatch(dispatchParams{Agent: "claudeCode", CWD: "/repo", Prompt: "start"})
	r := &e2eRouter{client: &fakeRelay{}, server: s}
	payload, _ := json.Marshal(map[string]string{"runId": first.RunID, "prompt": "next"})
	r.handleMessage("agentRunContinue", payload)
	fr := r.client.(*fakeRelay)
	found := false
	for _, s := range fr.sent {
		if s == "runContinueResult" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected runContinueResult reply, got %v", fr.sent)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./daemon/conduitd/ -run TestRelayAgentRunContinue`
Expected: FAIL — `agentRunContinue` falls through to `default`; no `runContinueResult` sent.

- [ ] **Step 3: Implement the case**

In `e2e_router.go` `handleMessage`, before `default:`:
```go
	case "agentRunContinue":
		var p struct {
			RunID  string `json:"runId"`
			Prompt string `json:"prompt"`
		}
		if err := json.Unmarshal(payload, &p); err != nil || p.RunID == "" {
			log.Printf("e2e: unmarshal agentRunContinue failed: %v", err)
			return
		}
		result := r.server.runContinue(p.RunID, p.Prompt)
		msg := map[string]interface{}{"type": "runContinueResult", "payload": result}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("runContinueResult", data)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./daemon/conduitd/ -run TestRelayAgentRunContinue && go test ./daemon/conduitd/...`
Expected: PASS (new test + full daemon suite green)

- [ ] **Step 5: Commit**

```bash
git add daemon/conduitd/e2e_router.go daemon/conduitd/e2e_router_test.go
git commit -m "feat(conduitd): handle agentRunContinue over E2E relay"
```

---

## Task 6: iOS `DaemonChannel.continueRun` (SSH client)

**Files:**
- Modify: `Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift` (add after `dispatchAgent` at `:452-457`)

**Interfaces:**
- Consumes: existing `sendRPC(method:params:) async throws -> Data` (`:73`) and `Self.decodeResult(_:as:)` (used at `:457`).
- Produces: `func continueRun(runId: String, prompt: String) async throws -> DispatchResult` calling RPC `"agent.run.continue"`.

- [ ] **Step 1: Add the method (mirrors `dispatchAgent` exactly)**

In `DaemonChannel.swift`, right after `dispatchAgent` (`:452-457`):
```swift
public func continueRun(runId: String, prompt: String) async throws -> DispatchResult {
    let params: [String: Any] = ["runId": runId, "prompt": prompt]
    let data = try await sendRPC(method: "agent.run.continue", params: params)
    return try Self.decodeResult(data, as: DispatchResult.self)
}
```

- [ ] **Step 2: Build the SPM package**

Run: `cd Packages/ConduitKit && swift build`
Expected: Build complete (DaemonChannel is not `#if os(iOS)`-gated — SPM verifies it).

- [ ] **Step 3: Commit**

```bash
git add Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift
git commit -m "feat(ios): DaemonChannel.continueRun RPC client"
```

---

## Task 7: Make relay `sendRunContinue` return its result (not fire-and-forget)

**Files:**
- Modify: `Packages/ConduitKit/Sources/SessionFeature/E2ERelayBridge.swift` (`sendRunContinue` ~105-112; the `handleRelayMessage` switch where `"dispatchResult"` is handled at `:153-161`)

**Interfaces:**
- Consumes: relay reply `"runContinueResult"` (Task 5); the existing `E2ERelayMessage.RelayInnerEnvelope<DispatchResult>` decode + continuation pattern used for `dispatchResult` (`:153-161`).
- Produces: `func sendRunContinue(runId: String, prompt: String) async throws -> DispatchResult` — sends `agentRunContinue` and awaits a `continueContinuation` resolved by the `runContinueResult` case. **Symmetric with the SSH `continueRun`**, so AppRoot handles both transports identically.

- [ ] **Step 1: Add a continuation + make `sendRunContinue` await it**

Mirror the existing dispatch flow (`sendDispatch` + `dispatchContinuation` resolved by the `dispatchResult` case at `:156`). Add a stored `private var continueContinuation: CheckedContinuation<DispatchResult, Error>?` next to `dispatchContinuation`, and change `sendRunContinue` to set it and await, sending the same `ContinueParams` payload it already sends:
```swift
public func sendRunContinue(runId: String, prompt: String) async throws -> DispatchResult {
    try await withCheckedThrowingContinuation { cont in
        self.continueContinuation = cont
        Task {
            do {
                struct ContinueParams: Codable { let runId: String; let prompt: String }
                try await relayClient.send(type: "agentRunContinue", payload: ContinueParams(runId: runId, prompt: prompt))
            } catch {
                self.continueContinuation?.resume(throwing: error)
                self.continueContinuation = nil
            }
        }
    }
}
```
(Match the exact `relayClient.send` shape `sendDispatch` uses — copy it verbatim.)

- [ ] **Step 2: Resolve it from the reply (mirror the `dispatchResult` case at `:153-161`)**

In `handleRelayMessage`, before `default`:
```swift
case "runContinueResult":
    let envelope = try? JSONDecoder().decode(E2ERelayMessage.RelayInnerEnvelope<DispatchResult>.self, from: message.payload)
    if let result = envelope?.payload {
        continueContinuation?.resume(returning: result)
    } else {
        continueContinuation?.resume(throwing: E2EError.decryptFailed)
    }
    continueContinuation = nil
```

- [ ] **Step 3: Build the SPM package**

Run: `cd Packages/ConduitKit && swift build`
Expected: Build complete.

- [ ] **Step 4: Commit**

```bash
git add Packages/ConduitKit/Sources/SessionFeature/E2ERelayBridge.swift
git commit -m "feat(ios): sendRunContinue awaits runContinueResult (returns new runId)"
```

---

## Task 8: Route follow-up by transport + surface errors (AppRoot)

**Files:**
- Modify: `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift` (`onSendFollowUp` closures ~871-872 and ~990-991; `ActiveChatRun` struct ~1580)

**Interfaces:**
- Consumes: `DaemonChannel.continueRun` (Task 6), `E2ERelayBridge.sendRunContinue` + `conduitE2ERunContinueResult` (Task 7).
- Produces: a follow-up routes to the **run's own transport**; failures and `denied`/`needsApproval`/`budgetExceeded` outcomes are shown in the thread (not swallowed by `try?`).

- [ ] **Step 1: Tag each run with its transport**

In `ActiveChatRun`, add a transport tag and (for SSH) the channel reference:
```swift
public enum RunTransport { case relay; case ssh(DaemonChannel) }
```
Add `public let transport: RunTransport` to `ActiveChatRun` and populate it where `performDispatch` builds the `.started(ActiveChatRun(...))` for relay (`~742`, `.relay`) and SSH (`~781`, `.ssh(slot.channel)` — use the same channel the SSH dispatch used).

- [ ] **Step 2: Route the follow-up**

Replace both `onSendFollowUp` closures (currently `Task { try? await e2eBridge?.sendRunContinue(...) }`) with a single helper that switches on the active run's transport:
```swift
private func sendFollowUp(_ run: ActiveChatRun, prompt: String) {
    Task {
        do {
            let result: DispatchResult
            switch run.transport {
            case .relay:
                guard let bridge = e2eBridge else { return }
                result = try await bridge.sendRunContinue(runId: run.runId, prompt: prompt)
            case .ssh(let channel):
                result = try await channel.continueRun(runId: run.runId, prompt: prompt)
            }
            await MainActor.run { handleContinueResult(result, for: run) }
        } catch {
            await MainActor.run { dispatchFeedback = "Follow-up failed: \(error.localizedDescription)" }
        }
    }
}
```
Both transports now return `DispatchResult`, so `handleContinueResult` is the single sink. It should: on `status == "started"`, hand the new `result.runId` to the inline thread (Task 9) as a new turn; otherwise set `dispatchFeedback` for `denied`/`needsApproval`/`budgetExceeded`/`error` (mirror how `performDispatch`'s `ChatDispatchOutcome` non-`started` cases already feed `dispatchFeedback`). Pass the new runId to NewChatTabView via a binding or callback (e.g. an `onContinuedTurn: (String) -> Void` the view sets, or a shared `@State` the view observes).

- [ ] **Step 3: Build the app target**

Run (XcodeBuildMCP): `build_sim` with the session defaults already set (Conduit / iPhone 17 Pro / Debug).
Expected: `SUCCEEDED`, zero errors. (AppRoot is `#if os(iOS)` — SPM will NOT catch breaks here; the app build is mandatory.)

- [ ] **Step 4: Commit**

```bash
git add Packages/ConduitKit/Sources/AppFeature/AppRoot.swift
git commit -m "feat(ios): route follow-up by run transport; surface continue errors"
```

---

## Task 9: Render a conversation as ordered turns (NewChatTabView)

**Files:**
- Modify: `Packages/ConduitKit/Sources/AppFeature/NewChatTabView.swift` (`activeRun` state ~43; body ~95-110; follow-up send ~246-256)

**Interfaces:**
- Consumes: the new runId from Task 8 (`handleContinueResult`) and the relay `conduitE2ERunContinueResult` notification (Task 7).
- Produces: the inline thread renders each turn's `RunOutputStore` text in order; sending a follow-up appends a new turn keyed by the continued `runId`.

- [ ] **Step 1: Model turns**

Replace the single `@State private var activeRun: ActiveChatRun?` usage with an ordered list of run ids for the active conversation:
```swift
@State private var turnRunIds: [String] = []   // first = initial dispatch, rest = continues
```
On initial dispatch (where `activeRun` is set), seed `turnRunIds = [run.runId]`. Keep `activeRun` for the *current/last* turn's controls.

- [ ] **Step 2: Render each turn**

In the body where `currentRun?.chunks` is rendered inside `ConversationScrollView`, iterate turns instead of the single run:
```swift
ForEach(turnRunIds, id: \.self) { rid in
    if let run = runOutputStore.run(rid) {
        StreamingOutputText(text: run.text)   // existing renderer from RunControls.swift
    }
}
```
(Keep the existing HUD/SpectrumBar bound to the last turn = `activeRun.runId`.)

- [ ] **Step 3: Append a turn on continue**

When `handleContinueResult` (Task 8, both transports) reports a new started runId, append it: `turnRunIds.append(newRunId)` and update `activeRun` to the new runId so the controls/HUD follow the latest turn. Register the new runId in `runOutputStore` (`runOutputStore.register(runId:)`) so it has a slot before chunks stream. Wire whatever channel Task 8 chose (`onContinuedTurn` callback or shared `@State`) to call this append.

- [ ] **Step 4: Build the app target**

Run (XcodeBuildMCP): `build_sim`.
Expected: `SUCCEEDED`, zero errors.

- [ ] **Step 5: Commit**

```bash
git add Packages/ConduitKit/Sources/AppFeature/NewChatTabView.swift
git commit -m "feat(ios): inline thread renders ordered turns; appends continued runId"
```

---

## Final verification (end-to-end, on a real host)

- [ ] `go test ./daemon/conduitd/...` — all green.
- [ ] App-target build green (`build_sim`).
- [ ] **Live SSH:** dispatch `claude` to a host, let a turn finish, type a follow-up in the inline bar, confirm a SECOND runId streams its response appended below the first in the same conversation. (Use the live-SSH `session` harness in CLAUDE.md.)
- [ ] **Live relay:** repeat over the E2E relay path (pair, dispatch, follow up).
- [ ] **opencode:** repeat the SSH follow-up with `opencode`.
- [ ] **Codex stays safe:** dispatch `codex`, attempt a follow-up, confirm it returns a visible "continue not supported" message and does NOT hang.
- [ ] **Gate visible:** with a policy that `ask`s/`deny`s a continue, confirm the New Chat thread shows the denied/needs-approval outcome instead of silently doing nothing.
- [ ] **Cross-cwd note:** `--continue` is cwd-most-recent; documented limitation — precise `--resume <session-id>` (via `--session-id` minting) is the first follow-up once the session picker is built.

## Deferred (explicitly NOT in this plan)
- Codex continue (behind a no-cost smoke check that sandboxed `codex exec resume` works on the installed CLI + verified hook wiring).
- Resume-by-id / `--session-id` minting + `agent.session.list` session picker.
- Terminal-started session takeover.
- The provider-native `AgentProvider` adapter interface (the better long-term spine — this MVP is the interim CLI adapter).
- L2 encrypted backup, L2-R readable tier, L3 always-on compute.
- On-device biometric verification of the security fixes (sim can't exercise Face ID).
