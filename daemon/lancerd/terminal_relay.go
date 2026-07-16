// Terminal relay handlers — Orca runtime RPC shape over Lancer's E2E relay.
//
// Ported from Orca (MIT, Lovecast Inc.) — https://github.com/stablyai/orca
// Sources: src/main/runtime/rpc/methods/terminal.ts,
//          src/shared/terminal-stream-protocol.ts
//
// Wire (phone ↔ daemon):
//   terminalCreate / terminalCreateResult
//   terminalAttach / terminalAttachResult
//   terminalSend / terminalSendResult
//   terminalResize / terminalResizeResult
//   terminalClose / terminalCloseResult
//   terminalList / terminalListResult
//   terminalSubscribe / terminalSubscribeResult
//   terminalStream  — base64 Orca binary frames (Output / Snapshot* / …)
package main

import (
	"encoding/base64"
	"encoding/json"
	"log"
	"sync/atomic"

	"github.com/google/uuid"

	"lancer/lancerd/terminal"
)

// relayTerminalClient fans PTY output to the paired phone as Orca stream frames.
type relayTerminalClient struct {
	router   *e2eRouter
	streamID uint32
	seq      atomic.Uint64
}

func (c *relayTerminalClient) OnData(sessionID string, data []byte, _ uint64) {
	if c.router == nil || c.router.client == nil || !c.router.client.isPaired() {
		return
	}
	seq := c.seq.Add(1)
	frame := terminal.EncodeStreamFrame(terminal.OpcodeOutput, c.streamID, seq, data)
	c.pushFrame(sessionID, frame)
}

func (c *relayTerminalClient) OnExit(sessionID string, code int) {
	if c.router == nil || c.router.client == nil || !c.router.client.isPaired() {
		return
	}
	payload, _ := json.Marshal(map[string]interface{}{
		"sessionId": sessionID,
		"exitCode":  code,
	})
	seq := c.seq.Add(1)
	frame := terminal.EncodeStreamFrame(terminal.OpcodeMetadata, c.streamID, seq, payload)
	c.pushFrame(sessionID, frame)
}

