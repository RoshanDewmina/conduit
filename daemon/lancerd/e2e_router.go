package main

import (
	"encoding/json"
	"log"
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
			RunID  string `json:"runId"`
			Prompt string `json:"prompt"`
		}
		if err := json.Unmarshal(payload, &p); err != nil || p.RunID == "" {
			log.Printf("e2e: unmarshal agentRunContinue failed: %v", err)
			return
		}
		result := r.server.runContinue(p.RunID, p.Prompt)
		// Reply with the new runId; continued output streams under it via the
		// existing agentRunOutput/agentRunStatus fan-out.
		msg := map[string]interface{}{"type": "runContinueResult", "payload": result}
		data, _ := json.Marshal(msg)
		_ = r.client.sendMessage("runContinueResult", data)

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
	case "agent.artifact":
		return "agentArtifact"
	default:
		return ""
	}
}
