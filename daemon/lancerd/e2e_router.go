package main

import (
	"encoding/json"
	"log"
	"os/exec"
	"sync"
	"time"

	"lancer/lancerd/policy"
)

// e2eApprovalRetry{InitialDelay,MaxDelay,Window} bound sendApproval's
// short-lived background retry when the relay client is not yet paired at
// delivery time (see sendApproval doc comment for the race this closes).
// Vars, not consts, so tests can shrink them to run the whole retry loop in
// milliseconds instead of real seconds.
var (
	e2eApprovalRetryInitialDelay = 200 * time.Millisecond
	e2eApprovalRetryMaxDelay     = 2 * time.Second
	e2eApprovalRetryWindow       = 10 * time.Second
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

	termClientMu sync.Mutex
	termClient   *relayTerminalClient

	// approvalRetryDoneForTest, when non-nil, receives an approval's ID after
	// its background retrySendApproval goroutine finishes (delivered or gave
	// up). Production code never sets this (nil ⇒ no-op send, matching every
	// other *ForTest seam in this package, e.g. decisionPoller.pollIntervalForTest).
	// Tests that shrink e2eApprovalRetry* to run the loop in milliseconds
	// still need this rather than a time.Sleep margin: time.Sleep gives no
	// happens-before edge against another goroutine, so the race detector
	// (correctly) flags a plain sleep-then-read as racy against the
	// goroutine's own log/sendMessage calls no matter how long the sleep is.
	// A channel receive is a real synchronization point.
	approvalRetryDoneForTest chan string
}

func newE2ERouter(client *e2eRelayClient, srv *server) *e2eRouter {
	r := &e2eRouter{client: client, server: srv}
	if client != nil {
		client.messageHandler = r.handleMessage
		client.pairedHandler = func() {
			r.resendPendingApprovals()
			r.resendPendingQuestions()
		}
	}
	return r
}

// resendPendingApprovals pushes every still-unresolved approval to the phone.
// Called on every peer_joined: an approval escalated while the phone was
// disconnected (or while the relay held an orphaned connection for either
// role) would otherwise never reach it — the send once looked successful, so
// nothing retries. The phone upserts by approval ID, so duplicates are
// harmless.
func (r *e2eRouter) resendPendingApprovals() {
	if r.server == nil {
		return
	}
	pending := r.server.approvals.pendingEvents()
	if len(pending) == 0 {
		return
	}
	log.Printf("e2e: re-sending %d pending approval(s) after (re)pair", len(pending))
	for _, ev := range pending {
		r.sendApproval(ev)
	}
}

// resendPendingQuestions pushes every still-unanswered question to the phone.
// Mirrors resendPendingApprovals: a question that arrived while the phone was
// disconnected would otherwise never reach it. The phone upserts by question
// ID, so duplicates are harmless.
func (r *e2eRouter) resendPendingQuestions() {
	if r.server == nil {
		return
	}
	pending := r.server.questions.pendingEvents()
	if len(pending) == 0 {
		return
	}
	log.Printf("e2e: re-sending %d pending question(s) after (re)pair", len(pending))
	for _, ev := range pending {
		r.sendQuestion(ev)
	}
}

// sendApproval routes an approval event through the E2E relay.
//
// A conversation-append that needs approval can call this within 0-1s of the
// daemon logging "e2e: paired with phone" — the literal pair-then-send
// workflow a first-time user follows. Live reproduction (2026-07-16,
// docs/test-runs/2026-07-16-untested-feature-sweep/LC-report.md) proved this
// isn't a fixed-point check: a relay identity change (e.g. the app's own
// onboarding flow re-registering) tears down an already-paired session and
// redials from scratch (resident.go's startRelayWatch → connectRelay), and
// the daemon can observe "connected to relay as daemon" long before the new
// session finishes its own peer_joined handshake — sometimes well over a
// minute later (observed: 09:48:57 connected, 09:50:55 paired in
// /tmp/sweep-C/daemon4.log from that reproduction). A conversation-append
// evaluated in that window sees isPaired()==false here.
//
// resendPendingApprovals (fired on the NEXT real peer_joined) is the durable
// backstop for that case — the event was already added to s.approvals before
// this call (deliverApprovalEvent), so it is never lost. But relying on it
// exclusively means the phone's synchronous needsApproval response (already
// rendered as a terminal error client-side — an iOS-side concern, out of
// scope here) has no live card to replace for however long the NEXT pairing
// takes. Retrying with short backoff for a bounded window covers the much
// more common case — the session finishing its handshake a moment later —
// without waiting on an unrelated future pairing event.
func (r *e2eRouter) sendApproval(ev ApprovalEvent) {
	if r.trySendApproval(ev) {
		return
	}
	go r.retrySendApproval(ev)
}

