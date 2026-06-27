package main

import (
	"encoding/json"
	"regexp"
	"testing"
)

var sixDigitCode = regexp.MustCompile(`^\d{6}$`)

// TestAgentPairBeginOverControlSocket drives agent.pair.begin through a real
// control connection (handshake first, same as the app does) and asserts the
// exact result contract Lancer for Mac is built against, plus the side
// effect that matters: the resident's relay-pairing file now exists so the
// relay watcher picks it up and connects.
func TestAgentPairBeginOverControlSocket(t *testing.T) {
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

	req := rpcMessage{JSONRPC: "2.0", ID: float64(2), Method: "agent.pair.begin"}
	data, _ := json.Marshal(req)
	if err := writeFrame(conn, data); err != nil {
		t.Fatalf("write agent.pair.begin: %v", err)
	}
	frame, err := readFrame(conn)
	if err != nil {
		t.Fatalf("read agent.pair.begin reply: %v", err)
	}
	var msg rpcMessage
	if err := json.Unmarshal(frame, &msg); err != nil {
		t.Fatalf("unmarshal reply: %v", err)
	}
	if msg.Error != nil {
		t.Fatalf("agent.pair.begin error: %+v", msg.Error)
	}

	var result pairBeginResult
	raw, _ := json.Marshal(msg.Result)
	if err := json.Unmarshal(raw, &result); err != nil {
		t.Fatalf("decode result: %v", err)
	}

	if !sixDigitCode.MatchString(result.Code) {
		t.Errorf("code = %q, want exactly 6 digits", result.Code)
	}
	if result.PublicKey == "" {
		t.Error("publicKey is empty")
	}
	if _, err := base64URLDecode(result.PublicKey); err != nil {
		t.Errorf("publicKey not valid base64url: %v", err)
	}
	if result.Relay == "" {
		t.Error("relay is empty")
	}

	var qr qrPairingPayload
	if err := json.Unmarshal([]byte(result.QRPayload), &qr); err != nil {
		t.Fatalf("qrPayload did not parse as JSON: %v (raw: %s)", err, result.QRPayload)
	}
	if qr.V != 1 {
		t.Errorf("qrPayload.v = %d, want 1", qr.V)
	}
	if qr.Code != result.Code {
		t.Errorf("qrPayload.code = %q, want %q", qr.Code, result.Code)
	}
	if qr.Relay != result.Relay {
		t.Errorf("qrPayload.relay = %q, want %q", qr.Relay, result.Relay)
	}
	if qr.PK != result.PublicKey {
		t.Errorf("qrPayload.pk = %q, want %q", qr.PK, result.PublicKey)
	}

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("readRelayPairing after agent.pair.begin: %v", err)
	}
	if cfg.Code != result.Code || cfg.RelayURL != result.Relay || cfg.PublicKey != result.PublicKey {
		t.Errorf("persisted relay pairing = %+v, want to match result %+v", cfg, result)
	}
}

// TestAgentPairBeginRespectsRelayURLOverride confirms the optional relayURL
// param is honored end to end (result + persisted file), matching what the
// CLI's env-var override (LANCER_RELAY_URL) does for the default path.
func TestAgentPairBeginRespectsRelayURLOverride(t *testing.T) {
	withStateDir(t)
	token, err := ensureIPCToken()
	if err != nil {
		t.Fatal(err)
	}
	startResident(t)
	conn := dialResident(t)
	defer conn.Close()

	if resp := controlHandshake(t, conn, token, IPCProtocolVersion); resp.Error != nil {
		t.Fatalf("handshake error: %+v", resp.Error)
	}

	const override = "wss://example.test/relay"
	params, _ := json.Marshal(pairBeginParams{RelayURL: override})
	req := rpcMessage{JSONRPC: "2.0", ID: float64(2), Method: "agent.pair.begin", Params: params}
	data, _ := json.Marshal(req)
	if err := writeFrame(conn, data); err != nil {
		t.Fatalf("write agent.pair.begin: %v", err)
	}
	frame, err := readFrame(conn)
	if err != nil {
		t.Fatalf("read agent.pair.begin reply: %v", err)
	}
	var msg rpcMessage
	if err := json.Unmarshal(frame, &msg); err != nil {
		t.Fatalf("unmarshal reply: %v", err)
	}
	if msg.Error != nil {
		t.Fatalf("agent.pair.begin error: %+v", msg.Error)
	}

	var result pairBeginResult
	raw, _ := json.Marshal(msg.Result)
	if err := json.Unmarshal(raw, &result); err != nil {
		t.Fatalf("decode result: %v", err)
	}
	if result.Relay != override {
		t.Errorf("relay = %q, want override %q", result.Relay, override)
	}

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("readRelayPairing: %v", err)
	}
	if cfg.RelayURL != override {
		t.Errorf("persisted relayURL = %q, want %q", cfg.RelayURL, override)
	}
}
