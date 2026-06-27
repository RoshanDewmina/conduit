package main

import (
	"encoding/json"
	"net"
	"os"
	"testing"
)

// controlHandshake dials, sends the framed hello, and returns the daemon's reply.
func controlHandshake(t *testing.T, conn net.Conn, token string, version int) rpcMessage {
	t.Helper()
	params, _ := json.Marshal(helloParams{ProtocolVersion: version, Token: token})
	hello := rpcMessage{JSONRPC: "2.0", ID: float64(1), Method: "hello", Params: params}
	data, _ := json.Marshal(hello)
	if err := writeFrame(conn, data); err != nil {
		t.Fatalf("write hello: %v", err)
	}
	respData, err := readFrame(conn)
	if err != nil {
		t.Fatalf("read hello reply: %v", err)
	}
	var resp rpcMessage
	if err := json.Unmarshal(respData, &resp); err != nil {
		t.Fatalf("unmarshal hello reply: %v", err)
	}
	return resp
}

func TestControlHandshakeSucceedsAndServesRPC(t *testing.T) {
	withStateDir(t)
	token, err := ensureIPCToken()
	if err != nil {
		t.Fatal(err)
	}
	startResident(t)
	conn := dialResident(t)
	defer conn.Close()

	resp := controlHandshake(t, conn, token, IPCProtocolVersion)
	if resp.Error != nil {
		t.Fatalf("handshake error: %+v", resp.Error)
	}
	var hr helloResult
	raw, _ := json.Marshal(resp.Result)
	if err := json.Unmarshal(raw, &hr); err != nil {
		t.Fatalf("decode hello result: %v", err)
	}
	if hr.ProtocolVersion != IPCProtocolVersion {
		t.Errorf("protocolVersion = %d, want %d", hr.ProtocolVersion, IPCProtocolVersion)
	}
	if hr.ServiceVersion == "" {
		t.Error("serviceVersion is empty")
	}

	// The same connection must now serve normal RPC.
	ping := rpcMessage{JSONRPC: "2.0", ID: float64(2), Method: "ping"}
	data, _ := json.Marshal(ping)
	if err := writeFrame(conn, data); err != nil {
		t.Fatal(err)
	}
	respData, err := readFrame(conn)
	if err != nil {
		t.Fatal(err)
	}
	var pong rpcMessage
	_ = json.Unmarshal(respData, &pong)
	if pong.Result != "pong" {
		t.Errorf("ping result = %v, want pong", pong.Result)
	}
}

func TestControlRejectsBadToken(t *testing.T) {
	withStateDir(t)
	if _, err := ensureIPCToken(); err != nil {
		t.Fatal(err)
	}
	startResident(t)
	conn := dialResident(t)
	defer conn.Close()

	resp := controlHandshake(t, conn, "not-the-real-token", IPCProtocolVersion)
	if resp.Error == nil || resp.Error.Code != -32001 {
		t.Fatalf("want -32001 unauthorized, got %+v", resp.Error)
	}
}

func TestControlRejectsBadProtocolVersion(t *testing.T) {
	withStateDir(t)
	token, err := ensureIPCToken()
	if err != nil {
		t.Fatal(err)
	}
	startResident(t)
	conn := dialResident(t)
	defer conn.Close()

	resp := controlHandshake(t, conn, token, IPCProtocolVersion+1)
	if resp.Error == nil || resp.Error.Code != -32002 {
		t.Fatalf("want -32002 version mismatch, got %+v", resp.Error)
	}
}

func TestEnsureIPCTokenIsStableAnd0600(t *testing.T) {
	withStateDir(t)
	t1, err := ensureIPCToken()
	if err != nil {
		t.Fatal(err)
	}
	t2, err := ensureIPCToken()
	if err != nil {
		t.Fatal(err)
	}
	if t1 != t2 || t1 == "" {
		t.Fatalf("token not stable: %q vs %q", t1, t2)
	}
	path, _ := ipcTokenPath()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Errorf("token mode = %o, want 0600", info.Mode().Perm())
	}
}

func TestPeerUIDMatchesCurrentUser(t *testing.T) {
	dir := t.TempDir()
	sock := dir + "/peer.sock"
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	accepted := make(chan net.Conn, 1)
	go func() {
		c, err := ln.Accept()
		if err == nil {
			accepted <- c
		}
	}()

	client, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	srv := <-accepted
	defer srv.Close()

	uid, err := peerUID(srv)
	if err != nil {
		t.Fatalf("peerUID: %v", err)
	}
	if uid != uint32(os.Getuid()) {
		t.Errorf("peerUID = %d, want %d", uid, os.Getuid())
	}
}