// trySendApproval makes one delivery attempt. Returns false (having already
// logged why) without sending anything when the client isn't paired.
func (r *e2eRouter) trySendApproval(ev ApprovalEvent) bool {
	if r.client == nil || !r.client.isPaired() {
		log.Printf("e2e: dropped approval %s — relay client not paired", ev.ApprovalID)
		return false
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
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("e2e: marshal approval failed: %v", err)
		return false
	}

	if err := r.client.sendMessage("approval", data); err != nil {
		log.Printf("e2e: send approval failed: %v", err)
		return false
	}
	log.Printf("e2e: sent approval %s over relay", ev.ApprovalID)
	return true
}

// retrySendApproval retries trySendApproval with short exponential backoff
// for a bounded window after an initial not-paired drop. It is not a
// replacement for resendPendingApprovals — that remains the durable backstop
// across an actual re-pair — this only closes the narrow gap where pairing
// finishes shortly after this specific call found isPaired() false.
func (r *e2eRouter) retrySendApproval(ev ApprovalEvent) {
	if r.approvalRetryDoneForTest != nil {
		defer func() { r.approvalRetryDoneForTest <- ev.ApprovalID }()
	}
	delay := e2eApprovalRetryInitialDelay
	deadline := time.Now().Add(e2eApprovalRetryWindow)
	for time.Now().Before(deadline) {
		time.Sleep(delay)
		if r.trySendApproval(ev) {
			log.Printf("e2e: delivered approval %s on retry after initial not-paired drop", ev.ApprovalID)
			return
		}
		delay *= 2
		if delay > e2eApprovalRetryMaxDelay {
			delay = e2eApprovalRetryMaxDelay
		}
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

// sendQuestion routes a QuestionEvent through the E2E relay. Relay "type" is
// "agentQuestion" — the relay kind the Lane E proposal names explicitly for
// this event, distinct from the "questionPending"-style naming an
// approval-mirroring guess would otherwise use.
func (r *e2eRouter) sendQuestion(ev QuestionEvent) {
	if r.client == nil || !r.client.isPaired() {
		log.Printf("e2e: dropped question %s — relay client not paired", ev.QuestionID)
		return
	}

	msg := map[string]interface{}{
		"type": "agentQuestion",
		"payload": map[string]interface{}{
			"questionID":    ev.QuestionID,
			"agent":         ev.Agent,
			"runId":         ev.RunID,
			"cwd":           ev.CWD,
			"questions":     ev.Questions,
			"allowFreeText": ev.AllowFreeText,
			"confidence":    ev.Confidence,
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("e2e: marshal question failed: %v", err)
		return
	}

	if err := r.client.sendMessage("agentQuestion", data); err != nil {
		log.Printf("e2e: send question failed: %v", err)
	} else {
		log.Printf("e2e: sent question %s over relay", ev.QuestionID)
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
	if r.handleTerminalMessage(msgType, payload) {
		return
	}
	switch msgType {
	case "approvalResponse":
		var decision struct {
			ApprovalID      string       `json:"approvalID"`
			Decision        string       `json:"decision"`
			EditedToolInput string       `json:"editedToolInput,omitempty"`
			ContentHash     string       `json:"contentHash,omitempty"`
			AllowRule       *policy.Rule `json:"allowRule,omitempty"`
		}
		if err := json.Unmarshal(payload, &decision); err != nil {
			log.Printf("e2e: unmarshal approval response failed: %v", err)
			return
		}
		event, ok := r.server.applyDecision(decision.ApprovalID, decision.Decision, decision.EditedToolInput, decision.ContentHash)
		if ok && decision.Decision == "approve" && decision.AllowRule != nil {
			r.server.applyAllowRule(event, decision.AllowRule)
		}
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

	case "questionAnswer":
		var answer QuestionAnswer
		if err := json.Unmarshal(payload, &answer); err != nil {
			log.Printf("e2e: unmarshal questionAnswer failed: %v", err)
			return
		}
		_, ok := r.server.applyQuestionAnswer(answer)
		// Mirrors approvalResponse's explicit ack below: a successful outgoing
		// send is not proof of delivery, so tell the phone whether the daemon
		// actually resolved the question rather than leaving it to guess.
		ackMsg := map[string]interface{}{
			"type": "questionAnswerAck",
			"payload": map[string]interface{}{
				"questionID": answer.QuestionID,
				"ok":         ok,
			},
		}
		ackData, err := json.Marshal(ackMsg)
		if err != nil {
			log.Printf("e2e: marshal questionAnswerAck failed: %v", err)
			return
		}
		if err := r.client.sendMessage("questionAnswerAck", ackData); err != nil {
			log.Printf("e2e: send questionAnswerAck failed: %v", err)
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

	case "attachmentPut":
		var params attachmentPutParams
		if err := json.Unmarshal(payload, &params); err != nil {
			log.Printf("e2e: unmarshal attachmentPut failed: %v", err)
			payloadOut := map[string]interface{}{
				"ok":    false,
				"error": err.Error(),
			}
			msg := map[string]interface{}{
				"type":    "attachmentPutResult",
				"payload": payloadOut,
			}
			data, _ := json.Marshal(msg)
			_ = r.client.sendMessage("attachmentPutResult", data)
			return
		}
		res, err := r.server.handleAttachmentPut(params)
		payloadOut := map[string]interface{}{
			"ok": res.OK,
		}
		if res.Path != "" {
			payloadOut["path"] = res.Path
		}
		if res.ID != "" {
			payloadOut["id"] = res.ID
		}
		if res.ContentDigest != "" {
			payloadOut["contentDigest"] = res.ContentDigest
		}
		if err != nil {
			payloadOut["error"] = err.Error()
		}
		msg := map[string]interface{}{
			"type":    "attachmentPutResult",
			"payload": payloadOut,
		}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("attachmentPutResult", data)

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

	case "agentEmergencyStop":
		stopped, denied := r.server.applyEmergencyStop()
		msg := map[string]interface{}{
			"type": "emergencyStopResult",
			"payload": map[string]interface{}{
				"emergencyStopped": true,
				"stoppedRuns":      stopped,
				"deniedApprovals":  denied,
			},
		}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("emergencyStopResult", data)

	case "agentEmergencyStopClear":
		payloadOut := map[string]interface{}{"emergencyStopped": false}
		if err := r.server.clearEmergencyStop(); err != nil {
			payloadOut["error"] = err.Error()
		}
		msg := map[string]interface{}{
			"type":    "emergencyStopClearResult",
			"payload": payloadOut,
		}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("emergencyStopClearResult", data)

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

	case "agentAuditTail":
		// Read-only mirror of the SSH agent.audit.tail RPC (server.go) for a
		// relay-only phone (no SSH DaemonChannel). Uses the same s.audit.tail so
		// both transports report identical entries — no new daemon business logic.
		var p struct {
			Limit int `json:"limit"`
		}
		if err := json.Unmarshal(payload, &p); err != nil {
			log.Printf("e2e: unmarshal agentAuditTail failed: %v", err)
			return
		}
		limit := p.Limit
		if limit <= 0 || limit > 500 {
			limit = 500
		}
		entries, err := r.server.audit.tail(limit)
		if entries == nil {
			entries = []AuditEntry{}
		}
		payloadOut := map[string]interface{}{"entries": entries}
		if err != nil {
			payloadOut["error"] = err.Error()
		}
		msg := map[string]interface{}{"type": "agentAuditTailResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentAuditTailResult", data)

	case "agentPermissionModeGet":
		// Coarse deny/ask/allow: real cwd → per-cwd override (else document
		// default); empty/"~" → document default only (Settings unchanged).
		var p struct {
			CWD string `json:"cwd"`
		}
		_ = json.Unmarshal(payload, &p)
		mode := r.server.policy.getPermissionMode(p.CWD)
		payloadOut := map[string]interface{}{"mode": mode}
		msg := map[string]interface{}{"type": "agentPermissionModeGetResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentPermissionModeGetResult", data)

	case "agentPermissionModeSet":
		// Writes coarse deny/ask/allow. Real cwd → per-cwd override (global
		// policy.yaml untouched). Empty/"~" → document Default only. Fails
		// closed: invalid mode rejected, storage left untouched.
		var p struct {
			Mode string `json:"mode"`
			CWD  string `json:"cwd"`
		}
		if err := json.Unmarshal(payload, &p); err != nil {
			log.Printf("e2e: unmarshal agentPermissionModeSet failed: %v", err)
			return
		}
		payloadOut := map[string]interface{}{"ok": false}
		if err := r.server.setPermissionModeAudited(p.Mode, "relay-phone", p.CWD); err != nil {
			payloadOut["error"] = err.Error()
		} else {
			payloadOut["ok"] = true
			payloadOut["mode"] = p.Mode
		}
		msg := map[string]interface{}{"type": "agentPermissionModeSetResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("agentPermissionModeSetResult", data)

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
		srv.savePersistedDevice(&registeredDevice{PushBackendURL: p.PushBackendURL, SessionID: p.SessionID})
		log.Printf("e2e: device registered for push (session %s, apnsToken=%v)", p.SessionID, p.APNSToken != "")
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
		if len(payload) > 0 {
			if err := json.Unmarshal(payload, &p); err != nil {
				log.Printf("e2e: unmarshal agentSessionsList failed: %v", err)
				return
			}
		}
		// Mirrors the SSH agent.sessions.list arm (server.go) exactly — same
		// buildSessionIndex call — so both transports return an identical
		// payload shape by construction, not by convention.
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
		// Mirrors the SSH agent.sessions.transcript arm (server.go) exactly —
		// same loadSessionTranscript call (including sinceLine caps and
		// resetRequired semantics) — so both transports return an identical
		// payload shape by construction, not by convention.
		result, err := loadSessionTranscript("", p.SessionID, p.SinceLine)
		messages := result.Messages
		if messages == nil {
			messages = []SessionMessage{}
		}
		payloadOut := map[string]interface{}{
			"messages":      messages,
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
		// Always echo request identity on the wire — error paths return a
		// zero-value conversationAppendResponse{}, and the phone's fail-closed
		// correlation drops results that omit clientTurnId (timeout vs host err).
		result.ClientTurnID = req.ClientTurnID
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

	case "repoTurnDiff":
		var req repoTurnDiffRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal repoTurnDiff failed: %v", err)
			return
		}
		result, err := r.server.repoTurnDiff(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "repoTurnDiffResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("repoTurnDiffResult", data)

	case "repoSessionDiff":
		var req repoSessionDiffRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal repoSessionDiff failed: %v", err)
			return
		}
		result, err := r.server.repoSessionDiff(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "repoSessionDiffResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("repoSessionDiffResult", data)

	case "repoFileDiff":
		var req repoFileDiffRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal repoFileDiff failed: %v", err)
			return
		}
		result, err := r.server.repoFileDiff(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "repoFileDiffResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("repoFileDiffResult", data)

	case "repoTree":
		var req repoTreeRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal repoTree failed: %v", err)
			return
		}
		result, err := r.server.repoTree(req)
		// SSH returns the directory-entry array as the JSON-RPC result; mirror
		// that on the relay (conversationRelayPayload expects a struct/map).
		var payloadOut interface{} = result
		if result == nil {
			payloadOut = []repoTreeEntry{}
		}
		if err != nil {
			payloadOut = map[string]interface{}{"error": err.Error()}
		}
		msg := map[string]interface{}{"type": "repoTreeResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("repoTreeResult", data)

	case "repoFile":
		var req repoFileRequest
		if err := json.Unmarshal(payload, &req); err != nil {
			log.Printf("e2e: unmarshal repoFile failed: %v", err)
			return
		}
		result, err := r.server.repoFile(req)
		payloadOut := conversationRelayPayload(result, err)
		msg := map[string]interface{}{"type": "repoFileResult", "payload": payloadOut}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("repoFileResult", data)

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
	case "agent.run.liveStatus":
		// Ephemeral status pill — never ledger-persisted (G3).
		return "runStatus"
	case "agent.run.receipt":
		return "runReceipt"
	case "agent.tool.start":
		return "agentToolStart"
	case "agent.artifact":
		return "agentArtifact"
	case "agent.ship.result":
		return "shipResult"
	default:
		return ""
	}
}
