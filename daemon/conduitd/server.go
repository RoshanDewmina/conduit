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
	"path/filepath"
	"strings"
	"sync"
	"time"

	"conduit/conduitd/policy"
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
		legacyJSON: filepath.Join(home, ".conduit", "always-rules.json"),
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
	dispatcher *dispatcher
	scheduler  *scheduler
	poller     *decisionPoller
	stdoutMu   sync.Mutex
	emitMu     sync.Mutex
	emit       func([]byte) error
	deviceMu   sync.RWMutex
	device     *registeredDevice
	// relayToken is the per-session capability secret minted at session attach
	// (conduit.device.register), delivered to the app over the DaemonChannel and
	// presented as `Authorization: Bearer <relayToken>` on the decision relay.
	// Guarded by deviceMu. TREAT AS SECRET — never log it.
	relayToken string
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
		dispatcher: newDispatcher(),
		scheduler:  newScheduler(home),
	}
	// The poller applies poll-delivered decisions through applyDecision so they
	// persist IDENTICALLY to the live-SSH respond path (audit + approveAlways
	// policy) — not via a bare resolve that skips both.
	s.poller = newDecisionPoller(s.applyDecision)
	// Run-control actions (pause/resume/stop/budget-exceeded) feed the same audit log.
	s.dispatcher.audit = s.auditEntry
	return s
}

// applyDecision resolves a pending approval and persists the outcome IDENTICALLY
// for every delivery path — the live-SSH `agent.approval.response` RPC and the
// phone→backend→poll fallback both route through here. resolve is the single
// delete-under-lock chokepoint, so this records at most once per approvalId.
// It writes the human-decision audit entry and, for approveAlways, the
// always-policy. FAIL-SAFE: a failed policy write is logged, never fatal — a
// dropped always-rule only means more prompting later, never an unintended allow.
func (s *server) applyDecision(id, decision, editedToolInput string) (ApprovalEvent, bool) {
	event, ok := s.approvals.resolve(id, decision, editedToolInput)
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
func (s *server) policyEffect(event ApprovalEvent) (string, string) {
	res := s.policy.evaluate(event)
	return string(res.Effect), res.MatchedRule
}

func (s *server) auditEntry(e AuditEntry) { _ = s.audit.append(e) }

// runDispatch applies the policy + budget gate and launches (used by RPC + scheduler).
func (s *server) runDispatch(p dispatchParams) dispatchResult {
	return s.dispatcher.dispatch(p, s.policyEffect, s.auditEntry)
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
			}
		}
	}()
}

// serverHome returns an isolated home directory when CONDUIT_STATE_DIR is set (tests).
func serverHome() string {
	home, _ := os.UserHomeDir()
	if state := os.Getenv("CONDUIT_STATE_DIR"); state != "" {
		home = filepath.Join(state, "home")
		_ = os.MkdirAll(filepath.Join(home, ".conduit"), 0700)
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
		"conduitd serve: resident daemon not reachable (%v); self-hosting socket (run `conduitd install` + `conduitd daemon` for a persistent bridge)\n",
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
		s.applyDecision(decision.ApprovalID, decision.Decision, decision.EditedToolInput)
		s.writeResult(msg.ID, "ok")

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

	case "agent.status":
		var params agentStatusParams
		if len(msg.Params) > 0 {
			if err := json.Unmarshal(msg.Params, &params); err != nil {
				s.writeError(msg.ID, -32602, "invalid params")
				return
			}
		}
		s.writeResult(msg.ID, collectAgentStatus(params.HomeDir))

	case "conduit.device.register":
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
		// conduitd's ~120s auto-deny remains the backstop.
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
	})
}

func (s *server) handleHookWithNotify(conn net.Conn, first []byte, notify func(ApprovalEvent) error) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(130 * time.Second))

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

	decisionCh := s.approvals.add(event)
	if notify != nil {
		if err := notify(event); err != nil {
			fmt.Fprintf(conn, `{"error":"internal"}`)
			return
		}
	}

	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go s.postApprovalPush(dev, event)
	}

	result, received := waitWithTimeout(decisionCh, 120*time.Second)
	decision := result.decision
	if !received {
		// Timed out: no resolver (RPC or poll) recorded a decision. Audit the
		// auto-deny here and retire the orphaned pending so a late relay decision
		// can't re-resolve it (which would mis-audit an approve / write an
		// always-rule after the agent was already denied). Fail-safe default-deny.
		s.approvals.remove(event.ApprovalID)
		s.recordHumanDecision(event, "deny")
		decision = "deny"
	} else if decision == "approveAlways" {
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
	resp, err := http.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		fmt.Fprintf(os.Stderr, "push-backend POST failed: %v\n", err)
		return
	}
	resp.Body.Close()
}

// postRelayRegistration registers sessionId → relayToken with the backend's
// control-plane /register endpoint, authenticated by APPROVAL_RELAY_SECRET (when
// configured). This lets the backend validate the per-session Bearer token the
// app and conduitd present on the decision relay. Never logs the relayToken.
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
