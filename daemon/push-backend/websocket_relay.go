package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	"golang.org/x/net/websocket"
)

// pairConfirmWindow bounds how long a freshly displayed pairing code stays
// redeemable if nobody ever completes the initial key exchange (DaemonKey
// and PhoneKey both set). A short code is a rendezvous identifier, not a
// permanent credential -- an abandoned or guessed-but-unused code must not
// stay valid forever. A code that HAS completed its first exchange
// (PairedAt set) keeps working indefinitely for legitimate reconnects.
const pairConfirmWindow = 10 * time.Minute

const (
	pairAttemptWindow = time.Minute
	pairAttemptMax    = 20
)

type relayPair struct {
	Code       string
	DaemonConn *websocket.Conn
	PhoneConn  *websocket.Conn
	DaemonKey  string
	PhoneKey   string
	CreatedAt  time.Time
	LastUsed   time.Time
	DaemonSeen time.Time
	PhoneSeen  time.Time
	// PairedAt is set once, the first time both DaemonKey and PhoneKey are
	// non-empty. Zero means the code never completed an initial key
	// exchange and is still subject to pairConfirmWindow.
	PairedAt time.Time
	Buffer   []relayMessage
	mu       sync.Mutex
}

// rateLimiter throttles relay connection attempts per source IP. The
// pairing code is a 6-digit space (1e6 combinations); without a limit it
// is brute-forceable in seconds. pairAttemptMax/min per IP is generous for
// a real daemon/phone's own reconnect+ping traffic but bounds an
// attacker's guess rate within pairConfirmWindow.
type rateLimiter struct {
	mu       sync.Mutex
	attempts map[string][]time.Time
}

func (rl *rateLimiter) allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	cutoff := time.Now().Add(-pairAttemptWindow)
	kept := rl.attempts[key][:0]
	for _, t := range rl.attempts[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= pairAttemptMax {
		rl.attempts[key] = kept
		return false
	}
	rl.attempts[key] = append(kept, time.Now())
	return true
}

// sweepStale removes entries with no attempts left inside the current
// window. Per-key pruning in allow() only runs when that same key is
// queried again, so a key visited exactly once (e.g. an attacker rotating
// source IPs, trivial over IPv6) would otherwise sit in this map forever —
// unbounded growth that also weakens the limiter's effect for a
// rotating-IP attacker. Called periodically by startRelayJanitor in main.go.
func (rl *rateLimiter) sweepStale() {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	cutoff := time.Now().Add(-pairAttemptWindow)
	for key, times := range rl.attempts {
		kept := times[:0]
		for _, t := range times {
			if t.After(cutoff) {
				kept = append(kept, t)
			}
		}
		if len(kept) == 0 {
			delete(rl.attempts, key)
		} else {
			rl.attempts[key] = kept
		}
	}
}

var pairAttemptLimiter = &rateLimiter{attempts: make(map[string][]time.Time)}

