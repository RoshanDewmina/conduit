package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const maxFrameBytes = 16 * 1024 * 1024 // 16 MB

// rpcMessage is the minimal JSON-RPC 2.0 envelope.
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

// registeredDevice holds the push routing info sent from the iOS app.
type registeredDevice struct {
	PushBackendURL string `json:"pushBackendURL"`
	SessionID      string `json:"sessionID"`
}

// bridge owns approval state, always-rules, device registration, and framed outbound I/O.
type bridge struct {
	approvals *approvalStore
	always    *alwaysRuleStore
	deviceMu  sync.RWMutex
	device    *registeredDevice
	emitMu    sync.Mutex
	emit      func([]byte) error
}

func newBridge() *bridge {
	return &bridge{
		approvals: newApprovalStore(),
		always:    newAlwaysRuleStore(),
	}
}

func (b *bridge) setEmitter(emit func([]byte) error) {
	b.emitMu.Lock()
	b.emit = emit
	b.emitMu.Unlock()
}

func (b *bridge) writeFramed(data []byte) {
	b.emitMu.Lock()
	emit := b.emit
	b.emitMu.Unlock()
	if emit == nil {
		return
	}
	_ = emit(data)
}

func (b *bridge) handleMessage(msg *rpcMessage) {
	switch msg.Method {
	case "ping":
		b.writeResult(msg.ID, "pong")

	case "agent.approval.response":
		var decision ApprovalDecision
		if err := json.Unmarshal(msg.Params, &decision); err != nil {
			b.writeError(msg.ID, -32602, "invalid params")
			return
		}
		event, ok := b.approvals.resolve(decision.ApprovalID, decision.Decision, decision.EditedToolInput)
		if ok && decision.Decision == "approveAlways" {
			b.always.add(alwaysRuleFromEvent(event))
		}
		b.writeResult(msg.ID, "ok")

	case "conduit.device.register":
		var info registeredDevice
		if err := json.Unmarshal(msg.Params, &info); err != nil {
			b.writeError(msg.ID, -32602, "invalid params")
			return
		}
		b.deviceMu.Lock()
		b.device = &info
		b.deviceMu.Unlock()
		b.writeResult(msg.ID, "ok")

	default:
		b.writeError(msg.ID, -32601, "method not found")
	}
}

func (b *bridge) handleHook(conn net.Conn, first []byte) {
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

	if b.always.matches(event) {
		_ = json.NewEncoder(conn).Encode(ApprovalDecision{ApprovalID: event.ApprovalID, Decision: "approve"})
		return
	}

	decisionCh := b.approvals.add(event)
	notification, err := marshalPendingNotification(event)
	if err == nil {
		b.writeFramed(notification)
	}

	b.deviceMu.RLock()
	dev := b.device
	b.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go b.postApprovalPush(dev, event)
	}

	result := waitWithTimeout(decisionCh, 120*time.Second)
	decision := result.decision
	if decision == "approveAlways" {
		b.always.add(alwaysRuleFromEvent(event))
		decision = "approve"
	}

	resp := ApprovalDecision{
		ApprovalID:      event.ApprovalID,
		Decision:        decision,
		EditedToolInput: result.editedToolInput,
	}
	_ = json.NewEncoder(conn).Encode(resp)
}

func (b *bridge) writeResult(id interface{}, result interface{}) {
	msg := rpcMessage{JSONRPC: "2.0", ID: id, Result: result}
	data, _ := json.Marshal(msg)
	b.writeFramed(data)
}

func (b *bridge) writeError(id interface{}, code int, message string) {
	msg := rpcMessage{JSONRPC: "2.0", ID: id, Error: &rpcError{Code: code, Message: message}}
	data, _ := json.Marshal(msg)
	b.writeFramed(data)
}

func (b *bridge) postApprovalPush(dev *registeredDevice, event ApprovalEvent) {
	hostname, _ := os.Hostname()
	payload := map[string]interface{}{
		"id":        event.ApprovalID,
		"sessionId": dev.SessionID,
		"command":   event.Command,
		"risk":      riskLabel(event.Risk),
		"hostName":  hostname,
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

// readStdioLoop reads length-prefixed JSON-RPC from r and dispatches to the bridge.
func (b *bridge) readStdioLoop(r io.Reader) error {
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
			b.writeError(nil, -32700, "parse error")
			continue
		}
		b.handleMessage(&msg)
	}
}
