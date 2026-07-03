package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"lancer/lancerd/policy"
)

const maxFrameBytes = 16 * 1024 * 1024

type rpcMessage struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  interface{}     `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type registeredDevice struct {
	PushBackendURL string `json:"pushBackendURL"`
	SessionID      string `json:"sessionID"`
}

type policyEngine struct {
	mu         sync.RWMutex
	home       string
	docs       []policy.Document
	legacyJSON string
	migrated   bool
}

func newPolicyEngine(home string) *policyEngine {
	e := &policyEngine{
		home:       home,
		legacyJSON: filepath.Join(home, ".lancer", "always-rules.json"),
	}
	e.reload("")
	return e
}

func (e *policyEngine) ensureMigrated() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.migrated {
		return
	}
	if _, err := os.Stat(e.legacyJSON); err == nil {
		_ = policy.MigrateAlwaysRulesJSON(e.legacyJSON, policy.AlwaysPolicyPath(e.home))
		_ = os.Rename(e.legacyJSON, e.legacyJSON+".migrated")
	}
	e.migrated = true
}

func (e *policyEngine) reload(cwd string) error {
	e.ensureMigrated()
	docs, err := policy.LoadAllForCWD(cwd, e.home)
	if err != nil {
		return err
	}
	e.mu.Lock()
	e.docs = docs
	e.mu.Unlock()
	return nil
}

func (e *policyEngine) evaluate(event ApprovalEvent) policy.Result {
	req := policyRequest(event)
	// User-approved always rules override stricter default templates when they match.
	if doc, err := policy.LoadFile(policy.AlwaysPolicyPath(e.home)); err == nil {
		if res := policy.Evaluate(doc, req); res.Effect == policy.EffectAllow && !res.FromDefault {
			return res
		}
	}
	e.mu.RLock()
	docs := append([]policy.Document(nil), e.docs...)
	e.mu.RUnlock()
	if len(docs) == 0 {
		return policy.Evaluate(policy.DefaultDocument(), req)
	}
	return policy.EvaluateDocuments(docs, req)
}

// appendAllowAlways persists approve-always via policy.AppendAllowRule (policy-always.yaml).
func (e *policyEngine) appendAllowAlways(event ApprovalEvent) error {
	if err := policy.AppendAllowRule(e.home, allowRuleFromEvent(event)); err != nil {
		return err
	}
	return e.reload(event.CWD)
}

type policyGetResult struct {
	Documents []policy.Document `json:"documents"`
	Default   string            `json:"default"`
	YAML      string            `json:"yaml,omitempty"`
}

func (e *policyEngine) getPolicyDocuments(cwd string) (policyGetResult, error) {
	e.ensureMigrated()
	var out policyGetResult
	if doc, _, err := policy.LoadRepoPolicy(cwd); err == nil {
		out.Documents = append(out.Documents, doc)
	}
	if doc, err := policy.LoadFile(policy.GlobalPolicyPath(e.home)); err == nil {
		out.Documents = append(out.Documents, doc)
	} else if os.IsNotExist(err) {
		out.Documents = append(out.Documents, policy.DefaultDocument())
	}
	if doc, err := policy.LoadFile(policy.AlwaysPolicyPath(e.home)); err == nil {
		out.Documents = append(out.Documents, doc)
	}
	out.Default = string(policy.EffectAsk)
	yaml, err := e.getPolicyYAML(cwd)
	if err == nil {
		out.YAML = yaml
	}
	return out, nil
}

// getPolicyYAML returns the editable global policy as YAML text. When no global
// policy file exists yet, it returns the bundled default document so the editor
// always has a document to show.
func (e *policyEngine) getPolicyYAML(cwd string) (string, error) {
	if data, err := os.ReadFile(policy.GlobalPolicyPath(e.home)); err == nil {
		return string(data), nil
	} else if !os.IsNotExist(err) {
		return "", err
	}
	return policy.MarshalYAML(policy.DefaultDocument())
}

func (s *server) simulatePolicy(yamlText string, periodDays int) policy.SimulationResult {
	doc, err := policy.ParseDocument(yamlText)
	if err != nil {
		return policy.SimulationResult{
			GeneratedAt: time.Now().UTC().Format(time.RFC3339),
			PeriodDays:  periodDays,
		}
	}
	entries, err := policy.LoadAuditEntries(serverHome(), periodDays)
	if err != nil {
		return policy.SimulationResult{
			GeneratedAt: time.Now().UTC().Format(time.RFC3339),
			PeriodDays:  periodDays,
		}
	}
	return policy.Simulate(doc, entries, periodDays)
}

// setPolicyYAML validates and persists the global policy YAML, then reloads so
// evaluation for cwd picks up the change immediately.
func (e *policyEngine) setPolicyYAML(cwd, yamlText string) error {
	doc, err := policy.ParseDocument(yamlText)
	if err != nil {
		return err
	}
	if err := policy.SaveFile(policy.GlobalPolicyPath(e.home), doc); err != nil {
		return err
	}
	return e.reload(cwd)
}

type server struct {
	approvals  *approvalStore
	policy     *policyEngine
	audit      *auditLog
	secrets    *secretsStore
	dispatcher *dispatcher
	scheduler  *scheduler
	poller     *decisionPoller
	e2e        *e2eRouter
	stdoutMu   sync.Mutex
	emitMu     sync.Mutex
	emit       func([]byte) error
	deviceMu   sync.RWMutex
	device     *registeredDevice
	// relayToken is the per-session capability secret minted at session attach
	// (lancer.device.register), delivered to the app over the DaemonChannel and
	// presented as `Authorization: Bearer <relayToken>` on the decision relay.
	// Guarded by deviceMu. TREAT AS SECRET — never log it.
	relayToken string
	// loops is an in-memory store of loop state pushed by the app via
	// agent.loop.update, keyed by loop id. The app's GRDB store is the durable
	// source of truth; this mirror lets the daemon answer agent.loop.list and
	// (later) rebroadcast to other connected clients. The map is the fast path;
	// loopsPath (~/.lancer/loops.json) is the durable mirror that survives
	// restarts — written on every upsert, loaded at startup. Guarded by loopsMu.
	loopsMu   sync.Mutex
	loops     map[string]loopState
	loopsPath string
	// sessions tracks shim-spawned agent sessions (id -> ShimSession).
	sessions *sessionRegistry
	// git runs git/gh subcommands for the agent.git.* / agent.worktree.* RPCs.
	// nil ⇒ realGitRunner; injectable in tests.
	git gitRunner
	// conversations is the host-owned conversation ledger (conversation_store.go)
	// backing the agent.conversations.* RPCs. nil only if openConversationStore
	// failed at startup (logged to stderr); the conversation RPC methods
	// (conversation_rpc.go) then return a clear "conversation store
	// unavailable" error instead of panicking on a nil pointer.
	conversations *conversationStore
}

type loopState struct {
	ID      string                 `json:"id"`
	Status  string                 `json:"status"`
	Payload map[string]interface{} `json:"payload"`
}

func (s *server) setE2ERouter(e2e *e2eRouter) {
	s.e2e = e2e
}

func (s *server) setEmitter(emit func([]byte) error) {
	s.emitMu.Lock()
	s.emit = emit
	s.emitMu.Unlock()
}

func newServer(home string) *server {
	s := &server{
		approvals:  newApprovalStore(),
		policy:     newPolicyEngine(home),
		audit:      newAuditLog(home),
		secrets:    newSecretsStore(home),
		dispatcher: newDispatcher(),
		sessions:   newSessionRegistry(),
		scheduler:  newScheduler(home),
		loops:      map[string]loopState{},
		loopsPath:  filepath.Join(home, ".lancer", "loops.json"),
	}
	s.loadLoops()
	// The conversation ledger opens its own SQLite file under <home>/.lancer —
	// same host-local-state pattern as policy/audit/secrets/scheduler above. A
	// failure here (e.g. unwritable home) is logged, not fatal: the daemon still
	// starts, and agent.conversations.* RPCs simply report the store as
	// unavailable rather than crashing the whole process.
	if conversations, err := openConversationStore(home); err != nil {
		fmt.Fprintf(os.Stderr, "conversation_store: open failed, agent.conversations.* RPCs will error: %v\n", err)
	} else {
		s.conversations = conversations
		// Lets a conversation-ledger-backed launch (launchConversationTurn)
		// persist the vendor session/thread id it captures from stdout, so the
		// NEXT follow-up on this conversation gets exact resume instead of
		// falling back to "continue latest in cwd". nil-safe: wrapEmitForRun
		// checks d.bindVendorSession != nil before calling it.
		s.dispatcher.bindVendorSession = conversations.bindVendorSession
	}
	// The poller applies poll-delivered decisions through applyDecision so they
	// persist IDENTICALLY to the live-SSH respond path (audit + approveAlways
	// policy) — not via a bare resolve that skips both.
	s.poller = newDecisionPoller(s.applyDecision)
	// Run-control actions (pause/resume/stop/budget-exceeded) feed the same audit log.
	s.dispatcher.audit = s.auditEntry
	// Launch escalation is relaxed only for agents whose per-action hook is
	// verifiably wired (Claude today); everything else stays fail-closed.
	s.dispatcher.hookWired = hookWiredForAgent(home)
	// Dispatched runs stream stdout/stderr + status back to the phone through the
	// same serialized writer the approval-pending notification uses.
	s.dispatcher.emit = s.emitNotification
	return s
}

// applyDecision resolves a pending approval and persists the outcome IDENTICALLY
// for every delivery path — the live-SSH `agent.approval.response` RPC and the
// phone→backend→poll fallback both route through here. resolve is the single
// delete-under-lock chokepoint, so this records at most once per approvalId.
// It writes the human-decision audit entry and, for approveAlways, the
// always-policy. FAIL-SAFE: a failed policy write is logged, never fatal — a
// dropped always-rule only means more prompting later, never an unintended allow.
func (s *server) applyDecision(id, decision, editedToolInput, contentHash string) (ApprovalEvent, bool) {
	event, ok := s.approvals.resolve(id, decision, editedToolInput, contentHash)
	if !ok {
		return ApprovalEvent{}, false
	}
	s.recordHumanDecision(event, decision)
	if decision == "approveAlways" {
		if err := s.policy.appendAllowAlways(event); err != nil {
			fmt.Fprintf(os.Stderr, "appendAllowAlways failed for %s: %v\n", id, err)
		}
	}
	return event, ok
}

// policyEffect adapts the policy engine to the dispatcher's evaluator signature.
func (s *server) policyEffect(event ApprovalEvent) (string, string, bool) {
	res := s.policy.evaluate(event)
	return string(res.Effect), res.MatchedRule, res.FromDefault
}

// hookWiredForAgent reports whether a per-action PreToolUse-equivalent gate is
// verifiably installed for the given agent binary, gating relaxLaunchEscalation.
// Claude checks its hooks.json wiring; OpenCode checks its tool.execute.before
// plugin (see opencode_plugin_install.go — the old hooks.json-based mechanism
// this used to point at was never real OpenCode config, found 2026-07-01/02).
// Codex/Kimi have no per-action hook, so those stay fail-closed.
func hookWiredForAgent(home string) func(string) bool {
	return func(bin string) bool {
		switch bin {
		case "claude":
			return claudeHookWired(claudeSettingsPath(home))
		case "opencode":
			return opencodeGateWired(home)
		default:
			return false
		}
	}
}

func (s *server) auditEntry(e AuditEntry) { _ = s.audit.append(e) }

// upsertLoop stores or replaces a loop by id. An empty id is rejected so a
// malformed payload can't collide under the "" key.
func (s *server) upsertLoop(payload map[string]interface{}) bool {
	id, _ := payload["id"].(string)
	if id == "" {
		return false
	}
	status, _ := payload["status"].(string)
	s.loopsMu.Lock()
	s.loops[id] = loopState{ID: id, Status: status, Payload: payload}
	s.persistLoopsLocked()
	s.loopsMu.Unlock()
	return true
}

// listLoops returns a snapshot of the in-memory loop store.
func (s *server) listLoops() []loopState {
	s.loopsMu.Lock()
	defer s.loopsMu.Unlock()
	out := make([]loopState, 0, len(s.loops))
	for _, l := range s.loops {
		out = append(out, l)
	}
	return out
}

// loadLoops hydrates the in-memory loop map from the on-disk mirror at startup.
// A missing or malformed file is non-fatal — the daemon simply starts empty.
func (s *server) loadLoops() {
	if s.loopsPath == "" {
		return
	}
	data, err := os.ReadFile(s.loopsPath)
	if err != nil {
		return
	}
	var stored []loopState
	if json.Unmarshal(data, &stored) != nil {
		return
	}
	s.loopsMu.Lock()
	for _, l := range stored {
		if l.ID == "" {
			continue
		}
		s.loops[l.ID] = l
	}
	s.loopsMu.Unlock()
}

// persistLoopsLocked writes the loop map to ~/.lancer/loops.json. Mirrors
// secretsStore.persistLocked (0700 dir, 0600 file). The caller must hold loopsMu.
func (s *server) persistLoopsLocked() {
	if s.loopsPath == "" {
		return
	}
	out := make([]loopState, 0, len(s.loops))
	for _, l := range s.loops {
		out = append(out, l)
	}
	_ = os.MkdirAll(filepath.Dir(s.loopsPath), 0700)
	data, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(s.loopsPath, data, 0600)
}

// runDispatch applies the policy + budget gate and launches (used by RPC + scheduler).
func (s *server) runDispatch(p dispatchParams) dispatchResult {
	return s.dispatcher.dispatch(p, s.policyEffect, s.auditEntry)
}

// runContinue continues an existing run with a new prompt (used by the SSH RPC and
// the E2E relay), re-passing the policy + budget gates via the dispatcher.
func (s *server) runContinue(runID, prompt string, fb continueFallback) dispatchResult {
	return s.dispatcher.continueRun(runID, prompt, fb, s.policyEffect, s.auditEntry)
}

// runObservedSessionContinue sends a follow-up prompt into a session that was
// started directly in a terminal on the host (never dispatched by Lancer),
// targeted by its exact vendor session ID, re-passing the policy + budget
// gates via the dispatcher (used by agent.observedSession.continue).
func (s *server) runObservedSessionContinue(p observedSessionContinueParams) dispatchResult {
	return s.dispatcher.resumeObservedSession(p, s.policyEffect, s.auditEntry)
}

// applyRunControl applies a relay-delivered run-control action to a dispatched
// run, routing through the same dispatcher methods the local RPC path uses.
func (s *server) applyRunControl(runID, action string) {
	switch action {
	case "stop":
		s.dispatcher.cancel(runID)
	case "pause":
		s.dispatcher.pause(runID)
	case "resume":
		s.dispatcher.resume(runID)
	}
}

// startScheduler runs the schedule ticker until ctx-like stop; call from daemon/legacy serve.
func (s *server) startScheduler(stop <-chan struct{}) {
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case t := <-ticker.C:
				s.scheduler.tick(t, s.runDispatch)
				// Feed periodic agent status spend into quota guardrails so the
				// iOS dashboard shows real data even when the app isn't polling.
				status := collectAgentStatus(serverHome())
				for _, ag := range status.Agents {
					if ag.UsageUSD != nil {
						s.dispatcher.updateProviderSpend(ag.Agent, *ag.UsageUSD)
					}
				}
			}
		}
	}()
}

// serverHome returns an isolated home directory when LANCER_STATE_DIR is set (tests).
func serverHome() string {
	home, _ := os.UserHomeDir()
	if state := os.Getenv("LANCER_STATE_DIR"); state != "" {
		home = filepath.Join(state, "home")
		_ = os.MkdirAll(filepath.Join(home, ".lancer"), 0700)
	}
	return home
}

func runServe() error {
	sockPath, err := socketPath()
	if err != nil {
		return err
	}
	conn, err := net.DialTimeout("unix", sockPath, 2*time.Second)
	if err == nil {
		defer conn.Close()
		return runServeAttach(conn)
	}

	fmt.Fprintf(os.Stderr,
		"lancerd serve: resident daemon not reachable (%v); self-hosting socket (run `lancerd install` + `lancerd daemon` for a persistent bridge)\n",
		err,
	)
	return runServeLegacy()
}

// runServeAttach relays length-prefixed JSON-RPC between stdin/stdout and the resident daemon.
func runServeAttach(conn net.Conn) error {
	hello, _ := json.Marshal(attachHello{Op: "attach"})
	if err := writeFrame(conn, hello); err != nil {
		return fmt.Errorf("attach handshake: %w", err)
	}

	errCh := make(chan error, 2)
	go func() {
		for {
			frame, err := readFrame(conn)
			if err != nil {
				errCh <- err
				return
			}
			if err := writeFrame(os.Stdout, frame); err != nil {
				errCh <- err
				return
			}
		}
	}()
	go func() {
		for {
			frame, err := readFrame(os.Stdin)
			if err != nil {
				errCh <- err
				return
			}
			if err := writeFrame(conn, frame); err != nil {
				errCh <- err
				return
			}
		}
	}()
	err := <-errCh
	if err == io.EOF {
		return nil
	}
	return err
}

func runServeLegacy() error {
	s := newServer(serverHome())
	ensureClaudeHookWiredOnBoot() // plain dispatches launch immediately (hook still gates tools)
	s.startScheduler(make(chan struct{}))

	sockPath, err := socketPath()
	if err != nil {
		return fmt.Errorf("socket path: %w", err)
	}
	_ = os.Remove(sockPath)

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return fmt.Errorf("listen unix %s: %w", sockPath, err)
	}
	defer func() { ln.Close(); os.Remove(sockPath) }()

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				first, framed, err := readFirstMessage(c)
				if err != nil || framed {
					c.Close()
					return
				}
				s.handleHook(c, first)
			}(conn)
		}
	}()

	return s.readStdioLoop(os.Stdin)
}

func (s *server) readStdioLoop(r io.Reader) error {
	for {
		frame, err := readFrame(r)
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return fmt.Errorf("read frame: %w", err)
		}
		var msg rpcMessage
		if err := json.Unmarshal(frame, &msg); err != nil {
			s.writeError(nil, -32700, "parse error")
			continue
		}
		s.handleMessage(&msg)
	}
}

func (s *server) handleMessage(msg *rpcMessage) {
	switch msg.Method {
	case "ping":
		s.writeResult(msg.ID, "pong")

	case "agent.approval.response":
		var decision ApprovalDecision
		if err := json.Unmarshal(msg.Params, &decision); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		if _, ok := s.applyDecision(decision.ApprovalID, decision.Decision, decision.EditedToolInput, decision.ContentHash); !ok {
			// Already resolved (timeout beat us here, or a duplicate/late
			// delivery), never existed, or the echoed content hash didn't match
			// the pending approval — tell the client rather than lying with a
			// blanket "ok" it would otherwise treat as delivered.
			s.writeError(msg.ID, -32001, "approval already resolved, not found, or content hash mismatch")
			return
		}
		s.writeResult(msg.ID, "ok")

	case "agent.doctor":
		s.writeResult(msg.ID, s.collectDoctorReport())

	case "agent.pair.begin":
		var params pairBeginParams
		if len(msg.Params) > 0 {
			if err := json.Unmarshal(msg.Params, &params); err != nil {
				s.writeError(msg.ID, -32602, "invalid params")
				return
			}
		}
		result, err := beginPairing(params)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, result)

	case "agent.audit.tail":
		var params struct {
			Limit int `json:"limit"`
		}
		_ = json.Unmarshal(msg.Params, &params)
		entries, err := s.audit.tail(params.Limit)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, map[string]interface{}{"entries": entries})

	case "agent.audit.verify":
		result := s.audit.Verify()
		s.writeResult(msg.ID, result)

	case "agent.audit.export":
		data := s.audit.exportJSONL()
		s.writeResult(msg.ID, map[string]string{"data": data})

	case "agent.policy.get":
		var params struct {
			CWD string `json:"cwd"`
		}
		_ = json.Unmarshal(msg.Params, &params)
		payload, err := s.policy.getPolicyDocuments(params.CWD)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, payload)

	case "agent.policy.reload":
		var params struct {
			CWD string `json:"cwd"`
		}
		_ = json.Unmarshal(msg.Params, &params)
		if err := s.policy.reload(params.CWD); err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, "ok")

	case "agent.policy.set":
		var params struct {
			CWD  string `json:"cwd"`
			YAML string `json:"yaml"`
		}
		if err := json.Unmarshal(msg.Params, &params); err != nil || params.YAML == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		if err := s.policy.setPolicyYAML(params.CWD, params.YAML); err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, "ok")

	case "agent.policy.simulate":
		var p struct {
			YAML       string `json:"yaml"`
			PeriodDays int    `json:"periodDays"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.YAML == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		if p.PeriodDays <= 0 {
			p.PeriodDays = 7
		}
		result := s.simulatePolicy(p.YAML, p.PeriodDays)
		s.writeResult(msg.ID, result)

	case "agent.status":
		var params agentStatusParams
		if len(msg.Params) > 0 {
			if err := json.Unmarshal(msg.Params, &params); err != nil {
				s.writeError(msg.ID, -32602, "invalid params")
				return
			}
		}
		s.writeResult(msg.ID, s.queryAgentStatus(params.HomeDir))

	case "agent.host.health":
		health := collectHostHealth()
		s.writeResult(msg.ID, health)

	case "agent.drift.scan":
		var params struct {
			Root string `json:"root"`
		}
		_ = json.Unmarshal(msg.Params, &params)
		if params.Root == "" {
			params.Root, _ = os.Getwd()
		}
		report, err := scanDrift(params.Root)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, report)

	case "agent.drift.remediate":
		var req DriftRemediateRequest
		if err := json.Unmarshal(msg.Params, &req); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		report, err := remediateDrift(req)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, report)

	case "agent.agents.installed":
		s.writeResult(msg.ID, map[string]interface{}{"agents": installedAgents(exec.LookPath)})

	case "agent.sessions.list":
		var params struct {
			HomeDir string `json:"homeDir,omitempty"`
		}
		_ = json.Unmarshal(msg.Params, &params)
		sessions, err := buildSessionIndex(params.HomeDir)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, map[string]interface{}{"sessions": sessions})

	case "agent.sessions.transcript":
		var params struct {
			SessionID string `json:"sessionId"`
			SinceLine int    `json:"sinceLine"`
		}
		if err := json.Unmarshal(msg.Params, &params); err != nil || params.SessionID == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		result, err := loadSessionTranscript("", params.SessionID, params.SinceLine)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, result)

	case "agent.conversations.list":
		var req conversationListRequest
		if len(msg.Params) > 0 {
			if err := json.Unmarshal(msg.Params, &req); err != nil {
				s.writeError(msg.ID, -32602, "invalid params")
				return
			}
		}
		result, err := s.conversationsList(req)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, result)

	case "agent.conversations.fetch":
		var req conversationFetchRequest
		if err := json.Unmarshal(msg.Params, &req); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		result, err := s.conversationsFetch(req)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, result)

	case "agent.conversations.append":
		var req conversationAppendRequest
		if err := json.Unmarshal(msg.Params, &req); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		result, err := s.conversationsAppend(req)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, result)

	case "agent.conversations.archive":
		var req conversationArchiveRequest
		if err := json.Unmarshal(msg.Params, &req); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		result, err := s.conversationsArchive(req)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, result)

	case "agent.conversations.attachObservedSession":
		var req conversationAttachObservedSessionRequest
		if err := json.Unmarshal(msg.Params, &req); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		result, err := s.conversationsAttachObservedSession(req)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, result)

	case "lancer.device.register":
		var info registeredDevice
		if err := json.Unmarshal(msg.Params, &info); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.deviceMu.Lock()
		// Reuse the session's existing relayToken across re-registrations
		// (reconnects) so the app's and backend's stored copies stay valid; mint
		// a fresh one only for a new/changed session.
		if s.device == nil || s.device.SessionID != info.SessionID || s.relayToken == "" {
			tok, err := generateRelayToken()
			if err != nil {
				s.deviceMu.Unlock()
				s.writeError(msg.ID, -32000, "relay token generation failed")
				return
			}
			s.relayToken = tok
		}
		s.device = &info
		relayToken := s.relayToken
		s.deviceMu.Unlock()

		// Register sessionId → relayToken with the backend over the control plane
		// (APPROVAL_RELAY_SECRET). Best-effort + async so we don't block the RPC
		// loop on a slow backend; if it fails the relay poll/POST simply 401s and
		// lancerd's ~120s auto-deny remains the backstop.
		if info.PushBackendURL != "" {
			go s.postRelayRegistration(info.PushBackendURL, info.SessionID, relayToken)
		}
		s.poller.ensureRunning(info.PushBackendURL, info.SessionID, relayToken)
		// Deliver the relayToken to the app over the (already-authenticated)
		// DaemonChannel as the `relayToken` field of this handshake's result.
		s.writeResult(msg.ID, map[string]string{"relayToken": relayToken})

	case "agent.dispatch":
		var p dispatchParams
		if err := json.Unmarshal(msg.Params, &p); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.writeResult(msg.ID, s.runDispatch(p))

	case "agent.run.continue":
		var p struct {
			RunID     string  `json:"runId"`
			Prompt    string  `json:"prompt"`
			Agent     string  `json:"agent"`
			CWD       string  `json:"cwd"`
			Model     string  `json:"model"`
			BudgetUSD float64 `json:"budgetUSD"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.RunID == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		fb := continueFallback{Agent: p.Agent, CWD: p.CWD, Model: p.Model, BudgetUSD: p.BudgetUSD}
		s.writeResult(msg.ID, s.runContinue(p.RunID, p.Prompt, fb))

	case "agent.observedSession.continue":
		var p observedSessionContinueParams
		if err := json.Unmarshal(msg.Params, &p); err != nil ||
			p.Vendor == "" || p.SessionID == "" || p.CWD == "" || p.Prompt == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.writeResult(msg.ID, s.runObservedSessionContinue(p))

	case "agent.cancel":
		var p struct {
			RunID string `json:"runId"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.writeResult(msg.ID, map[string]bool{"cancelled": s.dispatcher.cancel(p.RunID)})

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
		// Validate here (unlike the simple runId-only cases): a malformed budgetUSD
		// would silently zero the cap, which setBudget reads as "remove cap".
		if err := json.Unmarshal(msg.Params, &p); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.writeResult(msg.ID, map[string]bool{"ok": s.dispatcher.setBudget(p.RunID, p.BudgetUSD)})

	case "agent.quota.status":
		result := s.dispatcher.getQuotaGuard()
		s.writeResult(msg.ID, result)

	case "agent.quota.setCap":
		var p struct {
			Provider   string  `json:"provider"`
			DailyUSD   float64 `json:"dailyUSD"`
			MonthlyUSD float64 `json:"monthlyUSD"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Provider == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.dispatcher.setProviderCap(p.Provider, p.DailyUSD, p.MonthlyUSD)
		s.writeResult(msg.ID, map[string]bool{"ok": true})

	case "agent.quota.updateSpend":
		var p struct {
			Provider string  `json:"provider"`
			USD      float64 `json:"usd"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Provider == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.dispatcher.updateProviderSpend(p.Provider, p.USD)
		s.writeResult(msg.ID, map[string]bool{"ok": true})

	case "agent.loop.update":
		// Accept a Loop JSON object from the app and upsert it into the in-memory
		// loop store. The app's GRDB store remains the durable source of truth;
		// this mirror lets the daemon answer agent.loop.list.
		var loopPayload map[string]interface{}
		if err := json.Unmarshal(msg.Params, &loopPayload); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		if !s.upsertLoop(loopPayload) {
			s.writeError(msg.ID, -32602, "loop id required")
			return
		}
		s.writeResult(msg.ID, map[string]bool{"ok": true})

	case "agent.loop.list":
		s.writeResult(msg.ID, map[string]interface{}{"loops": s.listLoops()})

	case "agent.schedule.add":
		var sc schedule
		if err := json.Unmarshal(msg.Params, &sc); err != nil {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.writeResult(msg.ID, s.scheduler.add(sc))

	case "agent.schedule.list":
		s.writeResult(msg.ID, map[string]interface{}{"schedules": s.scheduler.list()})

	case "agent.schedule.remove":
		var p struct {
			ID string `json:"id"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.writeResult(msg.ID, map[string]bool{"removed": s.scheduler.remove(p.ID)})

	case "agent.secret.store":
		var p struct {
			Name   string `json:"name"`
			Type   string `json:"type"`
			Scope  string `json:"scope"`
			Value  string `json:"value"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Name == "" || p.Value == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		id := s.secrets.store(p.Name, p.Type, p.Scope, p.Value)
		s.writeResult(msg.ID, map[string]string{"id": id})

	case "agent.secret.request":
		var req SecretRequestParams
		if err := json.Unmarshal(msg.Params, &req); err != nil || req.ID == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		s.secrets.addPending(req)
		// Escalate to phone if device is connected.
		s.deviceMu.RLock()
		dev := s.device
		s.deviceMu.RUnlock()
		if dev != nil && dev.PushBackendURL != "" {
			go s.postSecretRequestPush(dev, req)
		}
		s.writeResult(msg.ID, map[string]bool{"pending": true})

	case "agent.secret.authorize":
		var p struct {
			RequestID string  `json:"requestId"`
			Scope     string  `json:"scope"`
			ExpiresAt *string `json:"expiresAt,omitempty"`
			OneTime   bool    `json:"oneTime"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.RequestID == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		var expiresAt *time.Time
		if p.ExpiresAt != nil {
			if t, err := time.Parse(time.RFC3339, *p.ExpiresAt); err == nil {
				expiresAt = &t
			}
		}
		if err := s.secrets.authorize(p.RequestID, p.Scope, expiresAt, p.OneTime, "user"); err != nil {
			s.writeError(msg.ID, -32602, err.Error())
			return
		}
		s.secrets.removePending(p.RequestID)
		s.writeResult(msg.ID, map[string]bool{"ok": true})

	case "agent.secret.revoke":
		var p struct {
			RequestID string `json:"requestId"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.writeResult(msg.ID, map[string]bool{"removed": s.secrets.revoke(p.RequestID)})

	case "agent.secret.delete":
		var p struct {
			SecretID string `json:"secretId"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.writeResult(msg.ID, map[string]bool{"removed": s.secrets.delete(p.SecretID)})

	case "agent.secret.list":
		secrets := s.secrets.list()
		pending := s.secrets.listPending()
		s.writeResult(msg.ID, map[string]interface{}{
			"secrets": secrets,
			"pending": pending,
		})

	case "agent.git.status":
		var p struct {
			Workdir string `json:"workdir"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Workdir == "" {
			s.writeError(msg.ID, -32602, "workdir required")
			return
		}
		status, err := s.gitStatus(p.Workdir)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, status)

	case "agent.git.diff":
		var p struct {
			Workdir string `json:"workdir"`
			Path    string `json:"path"`
			Staged  bool   `json:"staged"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Workdir == "" {
			s.writeError(msg.ID, -32602, "workdir required")
			return
		}
		diff, err := s.gitDiff(p.Workdir, p.Path, p.Staged)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, map[string]string{"diff": diff})

	case "agent.git.changedFiles":
		var p struct {
			Workdir    string `json:"workdir"`
			BaseBranch string `json:"baseBranch"`
			Branch     string `json:"branch"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Workdir == "" {
			s.writeError(msg.ID, -32602, "workdir required")
			return
		}
		files, err := s.gitChangedFiles(p.Workdir, p.BaseBranch, p.Branch)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, map[string]interface{}{"files": files})

	case "agent.fs.ls":
		var p struct {
			Path string `json:"path"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		res, err := s.fsList(p.Path)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, res)

	case "agent.commands.list":
		var p struct {
			Cwd    string `json:"cwd"`
			Vendor string `json:"vendor"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		// Read-only scan of the workspace's command/skill dirs. Never errors —
		// an empty list is a valid answer (no custom commands), so the composer
		// autocomplete degrades gracefully.
		s.writeResult(msg.ID, map[string]interface{}{"commands": listAgentCommands(p.Cwd, p.Vendor)})

	case "agent.git.clone":
		var p struct {
			Repo      string `json:"repo"`
			ParentDir string `json:"parentDir"`
			Name      string `json:"name"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Repo == "" {
			s.writeError(msg.ID, -32602, "repo required")
			return
		}
		// A clone writes to the host filesystem and may fetch credentials —
		// audit it like the other privileged git writes.
		s.auditEntry(AuditEntry{Action: "git-clone", Kind: "git", Command: "clone " + p.Repo})
		res, err := s.gitClone(p.Repo, p.ParentDir, p.Name)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, res)

	case "agent.git.ship":
		var p shipParams
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.Workdir == "" || p.Message == "" {
			s.writeError(msg.ID, -32602, "workdir and message required")
			return
		}
		// A phone-triggered push/PR is a privileged write — audit it (the hash-chained
		// log is lancerd's source of truth for who shipped what).
		s.auditEntry(AuditEntry{Action: "git-ship", Kind: "git", Command: "ship " + p.Workdir})
		res, err := s.gitShip(p)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, res)

	case "agent.worktree.list":
		var p struct {
			Workdir string `json:"workdir"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		if p.Workdir == "" {
			// No workdir supplied: nothing to enumerate. Empty (not error) so the
			// board degrades gracefully on hosts without a configured workspace.
			s.writeResult(msg.ID, map[string]interface{}{"worktrees": []worktreeResult{}})
			return
		}
		trees, err := s.listWorktrees(p.Workdir)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, map[string]interface{}{"worktrees": trees})

	case "agent.ci.recent":
		var p struct {
			Repo  string `json:"repo"`
			Limit int    `json:"limit"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		events, err := s.recentCIEvents(p.Repo, p.Limit)
		if err != nil {
			s.writeError(msg.ID, -32000, err.Error())
			return
		}
		s.writeResult(msg.ID, events)

	case "lancer.device.register.apns":
		var p struct {
			PushBackendURL string `json:"pushBackendURL"`
			SessionID      string `json:"sessionId"`
			APNSToken      string `json:"apnsToken"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.APNSToken == "" || p.SessionID == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		if p.PushBackendURL != "" {
			go s.postDeviceTokenRegistration(p.PushBackendURL, p.SessionID, p.APNSToken)
		}
		s.writeResult(msg.ID, map[string]string{"ok": "true"})

	case "lancer.device.register.activity":
		var p struct {
			PushBackendURL string `json:"pushBackendURL"`
			SessionID      string `json:"sessionId"`
			ActivityToken  string `json:"activityToken"`
			IsPushToStart  bool   `json:"isPushToStart"`
		}
		if err := json.Unmarshal(msg.Params, &p); err != nil || p.ActivityToken == "" || p.SessionID == "" {
			s.writeError(msg.ID, -32602, "invalid params")
			return
		}
		if p.PushBackendURL != "" {
			go s.postActivityTokenRegistration(p.PushBackendURL, p.SessionID, p.ActivityToken, p.IsPushToStart)
		}
		s.writeResult(msg.ID, map[string]string{"ok": "true"})

	default:
		s.writeError(msg.ID, -32601, "method not found")
	}
}

func (s *server) handleHook(conn net.Conn, first []byte) {
	s.handleHookWithNotify(conn, first, func(event ApprovalEvent) error {
		notification, err := marshalPendingNotification(event)
		if err != nil {
			return err
		}
		s.writeFramed(notification)
		return nil
	}, s.deviceRegistered)
}

// deviceRegistered reports whether a phone has registered for push, i.e. there
// is some path by which a human could answer an escalated approval. Used as the
// reachability predicate for the legacy (non-resident) serve path.
func (s *server) deviceRegistered() bool {
	s.deviceMu.RLock()
	defer s.deviceMu.RUnlock()
	return s.device != nil
}

// relayPaired reports whether a phone is currently paired over the E2E relay, so
// an escalated approval can reach a human there even with no local attach client
// or registered push device. Without this, a relay-only setup auto-allows every
// escalation (the approval never reaches the paired phone).
func (s *server) relayPaired() bool {
	return s.e2e != nil && s.e2e.client != nil && s.e2e.client.isPaired()
}

// noClientGrace is how long an escalated approval waits for a client to appear
// when none is currently reachable. Short enough that a host's normal `claude`
// runs are not stalled (Finding #10), long enough to absorb a phone reconnect
// that is already in flight. Only risk tiers policy.PermitsNoClientGrace allows
// (low/medium) get this fast-approve fallback — see handleHookWithNotify.
const noClientGrace = 8 * time.Second

// handleHookWithNotify processes one PreToolUse approval over conn. clientReachable
// reports whether a human can answer right now (attach client connected and/or a
// push device registered). When it returns false on an escalation AND the event's
// risk tier is low/medium (policy.PermitsNoClientGrace), the hook waits only
// noClientGrace before FAST AUTO-APPROVING (fail-open) rather than blocking
// indefinitely — otherwise wiring the hook would stall normal on-host `claude`
// runs whenever no phone is attached (Finding #10; the host runs bypassPermissions,
// so the hook is the only gate and must not hang). A high/critical-risk event with
// no reachable client is NOT eligible for that grace: an unreachable approver is
// evidence of reduced trust in the environment, not evidence the action is safe to
// auto-approve, so it falls through to the same no-timeout-at-all wait a reachable
// client gets below — it just keeps waiting for an explicit human decision,
// however long that takes. Only the low/medium no-reachable-client path above is
// fail-closed-with-a-grace; neither a reachable client nor a high/critical-risk
// unreachable one is ever auto-denied or auto-approved on a timeout (owner
// directive 2026-07-02 — a pending approval must pause, never silently resolve,
// on a slow or absent tap).
func (s *server) handleHookWithNotify(conn net.Conn, first []byte, notify func(ApprovalEvent) error, clientReachable func() bool) {
	defer conn.Close()
	// No hard deadline: a reachable client may take arbitrarily long to answer
	// (see the wait below), and the no-client path bounds itself via
	// noClientGrace on waitWithTimeout rather than the connection deadline.
	conn.SetDeadline(time.Time{})

	var event ApprovalEvent
	if first != nil {
		if err := json.Unmarshal(first, &event); err != nil {
			fmt.Fprintf(conn, `{"error":"bad request"}`)
			return
		}
	} else if err := json.NewDecoder(conn).Decode(&event); err != nil {
		fmt.Fprintf(conn, `{"error":"bad request"}`)
		return
	}
	if event.ApprovalID == "" {
		fmt.Fprintf(conn, `{"error":"bad request"}`)
		return
	}
	event.ContentHash = computeContentHash(event.Command, event.Patch, event.CWD, event.ToolInput)

	eval := s.policy.evaluate(event)
	switch eval.Effect {
	case policy.EffectAllow:
		_ = s.audit.append(AuditEntry{
			Action:     "auto-allow",
			Agent:      event.Agent,
			Kind:       event.Kind,
			Command:    event.Command,
			Effect:     string(eval.Effect),
			Rule:       eval.MatchedRule,
			ApprovalID: event.ApprovalID,
		})
		_ = json.NewEncoder(conn).Encode(ApprovalDecision{ApprovalID: event.ApprovalID, Decision: "approve"})
		return
	case policy.EffectDeny:
		_ = s.audit.append(AuditEntry{
			Action:     "auto-deny",
			Agent:      event.Agent,
			Kind:       event.Kind,
			Command:    event.Command,
			Effect:     string(eval.Effect),
			Rule:       eval.MatchedRule,
			ApprovalID: event.ApprovalID,
		})
		_ = json.NewEncoder(conn).Encode(ApprovalDecision{ApprovalID: event.ApprovalID, Decision: "deny"})
		return
	}

	br := computeBlastRadius(event, eval.MatchedRule)
	event.Files = br.Files
	event.TouchesGit = br.TouchesGit
	event.TouchesNetwork = br.TouchesNetwork
	event.MatchedRule = br.MatchedRule
	event.Risk = eval.ScoredRisk

	_ = s.audit.append(AuditEntry{
		Action:     "escalate",
		Agent:      event.Agent,
		Kind:       event.Kind,
		Command:    event.Command,
		Effect:     string(eval.Effect),
		Rule:       eval.MatchedRule,
		ApprovalID: event.ApprovalID,
	})

	if event.RunID == "" {
		event.RunID = s.dispatcher.runForCWD(event.CWD, event.Agent)
	}

	decisionCh := s.approvals.add(event)
	if notify != nil {
		if err := notify(event); err != nil {
			fmt.Fprintf(conn, `{"error":"internal"}`)
			return
		}
	}

	// Send through E2E relay when paired (primary path over push backend)
	if s.e2e != nil {
		s.e2e.sendApproval(event)
	}

	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go s.postApprovalPush(dev, event)
	}

	// No reachable client (no attach + no registered push device): nobody can
	// answer. For a risk tier that permits it, wait only a short grace in case one
	// is mid-reconnect, then fail OPEN (auto-approve) so the host's normal `claude`
	// runs aren't stalled for 120s. High/critical risk skips this fast path
	// entirely and falls through to the general wait below.
	if clientReachable != nil && !clientReachable() && policy.PermitsNoClientGrace(event.Risk) {
		result, received := waitWithTimeout(decisionCh, noClientGrace)
		if !received {
			s.approvals.remove(event.ApprovalID)
			_ = s.audit.append(AuditEntry{
				Action:     "auto-allow-no-client",
				Agent:      event.Agent,
				Kind:       event.Kind,
				Command:    event.Command,
				Effect:     string(policy.EffectAsk),
				Rule:       event.MatchedRule,
				ApprovalID: event.ApprovalID,
			})
			_ = json.NewEncoder(conn).Encode(ApprovalDecision{ApprovalID: event.ApprovalID, Decision: "approve"})
			return
		}
		// A client appeared within the grace and recorded a decision — honor it.
		decision := result.decision
		if decision == "approveAlways" {
			decision = "approve"
		}
		_ = json.NewEncoder(conn).Encode(ApprovalDecision{
			ApprovalID:      event.ApprovalID,
			Decision:        decision,
			EditedToolInput: result.editedToolInput,
		})
		return
	}

	// A reachable client gets no timeout at all: block until an explicit human
	// decision arrives on decisionCh, however long that takes. Previously this
	// used waitWithTimeout(decisionCh, approvalTimeout) and auto-denied after
	// 120s; the owner hit that fail-closed default three times in live testing
	// (tapped Approve, got a silent auto-deny 120s later anyway) and asked for
	// it to just pause instead. There is deliberately no bound here — see the
	// no-reachable-client branch above for the one path that still times out.
	result := <-decisionCh
	decision := result.decision
	if decision == "approveAlways" {
		// The resolver (applyDecision) already recorded the decision and wrote the
		// always-policy; collapse to "approve" for the agent, which only
		// understands approve/deny. Do NOT record again here (avoids a duplicate
		// audit entry across the resolve + hook-wake paths).
		decision = "approve"
	}

	resp := ApprovalDecision{
		ApprovalID:      event.ApprovalID,
		Decision:        decision,
		EditedToolInput: result.editedToolInput,
	}
	_ = json.NewEncoder(conn).Encode(resp)
}

func (s *server) recordHumanDecision(event ApprovalEvent, decision string) {
	action := decision
	if decision != "approve" && decision != "approveAlways" {
		action = "deny"
	}
	_ = s.audit.append(AuditEntry{
		Action:     action,
		Agent:      event.Agent,
		Kind:       event.Kind,
		Command:    event.Command,
		Rule:       event.MatchedRule,
		ApprovalID: event.ApprovalID,
	})
}

func (s *server) writeResult(id interface{}, result interface{}) {
	msg := rpcMessage{JSONRPC: "2.0", ID: id, Result: result}
	data, _ := json.Marshal(msg)
	s.writeFramed(data)
}

func (s *server) writeError(id interface{}, code int, message string) {
	msg := rpcMessage{JSONRPC: "2.0", ID: id, Error: &rpcError{Code: code, Message: message}}
	data, _ := json.Marshal(msg)
	s.writeFramed(data)
}

// emitNotification marshals a JSON-RPC notification (no id) and writes it on the
// serialized writeFramed path, so concurrent run-output goroutines are safe.
// When the E2E relay is active it also fans out the notification over the relay.
func (s *server) emitNotification(method string, params any) {
	data, err := json.Marshal(map[string]any{"jsonrpc": "2.0", "method": method, "params": params})
	if err != nil {
		return
	}
	s.writeFramed(data)

	// Fan-out to E2E relay when paired.
	if s.e2e != nil {
		s.e2e.sendRelayNotification(method, params)
	}
}

func (s *server) writeFramed(data []byte) {
	s.emitMu.Lock()
	emit := s.emit
	s.emitMu.Unlock()
	if emit != nil {
		_ = emit(data)
		return
	}
	s.stdoutMu.Lock()
	defer s.stdoutMu.Unlock()
	length := uint32(len(data))
	_ = binary.Write(os.Stdout, binary.BigEndian, length)
	_, _ = os.Stdout.Write(data)
}

func (s *server) postApprovalPush(dev *registeredDevice, event ApprovalEvent) {
	hostname, _ := os.Hostname()
	tool := event.ToolName
	if tool == "" {
		tool = event.Kind
	}
	payload := map[string]interface{}{
		"id":        event.ApprovalID,
		"sessionId": dev.SessionID,
		"command":   event.Command,
		"risk":      riskLabel(event.Risk),
		"hostName":  hostname,
		"agent":     event.Agent,
		"toolName":  tool,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return
	}
	url := strings.TrimRight(dev.PushBackendURL, "/") + "/approval"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	// /approval is a Tier-1 control-plane endpoint (APPROVAL_RELAY_SECRET). Without
	// this header the backend 401s and the push is never sent — the last broken link
	// in app-closed approval delivery. Mirror postDeviceTokenRegistration.
	if secret := strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET")); secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "push-backend POST failed: %v\n", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		fmt.Fprintf(os.Stderr, "push-backend /approval rejected: HTTP %d\n", resp.StatusCode)
	}
}

func (s *server) postSecretRequestPush(dev *registeredDevice, req SecretRequestParams) {
	hostname, _ := os.Hostname()
	payload := map[string]interface{}{
		"id":             req.ID,
		"sessionId":      dev.SessionID,
		"agent":          req.Agent,
		"toolName":       req.ToolName,
		"credentialType": req.CredentialType,
		"requestedScope": req.RequestedScope,
		"hostName":       hostname,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return
	}
	url := strings.TrimRight(dev.PushBackendURL, "/") + "/secret-request"
	httpReq, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return
	}
	httpReq.Header.Set("Content-Type", "application/json")
	// Tier-1 endpoint — same Bearer auth as /approval and /register.
	if secret := strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET")); secret != "" {
		httpReq.Header.Set("Authorization", "Bearer "+secret)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		fmt.Fprintf(os.Stderr, "push-backend secret-request POST failed: %v\n", err)
		return
	}
	resp.Body.Close()
}

// postRelayRegistration registers sessionId → relayToken with the backend's
// control-plane /register endpoint, authenticated by APPROVAL_RELAY_SECRET (when
// configured). This lets the backend validate the per-session Bearer token the
// app and lancerd present on the decision relay. Never logs the relayToken.
func (s *server) postRelayRegistration(backendURL, sessionID, relayToken string) {
	body, err := json.Marshal(map[string]string{
		"sessionId":  sessionID,
		"relayToken": relayToken,
	})
	if err != nil {
		return
	}
	endpoint := strings.TrimRight(backendURL, "/") + "/register"
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if secret := strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET")); secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "relay-token registration POST failed: %v\n", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		fmt.Fprintf(os.Stderr, "relay-token registration rejected: HTTP %d\n", resp.StatusCode)
	}
}

