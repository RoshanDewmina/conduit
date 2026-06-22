package main

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
)

// helloParams is the payload of the control channel's first "hello" RPC.
type helloParams struct {
	ProtocolVersion int    `json:"protocolVersion"`
	Token           string `json:"token"`
}

type helloResult struct {
	ProtocolVersion int    `json:"protocolVersion"`
	ServiceVersion  string `json:"serviceVersion"`
}

// isHelloControl reports whether a framed first message is a JSON-RPC "hello"
// request — the control channel's handshake, distinct from the legacy attach
// handshake (isAttachHello) which uses an unversioned {"op":"attach"} shape.
func isHelloControl(data []byte) bool {
	var msg rpcMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return false
	}
	return msg.Method == "hello"
}

// serveControl handles a versioned, token-authenticated control connection.
// Unlike serveAttach (single exclusive client), multiple control connections
// may be active concurrently — each gets its own goroutine and its own
// serialized response writer, so no shared attach lock is taken here.
func (r *resident) serveControl(conn net.Conn, first []byte) {
	defer conn.Close()

	var hello rpcMessage
	if err := json.Unmarshal(first, &hello); err != nil {
		return
	}

	var params helloParams
	_ = json.Unmarshal(hello.Params, &params)

	token, err := readIPCToken()
	if err != nil {
		writeFrame(conn, mustMarshalRPCError(hello.ID, -32001, "unauthorized"))
		return
	}
	if subtle.ConstantTimeCompare([]byte(params.Token), []byte(token)) != 1 {
		writeFrame(conn, mustMarshalRPCError(hello.ID, -32001, "unauthorized"))
		return
	}
	if params.ProtocolVersion != IPCProtocolVersion {
		writeFrame(conn, mustMarshalRPCError(hello.ID, -32002, "protocol version mismatch"))
		return
	}

	result := helloResult{
		ProtocolVersion: IPCProtocolVersion,
		ServiceVersion:  version,
	}
	resp, _ := json.Marshal(rpcMessage{JSONRPC: "2.0", ID: hello.ID, Result: result})
	if err := writeFrame(conn, resp); err != nil {
		return
	}

	// From here on, dispatch through the same handleMessage path serveAttach
	// uses, writing framed responses back on this connection. Each control
	// connection gets its own writer (no shared writeMu with attach/other
	// control clients) since responses are only ever written by this goroutine.
	for {
		frame, err := readFrame(conn)
		if err != nil {
			if err != io.EOF {
				fmt.Fprintf(os.Stderr, "lancerd daemon: control read: %v\n", err)
			}
			return
		}
		var msg rpcMessage
		if err := json.Unmarshal(frame, &msg); err != nil {
			continue
		}
		r.handleControlMessage(conn, &msg)
	}
}

// handleControlMessage dispatches one control-channel RPC request through the
// server's normal handleMessage path, but redirects the response to this
// connection instead of the server's shared emit writer (which targets the
// attach client / stdout). It temporarily swaps the emitter for the duration
// of the call — safe because handleMessage for any single request writes
// exactly one response synchronously before returning.
func (r *resident) handleControlMessage(conn net.Conn, msg *rpcMessage) {
	if msg.Method == "agent.approval.response" {
		var decision ApprovalDecision
		if err := json.Unmarshal(msg.Params, &decision); err == nil {
			_ = r.queue.remove(decision.ApprovalID)
			_ = r.queue.syncFromStore(r.core.approvals)
		}
	}

	var writeErr error
	r.core.emitMu.Lock()
	prevEmit := r.core.emit
	r.core.emit = func(data []byte) error {
		err := writeFrame(conn, data)
		if err != nil {
			writeErr = err
		}
		return err
	}
	r.core.emitMu.Unlock()

	r.core.handleMessage(msg)

	r.core.emitMu.Lock()
	r.core.emit = prevEmit
	r.core.emitMu.Unlock()

	if writeErr != nil {
		fmt.Fprintf(os.Stderr, "lancerd daemon: control write: %v\n", writeErr)
	}
}

func mustMarshalRPCError(id interface{}, code int, message string) []byte {
	data, _ := json.Marshal(rpcMessage{JSONRPC: "2.0", ID: id, Error: &rpcError{Code: code, Message: message}})
	return data
}
