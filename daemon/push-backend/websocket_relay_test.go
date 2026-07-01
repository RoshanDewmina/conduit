package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/net/websocket"
)

// resetHubForTest clears the shared relay hub AND the shared pairing-attempt
// rate limiter between tests. All httptest dials come from 127.0.0.1, so the
// limiter must be reset too or later tests inherit earlier tests' attempt
// counts and intermittently hit the 429 path.
func resetHubForTest() {
	hub.mu.Lock()
	hub.pairs = make(map[string]*relayPair)
	hub.mu.Unlock()

	pairAttemptLimiter.mu.Lock()
	pairAttemptLimiter.attempts = make(map[string][]time.Time)
	pairAttemptLimiter.mu.Unlock()
}

// recvErr reads one frame expecting it to be a {"type":"error",...} message,
// failing the test otherwise.
func recvErr(t *testing.T, conn *websocket.Conn) map[string]interface{} {
	t.Helper()
	got := recvJSON(t, conn)
	if got["type"] != "error" {
		t.Fatalf("got type = %v, want error (full: %+v)", got["type"], got)
	}
	return got
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

// A legitimate peer reconnecting with the SAME key it used before (a daemon
// restart, or the phone re-opening the app) must keep working — this is the
// existing "newest-wins" behavior and key-pinning must not break it.
func TestRelayAllowsReconnectWithSameKey(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "same01"
	daemonKey := "daemon-pub-key"
	phoneKey := "phone-pub-key"

	daemon := dialRelay(t, srv, "daemon", code, daemonKey)
	if got := recvJSON(t, daemon); got["type"] != "waiting" {
		t.Fatalf("daemon first message type = %v, want waiting", got["type"])
	}
	phone := dialRelay(t, srv, "phone", code, phoneKey)
	defer phone.Close()
	_ = recvJSON(t, phone)  // peer_joined
	_ = recvJSON(t, daemon) // peer_joined
	daemon.Close()

	// Daemon reconnects with the SAME key (e.g. process restarted, key
	// reloaded from relay-pairing.json) — must be accepted and re-paired.
	daemon2 := dialRelay(t, srv, "daemon", code, daemonKey)
	defer daemon2.Close()
	rejoined := recvJSON(t, phone)
	if rejoined["type"] != "peer_joined" || rejoined["peerPublicKey"] != daemonKey {
		t.Fatalf("phone peer_joined on reconnect = %+v, want peerPublicKey=%s", rejoined, daemonKey)
	}
}

// Security: once a role's key is pinned (first successful exchange), a LATER
// connection on the same code presenting a DIFFERENT key for that role must
// be rejected, not silently take over the slot. Without this, an attacker
// who later guesses a 6-digit code could present a new key, win the
// "newest connection" race, and the other side would silently derive a
// session key with the attacker (MITM) — exactly the "six digits = permanent
// trust" risk the locked pairing spec prohibits.
func TestRelayRejectsKeyMismatchHijack(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "hijack"
	daemonKey := "real-daemon-key"
	phoneKey := "real-phone-key"

	daemon := dialRelay(t, srv, "daemon", code, daemonKey)
	defer daemon.Close()
	_ = recvJSON(t, daemon) // waiting
	phone := dialRelay(t, srv, "phone", code, phoneKey)
	defer phone.Close()
	_ = recvJSON(t, phone)  // peer_joined
	_ = recvJSON(t, daemon) // peer_joined

	// Attacker guesses the code and tries to take over the daemon slot with
	// a DIFFERENT key, without ever having seen daemonKey.
	attacker := dialRelay(t, srv, "daemon", code, "attacker-key")
	defer attacker.Close()
	errMsg := recvErr(t, attacker)
	if errMsg["message"] == "" {
		t.Fatalf("expected a non-empty rejection message, got %+v", errMsg)
	}

	// The legitimate daemon connection must still be intact — a hijack
	// attempt must not have closed or replaced it. Prove this by sending a
	// message daemon → phone and confirming it still arrives.
	sendRelay(t, daemon, relayMessage{Type: "message", Target: "phone", Payload: "still-alive"})
	fwd := recvJSON(t, phone)
	if fwd["type"] != "message" || fwd["payload"] != "still-alive" {
		t.Fatalf("legit daemon connection appears broken after hijack attempt: %+v", fwd)
	}
}

// Security: a pairing code that nobody ever completed an initial key
// exchange on (only one side, or neither side, ever connected) must stop
// being redeemable after pairConfirmWindow — an abandoned or guessed-but-
// unused code must not stay valid forever.
func TestRelayExpiresUnconfirmedCode(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "stale1"
	daemon := dialRelay(t, srv, "daemon", code, "daemon-key")
	defer daemon.Close()
	if got := recvJSON(t, daemon); got["type"] != "waiting" {
		t.Fatalf("daemon first message type = %v, want waiting", got["type"])
	}

	// Backdate CreatedAt past the confirm window; PairedAt is still zero
	// because the phone never joined.
	hub.mu.Lock()
	pair := hub.pairs[code]
	pair.mu.Lock()
	pair.CreatedAt = time.Now().Add(-pairConfirmWindow - time.Minute)
	pair.mu.Unlock()
	hub.mu.Unlock()

	phone := dialRelay(t, srv, "phone", code, "phone-key")
	defer phone.Close()
	errMsg := recvErr(t, phone)
	if errMsg["message"] == "" {
		t.Fatalf("expected a non-empty expiry message, got %+v", errMsg)
	}

	hub.mu.RLock()
	_, stillExists := hub.pairs[code]
	hub.mu.RUnlock()
	if stillExists {
		t.Fatal("expired code should have been deleted from the hub")
	}
}

// Security: an already-PAIRED code (both keys exchanged at least once) must
// keep working past pairConfirmWindow — expiry only applies to codes that
// never completed their first exchange. This is the ongoing-relay-channel
// behavior the live product depends on; it must not regress.
func TestRelayPairedCodeNeverExpires(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "stable"
	daemonKey := "daemon-key"
	phoneKey := "phone-key"

	daemon := dialRelay(t, srv, "daemon", code, daemonKey)
	_ = recvJSON(t, daemon) // waiting
	phone := dialRelay(t, srv, "phone", code, phoneKey)
	defer phone.Close()
	_ = recvJSON(t, phone)  // peer_joined
	_ = recvJSON(t, daemon) // peer_joined
	daemon.Close()

	// Backdate CreatedAt to look very old — PairedAt is non-zero now, so
	// this must NOT trigger the expiry path.
	hub.mu.Lock()
	pair := hub.pairs[code]
	pair.mu.Lock()
	pair.CreatedAt = time.Now().Add(-24 * time.Hour)
	pair.mu.Unlock()
	hub.mu.Unlock()

	daemon2 := dialRelay(t, srv, "daemon", code, daemonKey)
	defer daemon2.Close()
	rejoined := recvJSON(t, phone)
	if rejoined["type"] != "peer_joined" {
		t.Fatalf("expected reconnect to succeed for a paired code regardless of age, got %+v", rejoined)
	}
}

// Security: the pairing code space is only 1e6 combinations and must be
// rate-limited per source IP to block brute-force guessing within
// pairConfirmWindow ("aggressive rate limiting" per the locked spec).
func TestRelayRateLimitsPairingAttempts(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	var lastStatus int
	for i := 0; i < pairAttemptMax+5; i++ {
		code := fmt.Sprintf("%06d", i)
		wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") +
			"/ws/relay?role=phone&code=" + code + "&publicKey=guess-key"
		_, err := websocket.Dial(wsURL, "", "http://localhost/")
		if err != nil {
			// http.Error before upgrade surfaces as a dial failure; capture
			// whether we've crossed into the rate-limited regime.
			if i >= pairAttemptMax {
				lastStatus = http.StatusTooManyRequests
			}
			continue
		}
	}
	if lastStatus != http.StatusTooManyRequests {
		t.Fatalf("expected attempts beyond pairAttemptMax (%d) to be rate-limited, but dials kept succeeding", pairAttemptMax)
	}
}

// Regression: concurrent reconnects racing concurrent message relay must not
// let two goroutines write to the same *websocket.Conn unsynchronized.
//
// Before the fix, the peer_joined sends (and buffered-message flush) for a
// reconnecting peer ran AFTER pair.mu was unlocked, while the message-relay
// loop's sendJSON call for an in-flight "message" holds pair.mu. Both paths
// can target the same underlying conn (the peer that did NOT just reconnect)
// at the same time, so pair.mu no longer actually serialized writes to it —
// exactly the condition that preceded a live SIGSEGV in the deployed relay
// (goroutine crash inside encoding/json's sync.Pool via sendJSON, both from
// the locked ping/pong path and the then-unlocked peer_joined path). This
// test hammers rapid daemon reconnects against a phone that is concurrently
// relaying "message" traffic, under `go test -race`, so a reintroduced
// unlocked-send window shows up as a detected data race rather than a rare,
// hard-to-reproduce production crash.
func TestRelayConcurrentReconnectAndMessageRelayNoRace(t *testing.T) {
	resetHubForTest()
	srv := httptest.NewServer(http.HandlerFunc(handleWebSocketRelay))
	defer srv.Close()

	code := "race01"
	daemonKey := "daemon-pub-key"
	phoneKey := "phone-pub-key"

	daemon := dialRelay(t, srv, "daemon", code, daemonKey)
	defer daemon.Close()
	if got := recvJSON(t, daemon); got["type"] != "waiting" {
		t.Fatalf("daemon first message type = %v, want waiting", got["type"])
	}
	phone := dialRelay(t, srv, "phone", code, phoneKey)
	defer phone.Close()
	_ = recvJSON(t, phone)  // peer_joined
	_ = recvJSON(t, daemon) // peer_joined

	const rounds = 40
	var wg sync.WaitGroup
	wg.Add(2)

	// Goroutine A: the phone keeps sending "message" traffic to the daemon —
	// each send takes the message-loop's pair.mu.Lock() path.
	go func() {
		defer wg.Done()
		for i := 0; i < rounds; i++ {
			_ = websocket.Message.Send(phone, mustJSON(relayMessage{
				Type: "message", Target: "daemon", Payload: fmt.Sprintf("payload-%d", i),
			}))
			time.Sleep(time.Millisecond)
		}
	}()

	// Goroutine B: the daemon rapidly reconnects with the SAME pinned key —
	// each reconnect exercises the "second-or-later connection" branch that
	// sends peer_joined to both daemonConn and phoneConn.
	go func() {
		defer wg.Done()
		var last *websocket.Conn
		for i := 0; i < rounds; i++ {
			c, err := websocket.Dial(
				"ws"+strings.TrimPrefix(srv.URL, "http")+"/ws/relay?role=daemon&code="+code+"&publicKey="+daemonKey,
				"", "http://localhost/")
			if err != nil {
				continue
			}
			if last != nil {
				_ = last.Close()
			}
			last = c
			time.Sleep(time.Millisecond)
		}
		if last != nil {
			_ = last.Close()
		}
	}()

	wg.Wait()
}

func mustJSON(v interface{}) string {
	data, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return string(data)
}

// Security: sweepStale must bound the rate limiter's memory under an
// attacker rotating source IPs (one attempt per IP, never revisited) — the
// per-key pruning inside allow() never fires again for a key that's only
// ever queried once, so without a periodic sweep the map would grow
// without bound.
func TestRateLimiterSweepStaleBoundsMemory(t *testing.T) {
	rl := &rateLimiter{attempts: make(map[string][]time.Time)}

	// Simulate 500 distinct attacker IPs, each making exactly one attempt
	// well outside the rate-limit window (so every entry is stale).
	stale := time.Now().Add(-2 * pairAttemptWindow)
	for i := 0; i < 500; i++ {
		key := fmt.Sprintf("203.0.113.%d", i)
		rl.attempts[key] = []time.Time{stale}
	}
	// One fresh, in-window entry that must survive the sweep.
	rl.attempts["198.51.100.1"] = []time.Time{time.Now()}

	rl.sweepStale()

	if got := len(rl.attempts); got != 1 {
		t.Fatalf("sweepStale left %d entries, want 1 (only the fresh one)", got)
	}
	if _, ok := rl.attempts["198.51.100.1"]; !ok {
		t.Fatal("sweepStale removed the fresh in-window entry, want it kept")
	}
}