func (s *server) postDeviceTokenRegistration(backendURL, sessionID, hexToken string) {
	body, err := json.Marshal(map[string]string{
		"sessionId":   sessionID,
		"deviceToken": hexToken,
	})
	if err != nil {
		return
	}
	endpoint := strings.TrimRight(backendURL, "/") + "/register"
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if secret := strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET")); secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "apns-token registration POST failed: %v\n", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		fmt.Fprintf(os.Stderr, "apns-token registration rejected: HTTP %d\n", resp.StatusCode)
	}
}

func (s *server) postActivityTokenRegistration(backendURL, sessionID, activityToken string, isPushToStart bool) {
	body, err := json.Marshal(map[string]interface{}{
		"sessionId":     sessionID,
		"activityToken": activityToken,
		"isPushToStart": isPushToStart,
	})
	if err != nil {
		return
	}
	endpoint := strings.TrimRight(backendURL, "/") + "/register-activity-token"
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if secret := strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET")); secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "activity-token registration POST failed: %v\n", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		fmt.Fprintf(os.Stderr, "activity-token registration rejected: HTTP %d\n", resp.StatusCode)
	}
}

func riskLabel(r int) string {
	switch r {
	case 1:
		return "medium"
	case 2:
		return "high"
	case 3:
		return "critical"
	default:
		return "low"
	}
}

