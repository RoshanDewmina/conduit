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
		log.Printf("e2e: dropped approval %s — relay client not paired", ev.ApprovalID)
		return
	}

	msg := map[string]interface{}{
		"type": "approvalPending",
		"payload": map[string]interface{}{
			"approvalID":  ev.ApprovalID,
			"agent":       ev.Agent,
			"kind":        ev.Kind,
			"command":     ev.Command,
			"patch":       ev.Patch,
			"risk":        ev.Risk,
			"cwd":         ev.CWD,
			"toolName":    ev.ToolName,
			"toolInput":   ev.ToolInput,
			"contentHash": ev.ContentHash,
			"question":    ev.Question,
			"choices":     ev.Choices,
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

// sendApprovalResolved tells the phone a pending approval it may still be
// showing has been resolved server-side without a decision ever arriving from
// this client (the 120s fail-closed timeout fired). Lets a live client drop
// the stale card proactively instead of leaving it stuck until the user
// notices and re-opens it.
func (r *e2eRouter) sendApprovalResolved(approvalID, decision string) {
	if r.client == nil || !r.client.isPaired() {
		return
	}

	msg := map[string]interface{}{
		"type": "approvalResolved",
		"payload": map[string]interface{}{
			"approvalID": approvalID,
			"decision":   decision,
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("e2e: marshal approvalResolved failed: %v", err)
		return
	}

	if err := r.client.sendMessage("approvalResolved", data); err != nil {
		log.Printf("e2e: send approvalResolved failed: %v", err)
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
			ContentHash     string `json:"contentHash,omitempty"`
		}
		if err := json.Unmarshal(payload, &decision); err != nil {
			log.Printf("e2e: unmarshal approval response failed: %v", err)
			return
		}
		_, ok := r.server.applyDecision(decision.ApprovalID, decision.Decision, decision.EditedToolInput, decision.ContentHash)
		// Every other phone-initiated message in this switch replies with a
		// typed …Result so the caller has a real round trip to await. This one
		// never did — the phone treated a successful *outgoing* send as proof
		// of delivery, with no way to learn the daemon actually processed it
		// (dropped frame, decrypt failure, already-resolved approval, or a
		// content-hash mismatch all looked identical to "it worked"). Send an
		// explicit ack so it doesn't have to guess.
		ackMsg := map[string]interface{}{
			"type": "approvalResponseAck",
			"payload": map[string]interface{}{
				"approvalID": decision.ApprovalID,
				"ok":         ok,
			},
		}
		ackData, err := json.Marshal(ackMsg)
		if err != nil {
			log.Printf("e2e: marshal approvalResponseAck failed: %v", err)
			return
		}
		if err := r.client.sendMessage("approvalResponseAck", ackData); err != nil {
			log.Printf("e2e: send approvalResponseAck failed: %v", err)
		}

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

	case "agentFsRead":
		var params struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			log.Printf("e2e: unmarshal agentFsRead failed: %v", err)
			return
		}
		// Mirror the agentFsList arm: marshal the result (or an error string)
		// under {type, payload} and let r.client.sendMessage encrypt/wrap it.
		res, err := r.server.fsRead(params.Path)
		payloadOut := map[string]interface{}{
			"path":      res.Path,
			"content":   res.Content,
			"truncated": res.Truncated,
		}
		if err != nil {
			payloadOut["error"] = err.Error()
		}
		msg := map[string]interface{}{
			"type":    "fsReadResult",
			"payload": payloadOut,
		}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("fsReadResult", data)

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

	case "agentStatusQuery":
		// On-demand status for a relay-only phone (no SSH DaemonChannel), mirroring
		// the SSH agent.status RPC (server.go). Uses the same s.queryAgentStatus so
		// both transports report identical behavior — no new daemon business logic.
		var p struct {
			HomeDir string `json:"homeDir,omitempty"`
		}
		if err := json.Unmarshal(payload, &p); err != nil {
			log.Printf("e2e: unmarshal agentStatusQuery failed: %v", err)
			return
		}
		result := r.server.queryAgentStatus(p.HomeDir)
		msg := map[string]interface{}{"type": "agentStatusQueryResult", "payload": result}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentStatusQueryResult", data)

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
		// Tell the phone the relayToken it just caused us to (re)generate, so its
		// own decision-POST fallback (ApprovalRelay.postDecisionToBackend) can
		// authenticate. Without this reply the relay-only path (no SSH channel,
		// which is the only other place the phone ever learns this token) never
		// receives it, so `forwardDecisionOnly`'s backend-POST fallback is a
		// silent, permanent no-op — the direct bridge send (`approvalResponse`)
		// becomes the ONLY delivery path, with no safety net if it ever misses
		// its ack (stale bridge after a re-pair, a dropped frame, a slow relay
		// hop) — the daemon's 120s fail-closed timeout then denies the approval
		// with the phone never having had a working way to answer.
		ackPayload := map[string]interface{}{"relayToken": relayToken}
		ackMsg := map[string]interface{}{"type": "deviceRegistered", "payload": ackPayload}
		if data, err := json.Marshal(ackMsg); err == nil {
			_ = r.client.sendMessage("deviceRegistered", data)
		}

	case "activityTokenRegister":
		// Forwards a Live Activity (ActivityKit) push or push-to-start token to
		// push-backend on the phone's behalf — mirrors deviceRegister above, but
		// for the Live Activity token instead of the APNs device token. Without
		// this handler the phone's activityTokenRegister sends were silently
		// dropped ("unhandled message type"), so a relay-only pairing's Live
		// Activity tokens never reached push-backend and closed-app push-driven
		// updates never worked, regardless of the client-side lifecycle fix.
		var ap struct {
			SessionID      string `json:"sessionId"`
			ActivityToken  string `json:"activityToken"`
			IsPushToStart  bool   `json:"isPushToStart"`
			PushBackendURL string `json:"pushBackendURL"`
		}
		if err := json.Unmarshal(payload, &ap); err != nil || ap.SessionID == "" || ap.ActivityToken == "" {
			log.Printf("e2e: unmarshal activityTokenRegister failed: %v", err)
			return
		}
		if ap.PushBackendURL != "" {
			go r.server.postActivityTokenRegistration(ap.PushBackendURL, ap.SessionID, ap.ActivityToken, ap.IsPushToStart)
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

	case "agentConversationsList":
		var req conversationListRequest
		if len(payload) > 0 {
			if err := json.Unmarshal(payload, &req); err != nil {
				log.Printf("e2e: unmarshal agentConversationsList failed: %v", err)
				return
			}
		}
		// Mirrors the SSH agent.conversations.list arm (server.go) exactly — same
		// r.server.conversationsList call — so both transports return an
		// identical payload shape by construction, not by convention.
		result, err := r.server.conversationsList(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "agentConversationsListResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentConversationsListResult", data)

	case "agentConversationsFetch":
		var req conversationFetchRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal agentConversationsFetch failed: %v", err)
			return
		}
		result, err := r.server.conversationsFetch(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "agentConversationsFetchResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentConversationsFetchResult", data)

	case "agentConversationsAppend":
		var req conversationAppendRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal agentConversationsAppend failed: %v", err)
			return
		}
		// Mirrors the SSH agent.conversations.append arm. This DOES dispatch/
		// launch the vendor CLI process (via s.conversations.beginTurn +
		// dispatcher.launchConversationTurn inside conversationsAppend) — both
		// transports call the exact same r.server.conversationsAppend, so a
		// relay-only pairing gets identical dispatch behavior to SSH.
		result, err := r.server.conversationsAppend(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "agentConversationsAppendResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentConversationsAppendResult", data)

	case "agentConversationsArchive":
		var req conversationArchiveRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal agentConversationsArchive failed: %v", err)
			return
		}
		result, err := r.server.conversationsArchive(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "agentConversationsArchiveResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentConversationsArchiveResult", data)

	case "agentConversationsAttachObservedSession":
		var req conversationAttachObservedSessionRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal agentConversationsAttachObservedSession failed: %v", err)
			return
		}
		// See conversation_rpc.go's package doc comment: imports the observed
		// session's on-disk transcript into the ledger as one completed turn.
		result, err := r.server.conversationsAttachObservedSession(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "agentConversationsAttachObservedSessionResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentConversationsAttachObservedSessionResult", data)

	default:
		log.Printf("e2e: unhandled message type: %s", msgType)
	}
}

// conversationRelayPayload flattens a conversation RPC result struct into a
// map and adds an "error" key when err is non-nil — mirrors the
// agentFsList/agentFsRead convention above: a relay caller gets the same
// fields a successful response would have, plus "error" on failure, instead
// of a separate error envelope shape.
func conversationRelayPayload(result any, err error) map[string]interface{} {
	payload := map[string]interface{}{}
	if data, marshalErr := json.Marshal(result); marshalErr == nil {
		_ = json.Unmarshal(data, &payload)
	}
	if err != nil {
		payload["error"] = err.Error()
	}
	return payload
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
