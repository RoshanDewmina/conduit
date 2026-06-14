package main

import (
	"encoding/json"
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

	websocket.Handler(func(conn *websocket.Conn) {
		defer conn.Close()
		conn.PayloadType = websocket.TextFrame

		hub.mu.Lock()
		pair, ok := hub.pairs[code]
		if !ok {
			if role == "phone" {
				hub.mu.Unlock()
				sendJSON(conn, map[string]interface{}{"type": "waiting", "message": "waiting for daemon"})
				_ = conn.Close()
				return
			}
			pair = newRelayPair(code, publicKey)
			pair.DaemonConn = conn
			pair.DaemonSeen = time.Now()
			hub.pairs[code] = pair
			hub.mu.Unlock()
			log.Printf("relay: daemon connected with code %s", code)
			sendJSON(conn, map[string]interface{}{"type": "paired", "role": "daemon"})
		} else {
			if role == "daemon" {
				hub.mu.Unlock()
				sendJSON(conn, map[string]interface{}{"type": "error", "message": "daemon already connected"})
				return
			}

			pair.mu.Lock()
			pair.PhoneConn = conn
			pair.PhoneKey = publicKey
			pair.PhoneSeen = time.Now()
			pair.mu.Unlock()
			hub.mu.Unlock()

			log.Printf("relay: phone connected with code %s", code)

			pair.mu.Lock()
			if pair.DaemonConn != nil {
				sendJSON(pair.DaemonConn, map[string]interface{}{
					"type":          "peer_joined",
					"role":          "phone",
					"peerPublicKey": publicKey,
				})
			}
			sendJSON(conn, map[string]interface{}{
				"type":          "peer_joined",
				"role":          "daemon",
				"peerPublicKey": pair.DaemonKey,
			})
			for _, msg := range pair.Buffer {
				sendJSON(conn, msg)
			}
			pair.Buffer = nil
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
	}).ServeHTTP(w, r)
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