// doctorCheckResult mirrors the Swift DoctorCheckResult struct.
type doctorCheckResult struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Passed   bool   `json:"passed"`
	Message  string `json:"message"`
	Severity string `json:"severity"`
}

// doctorReport mirrors the Swift DoctorReport struct.
type doctorReport struct {
	DaemonVersion string              `json:"daemonVersion"`
	Checks        []doctorCheckResult `json:"checks"`
	GeneratedAt   string              `json:"generatedAt"`
}

// collectDoctorReport runs all health checks and returns a doctorReport.
func (s *server) collectDoctorReport() doctorReport {
	home, _ := os.UserHomeDir()
	report := doctorReport{
		DaemonVersion: version,
		GeneratedAt:   time.Now().UTC().Format(time.RFC3339),
	}
	report.Checks = append(report.Checks, s.checkDaemonVersion())
	report.Checks = append(report.Checks, s.checkHooksInstalled(home))
	report.Checks = append(report.Checks, s.checkAgentAuth(home))
	report.Checks = append(report.Checks, s.checkPolicyParseable())
	report.Checks = append(report.Checks, s.checkFilesystemPermissions(home))
	report.Checks = append(report.Checks, s.checkLocalModelEndpoints())
	report.Checks = append(report.Checks, s.checkGitHubCLI())
	return report
}

