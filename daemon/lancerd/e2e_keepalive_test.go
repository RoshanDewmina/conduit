package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"golang.org/x/net/websocket"
)

// TestE2EClientReconnectsOnSilentlyDroppedConnection is the regression proof
// for the 2026-07-11 bug: the daemon's relay websocket session gets reaped
// server-side (idle-connection drop, or a code that later "expired
// unconfirmed") but the daemon never notices — no read deadline meant
// websocket.Message.Receive blocked forever, so the daemon logged "connected
// to relay as daemon" once and then sat on a dead socket permanently, with
// no reconnect and no re-registration.
//
// This test fakes the drop the way it actually happens in the field: the
// relay-side connection stays open at the TCP level (no FIN/RST — matching a
// NAT/LB idle-connection reap that never notifies either endpoint) but simply
// never sends another byte. Before this fix, messageLoop's Receive call would
// block on that silence forever. With the fix (SetReadDeadline refreshed each
// iteration), the client must notice the silence within its read timeout,
// tear the session down, and redial — proven here by the relay observing a
// SECOND daemon connection for the same pairing code.
func TestE2EClientReconnectsOnSilentlyDroppedConnection(t *testing.T) {
	var daemonConnCount int32
	firstConnDone := make(chan struct{})
	secondConnSeen := make(chan struct{})

	mux := http.NewServeMux()
	mux.HandleFunc("/ws/relay", func(w http.ResponseWriter, r *http.Request) {
		websocket.Handler(func(conn *websocket.Conn) {
			defer conn.Close()
			conn.PayloadType = websocket.TextFrame

			n := atomic.AddInt32(&daemonConnCount, 1)
			if n == 1 {
				close(firstConnDone)
				// Simulate a silently dropped connection: hold the socket
				// open, send/receive nothing, ever. A real daemon-side
				// idle-reap looks exactly like this from the daemon's POV —
				// no close frame, no RST, just silence.
				<-r.Context().Done()
				return
			}
			// Second connection = the client noticed the silence and
			// redialed. Signal success and hold briefly so the client's
			// connect() + messageLoop startup doesn't itself race conn
			// teardown at test end.
			select {
			case <-secondConnSeen:
			default:
				close(secondConnSeen)
			}
			<-r.Context().Done()
		}).ServeHTTP(w, r)
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()
	relayURL := "ws" + strings.TrimPrefix(srv.URL, "http")

	client := newE2ERelayClient(relayURL, "999999", nil)
	if client == nil {
		t.Fatal("newE2ERelayClient returned nil")
	}
	// Shrink the read timeout so the test doesn't wait out the real 90s
	// production value — this is exactly what readTimeout being a
	// per-client field (not a bare constant) is for.
	client.readTimeout = 200 * time.Millisecond
	client.start()
	defer client.stop()

	select {
	case <-firstConnDone:
	case <-time.After(3 * time.Second):
		t.Fatal("relay never saw the first daemon connection")
	}

	select {
	case <-secondConnSeen:
		// Reconnected after the silent drop — the fix works.
	case <-time.After(3 * time.Second):
		t.Fatal("client never reconnected after the connection went silent — " +
			"read deadline / stale-connection detection did not fire")
	}

	if got := atomic.LoadInt32(&daemonConnCount); got < 2 {
		t.Fatalf("relay saw %d daemon connections, want >= 2", got)
	}
}

// TestE2EClientRemintsOnExpiredUnconfirmedCode is the regression proof for
// REL-1 B: a pairing code the relay rejects as "expired unconfirmed" — one
// that never completed its first key exchange — must not be redialed
// forever with no operator-visible signal, AND must not just give up either.
// The client auto-re-mints a fresh code (writing relay-pairing.json) and
// stops itself; the resident's relayPairWatcher is what reconnects on the
// new code (not exercised here — see e2e_router_test.go's watcher tests).
//
// LANCER_STATE_DIR MUST be isolated: remintPairingCode() calls
// writeRelayPairing(), and this repo's daemon/lancerd tests run on a
// developer machine that may have a REAL resident lancerd watching the REAL
// ~/.lancer/relay-pairing.json — writing there would orphan a live paired
// phone.
func TestE2EClientRemintsOnExpiredUnconfirmedCode(t *testing.T) {
	dir := withStateDir(t)
	t.Setenv("LANCER_STATE_DIR", dir)

	var rejectCount int32

	mux := http.NewServeMux()
	mux.HandleFunc("/ws/relay", func(w http.ResponseWriter, r *http.Request) {
		websocket.Handler(func(conn *websocket.Conn) {
			defer conn.Close()
			conn.PayloadType = websocket.TextFrame
			atomic.AddInt32(&rejectCount, 1)
			_ = sendJSON(conn, map[string]any{
				"type":    "error",
				"code":    "code_expired",
				"message": "pairing code expired, generate a new one",
			})
		}).ServeHTTP(w, r)
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()
	relayURL := "ws" + strings.TrimPrefix(srv.URL, "http")

	oldCode := "111111"
	client := newE2ERelayClient(relayURL, oldCode, nil)
	if client == nil {
		t.Fatal("newE2ERelayClient returned nil")
	}
	client.start()
	defer client.stop()

	select {
	case <-client.stopCh:
		// remintPairingCode's giveUp fired — the dead client stopped itself.
	case <-time.After(5 * time.Second):
		t.Fatalf("client never stopped after an expired-unconfirmed rejection (rejections observed: %d)",
			atomic.LoadInt32(&rejectCount))
	}

	// Never confirmed on this code, so it must have re-minted on the FIRST
	// rejection, not retried e2eMaxExpiredCodeRejections times first.
	if got := atomic.LoadInt32(&rejectCount); got != 1 {
		t.Fatalf("relay observed %d rejected connection attempts, want exactly 1 (immediate remint)", got)
	}

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("readRelayPairing after remint: %v", err)
	}
	if cfg.Code == oldCode {
		t.Fatalf("relay-pairing.json still has the dead code %s — remint did not run", oldCode)
	}
}
