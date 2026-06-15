package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"golang.org/x/net/websocket"
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
	Buffer     []relayMessage
	mu         sync.Mutex
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

	websocket.Server{
		Handler: func(conn *websocket.Conn) {
		defer conn.Close()
		conn.PayloadType = websocket.TextFrame

		hub.mu.Lock()
		pair, ok := hub.pairs[code]
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
			sendJSON(conn, map[string]interface{}{"type": "waiting", "message": "waiting for peer"})
		} else {
			// Second peer — must be the opposite role of whoever is already here.
			pair.mu.Lock()
			dup := (role == "daemon" && pair.DaemonConn != nil) ||
				(role == "phone" && pair.PhoneConn != nil)
			if dup {
				pair.mu.Unlock()
				hub.mu.Unlock()
				sendJSON(conn, map[string]interface{}{"type": "error", "message": role + " already connected"})
				return
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
			daemonConn := pair.DaemonConn
			phoneConn := pair.PhoneConn
			daemonKey := pair.DaemonKey
			phoneKey := pair.PhoneKey
			buffered := pair.Buffer
			pair.Buffer = nil
			pair.mu.Unlock()
			hub.mu.Unlock()

			log.Printf("relay: %s connected with code %s (paired)", role, code)

			// Notify each peer of the other's public key (order-independent).
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
			// Flush any buffered messages to the peer that just joined.
			for _, msg := range buffered {
				sendJSON(conn, msg)
			}
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
				} else {
					if len(pair.Buffer) < 100 {
						pair.Buffer = append(pair.Buffer, msg)
					}
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
		if role == "daemon" {
			pair.DaemonConn = nil
		} else {
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
	if err := websocket.Message.Send(conn, string(data)); err != nil {
		log.Printf("relay: send error: %v", err)
	}
}
