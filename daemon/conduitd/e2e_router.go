package main

import (
	"encoding/json"
	"log"
)

// e2eRouter bridges daemon events to the E2E relay.
// When the relay is connected, it sends approval events and status
// updates through the encrypted channel. It also handles incoming
// messages from the phone (approval responses).
type e2eRouter struct {
	client *e2eRelayClient
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
func (r *e2eRouter) sendStatusUpdate(agent string, model string, sessions int, spend float64) {
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

	default:
		log.Printf("e2e: unhandled message type: %s", msgType)
	}
}