// checkGitHubCLI reports whether `gh` is installed and authenticated — the
// prerequisite for the "Ship it" PR-create flow. A miss is a warning (not an
// error): commit + push still work; only PR creation is blocked.
func (s *server) checkGitHubCLI() doctorCheckResult {
	out, err := s.gitRun("", "gh", "auth", "status")
	if err != nil {
		low := strings.ToLower(out + " " + err.Error())
		msg := "gh not installed — install GitHub CLI to open PRs from Lancer"
		if !strings.Contains(low, "executable file not found") && !strings.Contains(low, "not found") {
			msg = "gh installed but not authenticated — run `gh auth login` (or set GH_TOKEN) to open PRs"
		}
		return doctorCheckResult{
			ID:       "github-cli",
			Name:     "GitHub CLI (Ship it / PR)",
			Passed:   false,
			Message:  msg,
			Severity: "warning",
		}
	}
	return doctorCheckResult{
		ID:       "github-cli",
		Name:     "GitHub CLI (Ship it / PR)",
		Passed:   true,
		Message:  "gh authenticated — PR creation available",
		Severity: "info",
	}
}

func (s *server) checkDaemonVersion() doctorCheckResult {
	if version == "0.1.0-dev" {
		return doctorCheckResult{
			ID:       "daemon-version",
			Name:     "Daemon version",
			Passed:   false,
			Message:  "Running development build (" + version + ")",
			Severity: "warning",
		}
	}
	return doctorCheckResult{
		ID:       "daemon-version",
		Name:     "Daemon version",
		Passed:   true,
		Message:  "lancerd " + version,
		Severity: "info",
	}
}

