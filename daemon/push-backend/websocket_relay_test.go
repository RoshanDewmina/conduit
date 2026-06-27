package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"golang.org/x/net/websocket"
)

// resetHubForTest clears the shared relay hub between tests.
func resetHubForTest() {
	hub.mu.Lock()
	hub.pairs = make(map[string]*relayPair)
	hub.mu.Unlock()
}

// dialRelay opens a relay websocket for the given role/code, using the same
// x/net/websocket package the relay server speaks.
func dialRelay(t *testing.T, srv *httptest.Server, role, code, publicKey string) *websocket.Conn {
	t.Helper()
	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") +
		"/ws/relay?role=" + role + "&code=" + code + "&publicKey=" + publicKey
	conn, err := websocket.Dial(wsURL, "", "http://localhost/")
	if err != nil {
		t.Fatalf("dial %s: %v", role, err)
	}
	return conn
}

// recvJSON reads one text frame with a deadline so the test can never hang.
func recvJSON(t *testing.T, conn *websocket.Conn) map[string]interface{} {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	var raw string
	if err := websocket.Message.Receive(conn, &raw); err != nil {
		t.Fatalf("receive: %v", err)
	}
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		t.Fatalf("unmarshal %q: %v", raw, err)
	}
	return m
}

func sendRelay(t *testing.T, conn *websocket.Conn, v interface{}) {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := websocket.Message.Send(conn, string(data)); err != nil {
		t.Fatalf("send: %v", err)
	}
}

// Proves the relay round-trip end-to-end: daemon and phone pair on the same
// code, both learn the peer's public key, and an opaque ciphertext payload sent
// either direction is forwarded VERBATIM. The relay only ever sees the base64
// ciphertext string — it has no key, so the payload is opaque pass-through.
func TestRelayRoundTrip(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "abc123"
	daemonKey := "daemon-pub-key"
	phoneKey := "phone-pub-key"

	// Daemon connects first → gets a "paired" ack.
	daemon := dialRelay(t, srv, "daemon", code, daemonKey)
	defer daemon.Close()
	if got := recvJSON(t, daemon); got["type"] != "waiting" {
		t.Fatalf("daemon first message type = %v, want waiting", got["type"])
	}

	// Phone connects → both sides receive peer_joined with the peer's key.
	phone := dialRelay(t, srv, "phone", code, phoneKey)
	defer phone.Close()

	phoneJoined := recvJSON(t, phone)
	if phoneJoined["type"] != "peer_joined" || phoneJoined["peerPublicKey"] != daemonKey {
		t.Fatalf("phone peer_joined = %+v, want peerPublicKey=%s", phoneJoined, daemonKey)
	}
	daemonJoined := recvJSON(t, daemon)
	if daemonJoined["type"] != "peer_joined" || daemonJoined["peerPublicKey"] != phoneKey {
		t.Fatalf("daemon peer_joined = %+v, want peerPublicKey=%s", daemonJoined, phoneKey)
	}

	// (b) opaque ciphertext daemon → phone is forwarded verbatim.
	cipherToPhone := "AAAAencryptedFrameBytes====opaque"
	sendRelay(t, daemon, relayMessage{Type: "message", Target: "phone", Payload: cipherToPhone})
	fwd := recvJSON(t, phone)
	if fwd["type"] != "message" || fwd["from"] != "daemon" {
		t.Fatalf("forwarded envelope = %+v, want type=message from=daemon", fwd)
	}
	if fwd["payload"] != cipherToPhone {
		t.Fatalf("payload mutated: got %q, want %q", fwd["payload"], cipherToPhone)
	}

	// (b) opaque ciphertext phone → daemon is forwarded verbatim.
	cipherToDaemon := "BBBBdecisionFrame====opaque"
	sendRelay(t, phone, relayMessage{Type: "message", Target: "daemon", Payload: cipherToDaemon})
	fwd2 := recvJSON(t, daemon)
	if fwd2["type"] != "message" || fwd2["from"] != "phone" {
		t.Fatalf("forwarded envelope = %+v, want type=message from=phone", fwd2)
	}
	if fwd2["payload"] != cipherToDaemon {
		t.Fatalf("payload mutated: got %q, want %q", fwd2["payload"], cipherToDaemon)
	}
}

// A message that arrives before the peer connects must be buffered and replayed
// verbatim on join — still opaque pass-through, never inspected.
func TestRelayBuffersUntilPeerJoins(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "buf999"
	daemon := dialRelay(t, srv, "daemon", code, "daemon-key")
	defer daemon.Close()
	if got := recvJSON(t, daemon); got["type"] != "waiting" {
		t.Fatalf("daemon first message type = %v, want waiting", got["type"])
	}

	// Daemon sends before the phone is present → relay buffers it.
	buffered := "CCCCbufferedCiphertext====opaque"
	sendRelay(t, daemon, relayMessage{Type: "message", Target: "phone", Payload: buffered})

	phone := dialRelay(t, srv, "phone", code, "phone-key")
	defer phone.Close()

	// peer_joined first, then the buffered message replayed verbatim.
	if got := recvJSON(t, phone); got["type"] != "peer_joined" {
		t.Fatalf("phone first message type = %v, want peer_joined", got["type"])
	}
	replay := recvJSON(t, phone)
	if replay["type"] != "message" || replay["payload"] != buffered {
		t.Fatalf("replayed buffered message = %+v, want payload=%s", replay, buffered)
	}
}

// Regression: the PHONE may connect BEFORE the daemon (the real-world order —
// the app's pairing screen auto-dials, then the user runs `lancerd pair`).
// The relay must hold the phone open and pair on the daemon's later join,
// rather than dropping the phone with a "waiting"+close. (Pre-fix, phone-first
// was closed immediately and pairing never completed.)
func TestRelayPhoneFirstPairs(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "ph0ne1"
	phoneKey := "phone-pub-key"
	daemonKey := "daemon-pub-key"

	// Phone connects first → held with a "waiting" ack (connection stays open).
	phone := dialRelay(t, srv, "phone", code, phoneKey)
	defer phone.Close()
	if got := recvJSON(t, phone); got["type"] != "waiting" {
		t.Fatalf("phone first message type = %v, want waiting", got["type"])
	}

	// Daemon connects second → both sides receive peer_joined with peer keys.
	daemon := dialRelay(t, srv, "daemon", code, daemonKey)
	defer daemon.Close()

	daemonJoined := recvJSON(t, daemon)
	if daemonJoined["type"] != "peer_joined" || daemonJoined["peerPublicKey"] != phoneKey {
		t.Fatalf("daemon peer_joined = %+v, want peerPublicKey=%s", daemonJoined, phoneKey)
	}
	phoneJoined := recvJSON(t, phone)
	if phoneJoined["type"] != "peer_joined" || phoneJoined["peerPublicKey"] != daemonKey {
		t.Fatalf("phone peer_joined = %+v, want peerPublicKey=%s", phoneJoined, daemonKey)
	}
}

// Security regression (CSWSH): a browser-style Origin header must be rejected.
// Native clients (iOS = no Origin, daemon = http://localhost/) are allowed; a
// cross-site page origin must not be able to open the relay socket.
func TestRelayRejectsBrowserOrigin(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") +
		"/ws/relay?role=phone&code=evil01&publicKey=attacker-key"
	// Origin of a malicious web page.
	_, err := websocket.Dial(wsURL, "", "https://evil.example.com")
	if err == nil {
		t.Fatal("expected dial to be rejected for a browser Origin, but it succeeded")
	}
}
