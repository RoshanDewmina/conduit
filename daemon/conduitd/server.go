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
)

const (
	maxFrameBytes  = 16 * 1024 * 1024 // 16 MB
	socketFileName = "conduitd.sock"
)

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

// server bridges the iOS DaemonChannel (stdio) and agent hooks (Unix socket).
type server struct {
	approvals *approvalStore
	stdoutMu  sync.Mutex // serialize writes to stdout
	deviceMu  sync.RWMutex
	device    *registeredDevice
}

func runServe() error {
	s := &server{approvals: newApprovalStore()}

	sockPath, err := socketPath()
	if err != nil {
		return fmt.Errorf("socket path: %w", err)
	}
	_ = os.Remove(sockPath) // remove stale socket

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return fmt.Errorf("listen unix %s: %w", sockPath, err)
	}
	defer func() { ln.Close(); os.Remove(sockPath) }()

	// Accept agent-hook connections in background.
	go s.acceptHooks(ln)

	// Read JSON-RPC frames from stdin (iOS DaemonChannel).
	return s.readStdio()
}

// readStdio processes length-prefixed JSON-RPC frames from stdin.
// Each frame: 4-byte big-endian length (uint32) + JSON body.
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

// handleMessage dispatches an incoming JSON-RPC message from the iOS app.
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
		s.approvals.resolve(decision.ApprovalID, decision.Decision)
		s.writeResult(msg.ID, "ok")

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

// acceptHooks accepts Unix socket connections from agent-hook subprocesses.
func (s *server) acceptHooks(ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go s.handleHook(conn)
	}
}

// handleHook reads a single ApprovalEvent from an agent-hook connection,
// forwards it to the iOS app, waits for the decision, and writes it back.
func (s *server) handleHook(conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(130 * time.Second))

	var event ApprovalEvent
	if err := json.NewDecoder(conn).Decode(&event); err != nil {
		fmt.Fprintf(conn, `{"error":"bad request"}`)
		return
	}

	// Register pending approval and forward to iOS.
	decisonCh := s.approvals.add(event)

	notification, err := marshalPendingNotification(event)
	if err == nil {
		s.writeFramed(notification)
	}

	// Attempt APNs push for backgrounded/killed app. Runs in a goroutine so it
	// doesn't delay the approval wait channel.
	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go s.postApprovalPush(dev, event)
	}

	// Wait for iOS decision (max 120 s).
	decision := waitWithTimeout(decisonCh, 120*time.Second)

	resp := ApprovalDecision{ApprovalID: event.ApprovalID, Decision: decision}
	json.NewEncoder(conn).Encode(resp)
}

// writeResult sends a JSON-RPC success response to stdout.
func (s *server) writeResult(id interface{}, result interface{}) {
	msg := rpcMessage{JSONRPC: "2.0", ID: id, Result: result}
	data, _ := json.Marshal(msg)
	s.writeFramed(data)
}

// writeError sends a JSON-RPC error response to stdout.
func (s *server) writeError(id interface{}, code int, message string) {
	msg := rpcMessage{JSONRPC: "2.0", ID: id, Error: &rpcError{Code: code, Message: message}}
	data, _ := json.Marshal(msg)
	s.writeFramed(data)
}

// writeFramed writes a length-prefixed frame to stdout.
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

// postApprovalPush POSTs an approval-pending event to the push backend so the
// iOS device receives an APNs alert even when the SSH channel is down.
func (s *server) postApprovalPush(dev *registeredDevice, event ApprovalEvent) {
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

// riskLabel converts a numeric risk level to a string label.
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