func (s *server) checkHooksInstalled(home string) doctorCheckResult {
	agents := []struct {
		name string
		path string
	}{
		{"claude", filepath.Join(home, ".claude", "settings.json")},
		{"codex", filepath.Join(home, ".codex", "config.json")},
		{"opencode", filepath.Join(home, ".config", "opencode", "config.json")},
	}
	var missing []string
	for _, a := range agents {
		if _, err := os.Stat(a.path); os.IsNotExist(err) {
			missing = append(missing, a.name)
		}
	}
	if len(missing) > 0 {
		return doctorCheckResult{
			ID:       "hooks-installed",
			Name:     "Agent hooks installed",
			Passed:   false,
			Message:  "Missing config for: " + strings.Join(missing, ", "),
			Severity: "warning",
		}
	}
	return doctorCheckResult{
		ID:       "hooks-installed",
		Name:     "Agent hooks installed",
		Passed:   true,
		Message:  "All agent configs found",
		Severity: "info",
	}
}

func (s *server) checkAgentAuth(home string) doctorCheckResult {
	type keyCheck struct {
		envKey string
		name   string
	}
	keys := []keyCheck{
		{"ANTHROPIC_API_KEY", "Anthropic"},
		{"OPENAI_API_KEY", "OpenAI"},
	}
	var configured []string
	var missing []string
	for _, k := range keys {
		if v := os.Getenv(k.envKey); v != "" {
			configured = append(configured, k.name)
		} else {
			missing = append(missing, k.name)
		}
	}
	if len(configured) == 0 {
		return doctorCheckResult{
			ID:       "agent-auth",
			Name:     "Agent authentication",
			Passed:   false,
			Message:  "No API keys found in environment",
			Severity: "error",
		}
	}
	msg := "Configured: " + strings.Join(configured, ", ")
	if len(missing) > 0 {
		msg += " | Missing: " + strings.Join(missing, ", ")
	}
	return doctorCheckResult{
		ID:       "agent-auth",
		Name:     "Agent authentication",
		Passed:   true,
		Message:  msg,
		Severity: "info",
	}
}