func clientIP(r *http.Request) string {
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

type relayMessage struct {
	Type    string `json:"type"`
	Target  string `json:"target,omitempty"`
	Payload string `json:"payload,omitempty"`
}

func newRelayPair(code, daemonKey string) *relayPair {
	return &relayPair{
		Code:      code,
		DaemonKey: daemonKey,
		CreatedAt: time.Now(),
		LastUsed:  time.Now(),
	}
}

type relayHub struct {
	mu    sync.RWMutex
	pairs map[string]*relayPair
}

var hub = &relayHub{pairs: make(map[string]*relayPair)}

func handleWebSocketRelay(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	role := r.URL.Query().Get("role")
	publicKey := r.URL.Query().Get("publicKey")

	if code == "" || role == "" || publicKey == "" {
		http.Error(w, "code, role, and publicKey required", http.StatusBadRequest)
		return
	}

	if len(code) != 6 || (role != "daemon" && role != "phone") {
		http.Error(w, "invalid code or role", http.StatusBadRequest)
		return
	}

	if !pairAttemptLimiter.allow(clientIP(r)) {
		http.Error(w, "too many pairing attempts, try again later", http.StatusTooManyRequests)
		return
	}

	websocket.Server{
		Handler: func(conn *websocket.Conn) {
		defer conn.Close()
		conn.PayloadType = websocket.TextFrame

		hub.mu.Lock()
		pair, ok := hub.pairs[code]
		if ok {
			pair.mu.Lock()
			expired := pair.PairedAt.IsZero() && time.Since(pair.CreatedAt) > pairConfirmWindow
			pair.mu.Unlock()
			if expired {
				// Nobody ever completed the initial key exchange on this code
				// within pairConfirmWindow. Reject and free the slot rather than
				// silently recycling it for whoever connects next, which would
				// let a patient guesser claim an abandoned code later.
				delete(hub.pairs, code)
				hub.mu.Unlock()
				log.Printf("relay: closing %s conn for code %s: code expired unconfirmed", role, code)
				sendJSON(conn, map[string]interface{}{"type": "error", "code": "code_expired", "message": "pairing code expired, generate a new one"})
				return
			}
		}
		if !ok {
			// First peer for this code (either role). Create the pair, record
			// this side, and hold the connection open until the peer joins.
			// Order-independent: phone-first and daemon-first both work.
			pair = newRelayPair(code, "")
			if role == "daemon" {
				pair.DaemonConn = conn
				pair.DaemonKey = publicKey
				pair.DaemonSeen = time.Now()
			} else {
				pair.PhoneConn = conn
				pair.PhoneKey = publicKey
				pair.PhoneSeen = time.Now()
			}
			hub.pairs[code] = pair
			hub.mu.Unlock()
			log.Printf("relay: %s connected with code %s (waiting for peer)", role, code)
			sendJSON(conn, map[string]interface{}{
				"type":      "waiting",
				"message":   "waiting for peer",
				"expiresAt": pair.CreatedAt.Add(pairConfirmWindow).UTC().Format(time.RFC3339),
			})
		} else {
			// Second-or-later connection on an already-allocated code. Once a
			// role's key has been recorded, it is PINNED: a reconnect must
			// present that same key (a legitimate daemon/phone reconnecting
			// with its persisted key) or it is rejected. Without this, an
			// attacker who later guesses the code could present a new key,
			// win the "newest connection" slot, and the other side would
			// silently derive a session key with the attacker (MITM).
			pair.mu.Lock()
			if role == "daemon" && pair.DaemonKey != "" && pair.DaemonKey != publicKey {
				pair.mu.Unlock()
				hub.mu.Unlock()
				log.Printf("relay: closing daemon conn for code %s: key mismatch, rejecting hijack attempt", code)
				sendJSON(conn, map[string]interface{}{"type": "error", "code": "key_mismatch", "message": "key mismatch -- pairing already established with a different key"})
				return
			}
			if role == "phone" && pair.PhoneKey != "" && pair.PhoneKey != publicKey {
				pair.mu.Unlock()
				hub.mu.Unlock()
				log.Printf("relay: closing phone conn for code %s: key mismatch, rejecting hijack attempt", code)
				sendJSON(conn, map[string]interface{}{"type": "error", "code": "key_mismatch", "message": "key mismatch -- pairing already established with a different key"})
				return
			}
			// Newest-wins: a peer reconnecting on the same code with the SAME
			// pinned key (a daemon that restarted, or a phone re-opening
			// pairing) reclaims its slot. Close the stale connection so the
			// relay frees the slot instead of rejecting the newcomer —
			// otherwise a restarted daemon is locked out until the dead TCP
			// connection times out (minutes).
			if role == "daemon" && pair.DaemonConn != nil {
				log.Printf("relay: closing daemon conn for code %s: newest-wins reconnect replace", code)
				_ = pair.DaemonConn.Close()
				pair.DaemonConn = nil
			} else if role == "phone" && pair.PhoneConn != nil {
				log.Printf("relay: closing phone conn for code %s: newest-wins reconnect replace", code)
				_ = pair.PhoneConn.Close()
				pair.PhoneConn = nil
			}
			if role == "daemon" {
				pair.DaemonConn = conn
				pair.DaemonKey = publicKey
				pair.DaemonSeen = time.Now()
			} else {
				pair.PhoneConn = conn
				pair.PhoneKey = publicKey
				pair.PhoneSeen = time.Now()
			}
			if pair.PairedAt.IsZero() && pair.DaemonKey != "" && pair.PhoneKey != "" {
				pair.PairedAt = time.Now()
			}
			daemonConn := pair.DaemonConn
			phoneConn := pair.PhoneConn
			daemonKey := pair.DaemonKey
			phoneKey := pair.PhoneKey
			buffered := pair.Buffer
			pair.Buffer = nil
			// hub.mu only guards the hub.pairs map lookup above; it can be
			// released now. pair.mu stays HELD through the sends below: the
			// message-relay loop (the "message" case further down) also locks
			// pair.mu before calling sendJSON on pair.DaemonConn/pair.PhoneConn.
			// If this reconnect's peer_joined sends ran after unlocking (as they
			// used to), a concurrent reconnect on the other role, or an
			// in-flight message forward, could call sendJSON on the SAME
			// *websocket.Conn at the same time this code has a stale local
			// copy of it -- the two sendJSON calls are then not serialized by
			// anything, defeating the point of pair.mu. Holding pair.mu across
			// the sends closes that window; websocket.Message.Send's own
			// per-conn lock (ws.wio) is a different mutex, so this can't
			// deadlock.
			hub.mu.Unlock()

			// A pair entry persists across disconnects (cleanup only fires after
			// 24h of inactivity), so an existing pair does NOT guarantee the other
			// role is actually connected — e.g. the daemon dropped and the phone is
			// reconnecting alone. Sending peer_joined to a nil conn here panicked
			// the handler (crashing this connection, not the process — but the
			// resulting EOF made the client retry instantly with no backoff,
			// looping forever). Only announce pairing once both sides are present;
			// otherwise treat this connection like a fresh "first peer" wait.
			if daemonConn != nil && phoneConn != nil {
				log.Printf("relay: %s connected with code %s (paired)", role, code)
				sendJSON(daemonConn, map[string]interface{}{
					"type":          "peer_joined",
					"role":          "phone",
					"peerPublicKey": phoneKey,
				})
				sendJSON(phoneConn, map[string]interface{}{
					"type":          "peer_joined",
					"role":          "daemon",
					"peerPublicKey": daemonKey,
				})
				// Flush buffered messages now that both sides are present. Each
				// buffered message must go to ITS target (the buffer can hold
				// traffic for either direction), re-wrapped in the same
				// {type, from, payload} shape a live forward uses — flushing the
				// raw client frame (which carries "target", not "from") handed
				// the recipient a differently-shaped frame than every other
				// path.
				for _, msg := range buffered {
					target, from := phoneConn, "daemon"
					if msg.Target == "daemon" {
						target, from = daemonConn, "phone"
					}
					sendJSON(target, map[string]interface{}{
						"type":    "message",
						"from":    from,
						"payload": msg.Payload,
					})
				}
				if len(buffered) > 0 {
					log.Printf("relay: flushed %d buffered message(s) on code %s after %s rejoin", len(buffered), code, role)
				}
			} else {
				log.Printf("relay: %s connected with code %s (waiting for peer)", role, code)
				waitingFrame := map[string]interface{}{"type": "waiting", "message": "waiting for peer"}
				if pair.PairedAt.IsZero() {
					waitingFrame["expiresAt"] = pair.CreatedAt.Add(pairConfirmWindow).UTC().Format(time.RFC3339)
				}
				sendJSON(conn, waitingFrame)
			}
			pair.mu.Unlock()
		}

		for {
			var data []byte
			if err := websocket.Message.Receive(conn, &data); err != nil {
				log.Printf("relay: %s %s disconnected: %v", role, code, err)
				break
			}

			var msg relayMessage
			if err := json.Unmarshal(data, &msg); err != nil {
				continue
			}

			pair.mu.Lock()

			switch msg.Type {
			case "ping":
				sendJSON(conn, map[string]interface{}{"type": "pong"})

			case "message":
				var target *websocket.Conn
				now := time.Now()
				if msg.Target == "phone" {
					target = pair.PhoneConn
					pair.DaemonSeen = now
				} else if msg.Target == "daemon" {
					target = pair.DaemonConn
					pair.PhoneSeen = now
				}

				if target != nil {
					sendJSON(target, map[string]interface{}{
						"type":    "message",
						"from":    role,
						"payload": msg.Payload,
					})
				} else if len(pair.Buffer) < 100 {
					// The target role has no live connection. Buffer for its
					// next rejoin — and say so: a silently absent recipient is
					// how approval escalations vanished without a trace on any
					// side (2026-07-07 investigation).
					pair.Buffer = append(pair.Buffer, msg)
					log.Printf("relay: buffered message from %s on code %s (%s not connected, %d queued)", role, code, msg.Target, len(pair.Buffer))
				} else {
					log.Printf("relay: DROPPED message from %s on code %s (%s not connected, buffer full)", role, code, msg.Target)
				}

			case "close":
				pair.mu.Unlock()
				return
			}

			pair.LastUsed = time.Now()
			pair.mu.Unlock()
		}

		hub.mu.Lock()
		pair.mu.Lock()
		// Only release the slot if it still belongs to THIS connection. When a
		// reconnect replaces us (newest-wins close above), our read loop exits
		// and lands here AFTER the replacement has already registered — an
		// unconditional nil here clobbered the successor's registration, leaving
		// a client that believes it is connected while the relay sees nobody.
		// That was the root cause of silently lost approval escalations
		// (2026-07-07): messages for the orphaned role buffered forever.
		if role == "daemon" && pair.DaemonConn == conn {
			pair.DaemonConn = nil
		} else if role == "phone" && pair.PhoneConn == conn {
			pair.PhoneConn = nil
		}
		if pair.DaemonConn == nil && pair.PhoneConn == nil && time.Since(pair.LastUsed) > 24*time.Hour {
			delete(hub.pairs, code)
		}
		pair.mu.Unlock()
		hub.mu.Unlock()
	},
		Handshake: func(config *websocket.Config, req *http.Request) error {
			// Allow only native clients: iOS URLSession sends no Origin header;
			// the Go daemon (e2e_client) sends "http://localhost/". A browser
			// page sends its own origin — reject it to prevent cross-site
			// WebSocket hijacking (CSWSH). Defense-in-depth: pairing also
			// requires the single-use code + X25519 ECDH, so an unknown origin
			// gains nothing, but we close the vector anyway.
			switch req.Header.Get("Origin") {
			case "", "http://localhost/", "http://localhost":
				return nil
			default:
				return fmt.Errorf("origin not allowed: %s", req.Header.Get("Origin"))
			}
		},
	}.ServeHTTP(w, r)
}

func sendJSON(conn *websocket.Conn, v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	// Callers hold pair.mu (and, on the reconnect path, hub.mu) across this
	// send. Without a deadline, one peer with a jammed TCP connection blocks
	// every forward for its pair — and via hub.mu, every new connection to the
	// relay. Bound the stall; a timed-out peer will be replaced on its next
	// reconnect.
	_ = conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	if err := websocket.Message.Send(conn, string(data)); err != nil {
		log.Printf("relay: send error: %v", err)
	}
}
