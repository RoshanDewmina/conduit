package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/net/websocket"
)

// loopbackRelay is a faithful, in-process re-implementation of the blind
// push-backend relay (daemon/push-backend/websocket_relay.go) used to prove the
// FULL pairing handshake end-to-end inside the conduitd package: a real
// e2eRelayClient (daemon role) pairs with a simulated phone through it, derives a
// shared key, and exchanges an AEAD-sealed approval round-trip.
//
// Crucially it records every "message" payload it forwards so the test can assert
// the relay is BLIND — it only ever sees opaque ciphertext, never the plaintext
// approval marker. This is the scripted-loopback proof for task 4(b).
type loopbackRelay struct {
	mu          sync.Mutex
	daemonConn  *websocket.Conn
	phoneConn   *websocket.Conn
	daemonKey   string
	phoneKey    string
	seenPayloads []string // every forwarded ciphertext payload, in order
}

func (lr *loopbackRelay) recordPayload(p string) {
	lr.mu.Lock()
	lr.seenPayloads = append(lr.seenPayloads, p)
	lr.mu.Unlock()
}

func (lr *loopbackRelay) handler(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	role := r.URL.Query().Get("role")
	publicKey := r.URL.Query().Get("publicKey")
	if code == "" || role == "" || publicKey == "" {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	websocket.Handler(func(conn *websocket.Conn) {
		defer conn.Close()
		conn.PayloadType = websocket.TextFrame

		lr.mu.Lock()
		if role == "daemon" {
			lr.daemonConn = conn
			lr.daemonKey = publicKey
		} else {
			lr.phoneConn = conn
			lr.phoneKey = publicKey
		}
		// Once both peers are present, announce peer_joined to each with the
		// peer's public key — exactly the push-backend contract.
		bothPresent := lr.daemonConn != nil && lr.phoneConn != nil
		dConn, pConn := lr.daemonConn, lr.phoneConn
		dKey, pKey := lr.daemonKey, lr.phoneKey
		lr.mu.Unlock()

		if role == "daemon" {
			_ = sendJSON(conn, map[string]any{"type": "paired", "role": "daemon"})
		}
		if bothPresent {
			_ = sendJSON(dConn, map[string]any{"type": "peer_joined", "role": "phone", "peerPublicKey": pKey})
			_ = sendJSON(pConn, map[string]any{"type": "peer_joined", "role": "daemon", "peerPublicKey": dKey})
		}

		for {
			var data []byte
			if err := websocket.Message.Receive(conn, &data); err != nil {
				return
			}
			var msg relayInMessage
			if err := json.Unmarshal(data, &msg); err != nil {
				continue
			}
			switch msg.Type {
			case "ping":
				_ = sendJSON(conn, map[string]any{"type": "pong"})
			case "message":
				// The relay sees only the opaque payload — record it for the
				// blindness assertion, then forward verbatim.
				lr.recordPayload(msg.Payload)
				lr.mu.Lock()
				var target *websocket.Conn
				if msg.Target == "phone" {
					target = lr.phoneConn
				} else {
					target = lr.daemonConn
				}
				lr.mu.Unlock()
				if target != nil {
					_ = sendJSON(target, map[string]any{"type": "message", "from": role, "payload": msg.Payload})
				}
			}
		}
	}).ServeHTTP(w, r)
}

type relayInMessage struct {
	Type    string `json:"type"`
	Target  string `json:"target,omitempty"`
	Payload string `json:"payload,omitempty"`
}

// TestE2ELoopbackThroughBlindRelay drives the real e2eRelayClient (daemon side)
// against a locally-run blind relay and a simulated phone built from the same
// e2e_crypto.go primitives the iOS client must match. It proves:
//   - pairing: both peers learn the other's public key over the relay,
//   - key agreement: daemon and phone independently derive the SAME session key,
//   - transport: an approval sealed by the daemon opens on the phone, and an
//     approvalResponse sealed by the phone routes back into applyDecision,
//   - blindness: the relay only ever observed ciphertext, never the plaintext.
func TestE2ELoopbackThroughBlindRelay(t *testing.T) {
	lr := &loopbackRelay{}
	srv := httptest.NewServer(http.HandlerFunc(lr.handler))
	defer srv.Close()
	relayURL := "ws" + strings.TrimPrefix(srv.URL, "http")

	const code = "424242"
	const plaintextMarker = "rm -rf /tmp/agent-scratch"

	// Register a real pending approval so the router's applyDecision call
	// resolves it; we observe the decision on the store's decision channel
	// (no production hook needed).
	// Use a self-managed temp dir (best-effort cleanup) rather than t.TempDir():
	// applyDecision writes an audit entry under home/.conduit, and that write can
	// race t.TempDir()'s strict "must be empty" RemoveAll on teardown.
	home, err0 := os.MkdirTemp("", "conduit-loopback-*")
	if err0 != nil {
		t.Fatalf("mkdtemp: %v", err0)
	}
	defer os.RemoveAll(home)
	srvObj := newServer(home)
	decisionCh := srvObj.approvals.add(ApprovalEvent{ApprovalID: "appr-1", Command: plaintextMarker})

	// Real daemon-side relay client. Its handler is wired by the router; here we
	// install the router so an inbound approvalResponse reaches applyDecision.
	client := newE2ERelayClient(relayURL, code, nil)
	if client == nil {
		t.Fatal("newE2ERelayClient returned nil")
	}
	_ = newE2ERouter(client, srvObj) // sets client.messageHandler
	client.start()
	defer client.stop()

	// Simulated phone: real keypair + raw relay websocket.
	phonePriv, phonePub, err := generateKeyPair()
	if err != nil {
		t.Fatalf("phone keypair: %v", err)
	}
	phoneURL := relayURL + "/ws/relay?role=phone&code=" + code +
		"&publicKey=" + base64URLEncode(phonePub[:])
	phoneConn, err := websocket.Dial(phoneURL, "", srv.URL)
	if err != nil {
		t.Fatalf("phone dial: %v", err)
	}
	defer phoneConn.Close()

	// Phone awaits peer_joined to learn the daemon's public key.
	var daemonPubB64 string
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		_ = phoneConn.SetReadDeadline(time.Now().Add(2 * time.Second))
		var raw string
		if err := websocket.Message.Receive(phoneConn, &raw); err != nil {
			t.Fatalf("phone receive peer_joined: %v", err)
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(raw), &m); err != nil {
			continue
		}
		if m["type"] == "peer_joined" {
			daemonPubB64, _ = m["peerPublicKey"].(string)
			break
		}
	}
	if daemonPubB64 == "" {
		t.Fatal("phone never learned daemon public key")
	}

	// Phone derives the session key using the SAME HKDF context the daemon uses:
	// helperID="conduit-relay", helperKeyB64=daemon pub, appKeyB64=phone pub.
	phoneKey, err := deriveSessionKey(
		phonePriv,
		daemonPubB64,
		"conduit-relay",
		daemonPubB64,
		base64URLEncode(phonePub[:]),
	)
	if err != nil {
		t.Fatalf("phone deriveSessionKey: %v", err)
	}

	// Wait for the daemon client to report paired (it derived its own key).
	pairedDeadline := time.Now().Add(5 * time.Second)
	for !client.isPaired() {
		if time.Now().After(pairedDeadline) {
			t.Fatal("daemon client never reported paired")
		}
		time.Sleep(20 * time.Millisecond)
	}

	// Daemon → phone: send an approval through the encrypted channel.
	approval := map[string]any{
		"type": "approvalPending",
		"payload": map[string]any{
			"approvalID": "appr-1",
			"command":    plaintextMarker,
		},
	}
	approvalJSON, _ := json.Marshal(approval)
	if err := client.sendMessage("approval", approvalJSON); err != nil {
		t.Fatalf("daemon sendMessage: %v", err)
	}

	// Phone receives, decrypts, and verifies the plaintext.
	_ = phoneConn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var rawMsg string
	if err := websocket.Message.Receive(phoneConn, &rawMsg); err != nil {
		t.Fatalf("phone receive approval: %v", err)
	}
	var env struct {
		Type    string `json:"type"`
		Payload string `json:"payload"`
	}
	if err := json.Unmarshal([]byte(rawMsg), &env); err != nil {
		t.Fatalf("phone unmarshal envelope: %v", err)
	}
	var frame encryptedFrame
	if err := json.Unmarshal([]byte(env.Payload), &frame); err != nil {
		t.Fatalf("phone unmarshal frame: %v", err)
	}
	plain, err := decryptFrame(&frame, phoneKey)
	if err != nil {
		t.Fatalf("phone decryptFrame: %v", err)
	}
	if !strings.Contains(string(plain), plaintextMarker) {
		t.Fatalf("phone decrypted plaintext missing marker: %s", plain)
	}

	// Phone → daemon: seal an approvalResponse and send it back. The phone wraps
	// app messages as {type, payload:{…typed params…}} (matching E2ERelayClient.send),
	// so the typed fields live under "payload", not at the top level.
	resp := map[string]any{
		"type": "approvalResponse",
		"payload": map[string]any{
			"approvalID": "appr-1",
			"decision":   "approve",
		},
	}
	respJSON, _ := json.Marshal(resp)
	respFrame, err := encryptFrame(respJSON, phoneKey)
	if err != nil {
		t.Fatalf("phone encryptFrame: %v", err)
	}
	respFrameJSON, _ := json.Marshal(respFrame)
	phoneOut := map[string]any{"type": "message", "target": "daemon", "payload": string(respFrameJSON)}
	phoneOutJSON, _ := json.Marshal(phoneOut)
	if err := websocket.Message.Send(phoneConn, string(phoneOutJSON)); err != nil {
		t.Fatalf("phone send response: %v", err)
	}

	select {
	case d := <-decisionCh:
		if d.decision != "approve" {
			t.Fatalf("applyDecision got %q, want approve", d.decision)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("daemon never routed the approvalResponse into applyDecision")
	}

	// Blindness: the relay forwarded payloads but none may contain the plaintext.
	lr.mu.Lock()
	payloads := append([]string(nil), lr.seenPayloads...)
	lr.mu.Unlock()
	if len(payloads) < 2 {
		t.Fatalf("relay forwarded %d payloads, expected >=2", len(payloads))
	}
	for i, p := range payloads {
		if strings.Contains(p, plaintextMarker) {
			t.Fatalf("relay payload[%d] leaked plaintext marker: %s", i, p)
		}
		if strings.Contains(p, "approvalResponse") || strings.Contains(p, "approvalPending") {
			t.Fatalf("relay payload[%d] leaked cleartext message type: %s", i, p)
		}
	}
}
