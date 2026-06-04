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

const (
	maxFrameBytes  = 16 * 1024 * 1024
	socketFileName = "conduitd.sock"
)

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
	mu          sync.RWMutex
	home        string
	docs        []policy.Document
	legacyJSON  string
	migrated    bool
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
	return out, nil
}

type server struct {
	approvals *approvalStore
	policy    *policyEngine
	audit     *auditLog
	stdoutMu  sync.Mutex
	deviceMu  sync.RWMutex
	device    *registeredDevice
}

func runServe() error {
	home, _ := os.UserHomeDir()
	s := &server{
		approvals: newApprovalStore(),
		policy:    newPolicyEngine(home),
		audit:     newAuditLog(home),
	}

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

	go s.acceptHooks(ln)
	return s.readStdio()
}

func (s *server) readStdio() error {
	for {
		var length uint32
		if err := binary.Read(os.Stdin, binary.BigEndian, &length); err != nil {
			if err == io.EOF {
				return nil
			}
			return fmt.Errorf("read length: %w", err)
		}
		if length == 0 || length > maxFrameBytes {
			return fmt.Errorf("invalid frame length: %d", length)
		}
		buf := make([]byte, length)
		if _, err := io.ReadFull(os.Stdin, buf); err != nil {
			return fmt.Errorf("read body: %w", err)
		}
		var msg rpcMessage
		if err := json.Unmarshal(buf, &msg); err != nil {
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
		event, ok := s.approvals.resolve(decision.ApprovalID, decision.Decision, decision.EditedToolInput)
		if ok {
			s.recordHumanDecision(event, decision.Decision)
			if decision.Decision == "approveAlways" {
				_ = s.policy.appendAllowAlways(event)
			}
		}
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
		s.device = &info
		s.deviceMu.Unlock()
		s.writeResult(msg.ID, "ok")

	default:
		s.writeError(msg.ID, -32601, "method not found")
	}
}

func (s *server) acceptHooks(ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go s.handleHook(conn)
	}
}

func (s *server) handleHook(conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(130 * time.Second))

	var event ApprovalEvent
	if err := json.NewDecoder(conn).Decode(&event); err != nil {
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
	if notification, err := marshalPendingNotification(event); err == nil {
		s.writeFramed(notification)
	}

	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go s.postApprovalPush(dev, event)
	}

	result := waitWithTimeout(decisionCh, 120*time.Second)
	decision := result.decision
	if decision == "approveAlways" {
		_ = s.policy.appendAllowAlways(event)
		decision = "approve"
	}
	s.recordHumanDecision(event, result.decision)

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
	s.stdoutMu.Lock()
	defer s.stdoutMu.Unlock()
	length := uint32(len(data))
	_ = binary.Write(os.Stdout, binary.BigEndian, length)
	_, _ = os.Stdout.Write(data)
}

func socketPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, ".conduit")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	return filepath.Join(dir, socketFileName), nil
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