func (s *server) checkPolicyParseable() doctorCheckResult {
	_, err := s.policy.getPolicyDocuments("")
	if err != nil {
		return doctorCheckResult{
			ID:       "policy-parseable",
			Name:     "Policy parseable",
			Passed:   false,
			Message:  "Policy load error: " + err.Error(),
			Severity: "error",
		}
	}
	return doctorCheckResult{
		ID:       "policy-parseable",
		Name:     "Policy parseable",
		Passed:   true,
		Message:  "Policy loaded successfully",
		Severity: "info",
	}
}

func (s *server) checkFilesystemPermissions(home string) doctorCheckResult {
	lancerDir := filepath.Join(home, ".lancer")
	info, err := os.Stat(lancerDir)
	if os.IsNotExist(err) {
		return doctorCheckResult{
			ID:       "fs-permissions",
			Name:     "Filesystem permissions",
			Passed:   false,
			Message:  "~/.lancer/ does not exist",
			Severity: "error",
		}
	}
	if err != nil {
		return doctorCheckResult{
			ID:       "fs-permissions",
			Name:     "Filesystem permissions",
			Passed:   false,
			Message:  "Cannot stat ~/.lancer/: " + err.Error(),
			Severity: "error",
		}
	}
	// Check writable by testing a temp file
	testFile := filepath.Join(lancerDir, ".doctor-test")
	f, err := os.OpenFile(testFile, os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return doctorCheckResult{
			ID:       "fs-permissions",
			Name:     "Filesystem permissions",
			Passed:   false,
			Message:  "~/.lancer/ is not writable: " + err.Error(),
			Severity: "error",
		}
	}
	f.Close()
	os.Remove(testFile)

	mode := info.Mode().String()
	return doctorCheckResult{
		ID:       "fs-permissions",
		Name:     "Filesystem permissions",
		Passed:   true,
		Message:  "~/.lancer/ exists and is writable (" + mode + ")",
		Severity: "info",
	}
}

func (s *server) checkLocalModelEndpoints() doctorCheckResult {
	type endpoint struct {
		name string
		host string
		port string
	}
	endpoints := []endpoint{
		{"Ollama", "127.0.0.1", "11434"},
		{"LM Studio", "127.0.0.1", "1234"},
	}
	var reachable []string
	var unreachable []string
	for _, ep := range endpoints {
		conn, err := net.DialTimeout("tcp", ep.host+":"+ep.port, 500*time.Millisecond)
		if err == nil {
			conn.Close()
			reachable = append(reachable, ep.name)
		} else {
			unreachable = append(unreachable, ep.name)
		}
	}
	if len(reachable) == 0 {
		return doctorCheckResult{
			ID:       "local-models",
			Name:     "Local model endpoints",
			Passed:   false,
			Message:  "No local model servers detected (checked: " + strings.Join(unreachable, ", ") + ")",
			Severity: "info",
		}
	}
	return doctorCheckResult{
		ID:       "local-models",
		Name:     "Local model endpoints",
		Passed:   true,
		Message:  "Reachable: " + strings.Join(reachable, ", "),
		Severity: "info",
	}
}