func (c *relayTerminalClient) pushFrame(sessionID string, frame []byte) {
	msg := map[string]interface{}{
		"type": "terminalStream",
		"payload": map[string]interface{}{
			"sessionId": sessionID,
			"frame":     base64.StdEncoding.EncodeToString(frame),
		},
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	if err := c.router.client.sendMessage("terminalStream", data); err != nil {
		log.Printf("e2e: send terminalStream failed: %v", err)
	}
}

func (c *relayTerminalClient) pushSnapshot(sessionID string, snap *terminal.Snapshot) {
	if snap == nil || snap.SnapshotAnsi == "" {
		return
	}
	ansi := []byte(snap.SnapshotAnsi)
	seq := c.seq.Add(1)
	c.pushFrame(sessionID, terminal.EncodeStreamFrame(terminal.OpcodeSnapshotStart, c.streamID, seq, nil))
	// Chunk large snapshots so relay frames stay manageable.
	const chunk = 24 * 1024
	for i := 0; i < len(ansi); i += chunk {
		end := i + chunk
		if end > len(ansi) {
			end = len(ansi)
		}
		seq = c.seq.Add(1)
		c.pushFrame(sessionID, terminal.EncodeStreamFrame(terminal.OpcodeSnapshotChunk, c.streamID, seq, ansi[i:end]))
	}
	meta, _ := json.Marshal(map[string]interface{}{
		"cols":           snap.Cols,
		"rows":           snap.Rows,
		"outputSequence": snap.OutputSequence,
		"cwd":            snap.CWD,
	})
	seq = c.seq.Add(1)
	c.pushFrame(sessionID, terminal.EncodeStreamFrame(terminal.OpcodeSnapshotEnd, c.streamID, seq, meta))
}

func (s *server) terminalHost() *terminal.Host {
	s.termOnce.Do(func() {
		s.termHost = terminal.NewHost()
	})
	return s.termHost
}

func (r *e2eRouter) handleTerminalMessage(msgType string, payload []byte) bool {
	switch msgType {
	case "terminalCreate":
		r.handleTerminalCreate(payload)
		return true
	case "terminalAttach":
		r.handleTerminalAttach(payload)
		return true
	case "terminalSend":
		r.handleTerminalSend(payload)
		return true
	case "terminalResize":
		r.handleTerminalResize(payload)
		return true
	case "terminalClose":
		r.handleTerminalClose(payload)
		return true
	case "terminalList":
		r.handleTerminalList(payload)
		return true
	case "terminalSubscribe":
		r.handleTerminalSubscribe(payload)
		return true
	default:
		return false
	}
}

func (r *e2eRouter) handleTerminalCreate(payload []byte) {
	var req struct {
		SessionID string            `json:"sessionId"`
		CWD       string            `json:"cwd"`
		Cols      int               `json:"cols"`
		Rows      int               `json:"rows"`
		Command   string            `json:"command"`
		Env       map[string]string `json:"env"`
	}
	if err := json.Unmarshal(payload, &req); err != nil {
		r.replyTerminalError("terminalCreateResult", "", "invalid terminalCreate payload")
		return
	}
	if req.SessionID == "" {
		req.SessionID = "term-" + uuid.NewString()
	}
	if req.Cols <= 0 {
		req.Cols = 80
	}
	if req.Rows <= 0 {
		req.Rows = 24
	}

	client := r.ensureRelayTerminalClient()
	result, err := r.server.terminalHost().CreateOrAttach(terminal.CreateOrAttachOptions{
		SessionID: req.SessionID,
		Cols:      req.Cols,
		Rows:      req.Rows,
		CWD:       req.CWD,
		Env:       req.Env,
		Command:   req.Command,
	}, client)
	if err != nil {
		r.replyTerminalError("terminalCreateResult", req.SessionID, err.Error())
		return
	}
	if !result.IsNew && result.Snapshot != nil {
		client.pushSnapshot(req.SessionID, result.Snapshot)
	}
	r.replyTerminal("terminalCreateResult", map[string]interface{}{
		"terminal": map[string]interface{}{
			"handle":    result.SessionID,
			"sessionId": result.SessionID,
			"pid":       result.PID,
			"title":     "shell",
			"isNew":     result.IsNew,
		},
		"error": nil,
	})
}

func (r *e2eRouter) handleTerminalAttach(payload []byte) {
	var req struct {
		Handle string `json:"handle"`
		Cols   int    `json:"cols"`
		Rows   int    `json:"rows"`
	}
	if err := json.Unmarshal(payload, &req); err != nil || req.Handle == "" {
		r.replyTerminalError("terminalAttachResult", "", "handle is required")
		return
	}
	client := r.ensureRelayTerminalClient()
	snap, err := r.server.terminalHost().Attach(req.Handle, client)
	if err != nil {
		r.replyTerminalError("terminalAttachResult", req.Handle, err.Error())
		return
	}
	if req.Cols > 0 && req.Rows > 0 {
		_ = r.server.terminalHost().Resize(req.Handle, req.Cols, req.Rows)
	}
	client.pushSnapshot(req.Handle, snap)
	r.replyTerminal("terminalAttachResult", map[string]interface{}{
		"handle":  req.Handle,
		"isNew":   false,
		"snapshot": snap,
		"error":   nil,
	})
}

func (r *e2eRouter) handleTerminalSend(payload []byte) {
	var req struct {
		Handle string `json:"handle"`
		Text   string `json:"text"`
	}
	if err := json.Unmarshal(payload, &req); err != nil || req.Handle == "" {
		r.replyTerminalError("terminalSendResult", "", "handle is required")
		return
	}
	n, err := r.server.terminalHost().Write(req.Handle, []byte(req.Text))
	if err != nil {
		r.replyTerminalError("terminalSendResult", req.Handle, err.Error())
		return
	}
	r.replyTerminal("terminalSendResult", map[string]interface{}{
		"send": map[string]interface{}{
			"handle":       req.Handle,
			"accepted":     true,
			"bytesWritten": n,
		},
		"error": nil,
	})
}

func (r *e2eRouter) handleTerminalResize(payload []byte) {
	var req struct {
		Handle   string `json:"handle"`
		Cols     int    `json:"cols"`
		Rows     int    `json:"rows"`
		ClientID string `json:"clientId"`
		Mode     string `json:"mode"`
	}
	if err := json.Unmarshal(payload, &req); err != nil || req.Handle == "" {
		r.replyTerminalError("terminalResizeResult", "", "handle is required")
		return
	}
	if err := r.server.terminalHost().Resize(req.Handle, req.Cols, req.Rows); err != nil {
		r.replyTerminalError("terminalResizeResult", req.Handle, err.Error())
		return
	}
	r.replyTerminal("terminalResizeResult", map[string]interface{}{
		"handle": req.Handle,
		"cols":   req.Cols,
		"rows":   req.Rows,
		"error":  nil,
	})
}

func (r *e2eRouter) handleTerminalClose(payload []byte) {
	var req struct {
		Handle string `json:"handle"`
	}
	if err := json.Unmarshal(payload, &req); err != nil || req.Handle == "" {
		r.replyTerminalError("terminalCloseResult", "", "handle is required")
		return
	}
	err := r.server.terminalHost().Kill(req.Handle)
	errStr := ""
	if err != nil {
		errStr = err.Error()
	}
	r.replyTerminal("terminalCloseResult", map[string]interface{}{
		"handle": req.Handle,
		"error":  nilIfEmpty(errStr),
	})
}

func (r *e2eRouter) handleTerminalList(_ []byte) {
	sessions := r.server.terminalHost().List()
	r.replyTerminal("terminalListResult", map[string]interface{}{
		"sessions": sessions,
		"error":    nil,
	})
}

func (r *e2eRouter) handleTerminalSubscribe(payload []byte) {
	var req struct {
		Handle string `json:"handle"`
		Client struct {
			ID   string `json:"id"`
			Type string `json:"type"`
		} `json:"client"`
	}
	if err := json.Unmarshal(payload, &req); err != nil || req.Handle == "" {
		r.replyTerminalError("terminalSubscribeResult", "", "handle is required")
		return
	}
	client := r.ensureRelayTerminalClient()
	snap, err := r.server.terminalHost().Attach(req.Handle, client)
	if err != nil {
		r.replyTerminalError("terminalSubscribeResult", req.Handle, err.Error())
		return
	}
	client.pushSnapshot(req.Handle, snap)
	r.replyTerminal("terminalSubscribeResult", map[string]interface{}{
		"handle":   req.Handle,
		"streamId": client.streamID,
		"error":    nil,
	})
}

func (r *e2eRouter) ensureRelayTerminalClient() *relayTerminalClient {
	r.termClientMu.Lock()
	defer r.termClientMu.Unlock()
	if r.termClient == nil {
		r.termClient = &relayTerminalClient{router: r, streamID: 1}
	}
	return r.termClient
}

func (r *e2eRouter) replyTerminal(msgType string, payload map[string]interface{}) {
	msg := map[string]interface{}{"type": msgType, "payload": payload}
	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("e2e: marshal %s failed: %v", msgType, err)
		return
	}
	if err := r.client.sendMessage(msgType, data); err != nil {
		log.Printf("e2e: send %s failed: %v", msgType, err)
	}
}

func (r *e2eRouter) replyTerminalError(msgType, handle, errMsg string) {
	r.replyTerminal(msgType, map[string]interface{}{
		"handle": handle,
		"error":  errMsg,
	})
}

func nilIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
