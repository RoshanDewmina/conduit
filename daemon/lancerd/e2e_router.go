package main

import (
	"encoding/json"
	"log"
	"os/exec"
)

// relayClient is the minimal interface the e2eRouter needs from a relay
// client. The production *e2eRelayClient satisfies it; tests can inject fakes.
type relayClient interface {
	isPaired() bool
	sendMessage(msgType string, payload []byte) error
	stop()
}

// e2eRouter bridges daemon events to the E2E relay.
// When the relay is connected, it sends approval events and status
// updates through the encrypted channel. It also handles incoming
// messages from the phone (approval responses).
type e2eRouter struct {
	client relayClient
	server *server
}

func newE2ERouter(client *e2eRelayClient, srv *server) *e2eRouter {
	r := &e2eRouter{client: client, server: srv}
	if client != nil {
		client.messageHandler = r.handleMessage
	}
	return r
}

// sendApproval routes an approval event through the E2E relay.
func (r *e2eRouter) sendApproval(ev ApprovalEvent) {
	if r.client == nil || !r.client.isPaired() {
		return
	}

	msg := map[string]interface{}{
		"type": "approvalPending",
		"payload": map[string]interface{}{
			"approvalID": ev.ApprovalID,
			"agent":      ev.Agent,
			"kind":       ev.Kind,
			"command":    ev.Command,
			"risk":       ev.Risk,
			"cwd":        ev.CWD,
			"toolName":   ev.ToolName,
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("e2e: marshal approval failed: %v", err)
		return
	}

	if err := r.client.sendMessage("approval", data); err != nil {
		log.Printf("e2e: send approval failed: %v", err)
	}
}

// sendStatusUpdate sends agent status through the E2E relay.
func (r *e2eRouter) sendStatusUpdate(agent string, model string, sessions int, spend float64, hostName string) {
	if r.client == nil || !r.client.isPaired() {
		return
	}

	msg := map[string]interface{}{
		"type": "agentStatus",
		"payload": map[string]interface{}{
			"agent":        agent,
			"model":        model,
			"sessionCount": sessions,
			"usageUSD":     spend,
			"hostName":     hostName,
		},
	}

	data, _ := json.Marshal(msg)
	_ = r.client.sendMessage("status", data)
}

// handleMessage processes incoming E2E messages from the phone.
// It is set as the client's messageHandler on construction.
func (r *e2eRouter) handleMessage(msgType string, payload []byte) {
	switch msgType {
	case "approvalResponse":
		var decision struct {
			ApprovalID      string `json:"approvalID"`
			Decision        string `json:"decision"`
			EditedToolInput string `json:"editedToolInput,omitempty"`
		}
		if err := json.Unmarshal(payload, &decision); err != nil {
			log.Printf("e2e: unmarshal approval response failed: %v", err)
			return
		}
		r.server.applyDecision(decision.ApprovalID, decision.Decision, decision.EditedToolInput)

	case "agentDispatch":
		var params struct {
			Agent     string  `json:"agent"`
			CWD       string  `json:"cwd"`
			Prompt    string  `json:"prompt"`
			Model     string  `json:"model,omitempty"`
			BudgetUSD float64 `json:"budgetUSD,omitempty"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			log.Printf("e2e: unmarshal agentDispatch failed: %v", err)
			return
		}
		dp := dispatchParams{
			Agent:     params.Agent,
			CWD:       params.CWD,
			Prompt:    params.Prompt,
			Model:     params.Model,
			BudgetUSD: params.BudgetUSD,
		}
		result := r.server.runDispatch(dp)

		// Send the dispatch result back over the relay. Streaming output/status
		// from the launched process flows through r.server.emitNotification,
		// which fans out to the relay via sendRelayNotification — no explicit
		// stream handling needed here.
		msg := map[string]interface{}{
			"type":    "dispatchResult",
			"payload": result,
		}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("dispatchResult", data)

	case "agentFsList":
		var params struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			log.Printf("e2e: unmarshal agentFsList failed: %v", err)
			return
		}
		// Mirror the dispatch arm: marshal the result (or an error string) under
		// {type, payload} and let r.client.sendMessage encrypt/wrap it. The phone
		// decodes the same shape via RelayInnerEnvelope<RelayDirListing>.
		res, err := r.server.fsList(params.Path)
		entries := res.Entries
		if entries == nil {
			entries = []fsEntry{} // emit [] not null so the phone always decodes
		}
		payloadOut := map[string]interface{}{
			"path":    res.Path,
			"parent":  res.Parent,
			"entries": entries,
		}
		if err != nil {
			payloadOut["error"] = err.Error()
		}
		msg := map[string]interface{}{
			"type":    "fsListResult",
			"payload": payloadOut,
		}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("fsListResult", data)

	case "agentCommandsList":
		var params struct {
			Cwd    string `json:"cwd"`
			Vendor string `json:"vendor"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			log.Printf("e2e: unmarshal agentCommandsList failed: %v", err)
			return
		}
		// Read-only scan; mirrors the agentFsList arm. The phone decodes the same
		// {commands:[...]} shape it gets from the direct DaemonChannel RPC.
		payloadOut := map[string]interface{}{
			"commands": listAgentCommands(params.Cwd, params.Vendor),
		}
		msg := map[string]interface{}{"type": "commandsListResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("commandsListResult", data)

	case "agentRunControl":
		var p struct {
			RunID  string `json:"runId"`
			Action string `json:"action"` // stop | pause | resume
		}
		if err := json.Unmarshal(payload, &p); err != nil {
			log.Printf("e2e: unmarshal agentRunControl failed: %v", err)
			return
		}
		r.server.applyRunControl(p.RunID, p.Action)

	case "agentRunContinue":
		var p struct {
			RunID     string  `json:"runId"`
			Prompt    string  `json:"prompt"`
			Agent     string  `json:"agent"`
			CWD       string  `json:"cwd"`
			Model     string  `json:"model"`
			BudgetUSD float64 `json:"budgetUSD"`
		}
		if err := json.Unmarshal(payload, &p); err != nil || p.RunID == "" {
			log.Printf("e2e: unmarshal agentRunContinue failed: %v", err)
			return
		}
		fb := continueFallback{Agent: p.Agent, CWD: p.CWD, Model: p.Model, BudgetUSD: p.BudgetUSD}
		result := r.server.runContinue(p.RunID, p.Prompt, fb)
		// Reply with the new runId; continued output streams under it via the
		// existing agentRunOutput/agentRunStatus fan-out.
		msg := map[string]interface{}{"type": "runContinueResult", "payload": result}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("runContinueResult", data)

	case "deviceRegister":
		// The phone registers its APNs device token over the relay so that
		// app-CLOSED approvals can be delivered by push. The SSH path does this
		// via the lancer.device.register(.apns) RPCs; the relay path had no
		// equivalent, so s.device stayed nil and postApprovalPush never fired —
		// the reason push never reached a relay-only device. This mirrors the
		// server.go lancer.device.register + .apns handlers.
		var p struct {
			SessionID      string `json:"sessionId"`
			APNSToken      string `json:"apnsToken"`
			PushBackendURL string `json:"pushBackendURL"`
		}
		if err := json.Unmarshal(payload, &p); err != nil || p.SessionID == "" {
			log.Printf("e2e: unmarshal deviceRegister failed: %v", err)
			return
		}
		srv := r.server
		srv.deviceMu.Lock()
		if srv.device == nil || srv.device.SessionID != p.SessionID || srv.relayToken == "" {
			if tok, err := generateRelayToken(); err == nil {
				srv.relayToken = tok
			}
		}
		srv.device = &registeredDevice{PushBackendURL: p.PushBackendURL, SessionID: p.SessionID}
		relayToken := srv.relayToken
		srv.deviceMu.Unlock()
		if p.PushBackendURL != "" {
			// Decision-relay Bearer (closed-app Approve/Reject returns via the
			// backend) + the APNs token the backend pushes to.
			go srv.postRelayRegistration(p.PushBackendURL, p.SessionID, relayToken)
			srv.poller.ensureRunning(p.PushBackendURL, p.SessionID, relayToken)
			if p.APNSToken != "" {
				go srv.postDeviceTokenRegistration(p.PushBackendURL, p.SessionID, p.APNSToken)
			}
		}

	case "agentAgentsInstalled":
		payloadOut := map[string]interface{}{"agents": installedAgents(exec.LookPath)}
		data, _ := json.Marshal(map[string]interface{}{"type": "agentsInstalledResult", "payload": payloadOut})
		_ = r.client.sendMessage("agentsInstalledResult", data)

	case "agentSessionsList":
		var p struct {
			HomeDir string `json:"homeDir,omitempty"`
		}
		if err := json.Unmarshal(payload, &p); err != nil {
			log.Printf("e2e: unmarshal agentSessionsList failed: %v", err)
			return
		}
		sessions, err := buildSessionIndex(p.HomeDir)
		if sessions == nil {
			sessions = []SessionInfo{}
		}
		payloadOut := map[string]interface{}{"sessions": sessions}
		if err != nil {
			payloadOut["error"] = err.Error()
		}
		msg := map[string]interface{}{"type": "sessionsListResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("sessionsListResult", data)

	case "agentSessionsTranscript":
		var p struct {
			SessionID string `json:"sessionId"`
			SinceLine int    `json:"sinceLine"`
		}
		if err := json.Unmarshal(payload, &p); err != nil || p.SessionID == "" {
			log.Printf("e2e: unmarshal agentSessionsTranscript failed: %v", err)
			return
		}
		result, err := loadSessionTranscript("", p.SessionID, p.SinceLine)
		log.Printf("e2e: transcript sessionId=%q since=%d → %d msgs, err=%v", p.SessionID, p.SinceLine, len(result.Messages), err)
		payloadOut := map[string]interface{}{
			"messages":      result.Messages,
			"nextLine":      result.NextLine,
			"resetRequired": result.ResetRequired,
		}
		if err != nil {
			payloadOut["error"] = err.Error()
		}
		msg := map[string]interface{}{"type": "sessionsTranscriptResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("sessionsTranscriptResult", data)

	case "agentSessionContinue":
		var p observedSessionContinueParams
		if err := json.Unmarshal(payload, &p); err != nil ||
			p.Vendor == "" || p.SessionID == "" || p.CWD == "" || p.Prompt == "" {
			log.Printf("e2e: unmarshal agentSessionContinue failed: %v", err)
			return
		}
		// Mirrors the agentRunContinue arm: same core logic as the SSH transport's
		// agent.observedSession.continue (runObservedSessionContinue re-passes the
		// same policy/budget gates via dispatcher.resumeObservedSession).
		result := r.server.runObservedSessionContinue(p)
		msg := map[string]interface{}{"type": "sessionContinueResult", "payload": result}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("sessionContinueResult", data)

	default:
		log.Printf("e2e: unhandled message type: %s", msgType)
	}
}

// sendRelayNotification forwards a JSON-RPC-style notification through the E2E
// relay as an encrypted message. The iOS side maps these back to their original
// meaning (e.g. agentRunOutput → agent.run.output).
func (r *e2eRouter) sendRelayNotification(method string, params any) {
	if r.client == nil || !r.client.isPaired() {
		return
	}
	relayType := methodToRelayType(method)
	if relayType == "" {
		return
	}
	msg := map[string]interface{}{
		"type":    relayType,
		"payload": params,
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	_ = r.client.sendMessage(relayType, data)
}

func methodToRelayType(method string) string {
	switch method {
	case "agent.run.output":
		return "agentRunOutput"
	case "agent.run.status":
		return "agentRunStatus"
	case "agent.tool.start":
		return "agentToolStart"
	case "agent.artifact":
		return "agentArtifact"
	default:
		return ""
	}
}
