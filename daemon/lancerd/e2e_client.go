package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"sync"
	"time"

	"golang.org/x/net/websocket"
)

type e2eRelayClient struct {
	mu             sync.Mutex
	relayURL       string
	pairingCode    string
	privateKey     [32]byte
	publicKey      [32]byte
	conn           *websocket.Conn
	sessionKey     []byte
	connected      bool
	paired         bool
	messageHandler func(msgType string, payload []byte)
	stopCh         chan struct{}
	stopOnce       sync.Once
	wg             sync.WaitGroup
	reconnectDelay time.Duration
}

func newE2ERelayClient(relayURL, pairingCode string, handler func(msgType string, payload []byte)) *e2eRelayClient {
	priv, pub, err := generateKeyPair()
	if err != nil {
		log.Printf("e2e: failed to generate keypair: %v", err)
		return nil
	}

	return &e2eRelayClient{
		relayURL:       relayURL,
		pairingCode:    pairingCode,
		privateKey:     priv,
		publicKey:      pub,
		messageHandler: handler,
		stopCh:         make(chan struct{}),
		reconnectDelay: 1 * time.Second,
	}
}

// newE2ERelayClientWithKey creates a client using a specific keypair (from a
// persisted relay pairing) rather than generating a fresh one.
func newE2ERelayClientWithKey(relayURL, pairingCode string, handler func(msgType string, payload []byte), privKey, pubKey [32]byte) *e2eRelayClient {
	return &e2eRelayClient{
		relayURL:       relayURL,
		pairingCode:    pairingCode,
		privateKey:     privKey,
		publicKey:      pubKey,
		messageHandler: handler,
		stopCh:         make(chan struct{}),
		reconnectDelay: 1 * time.Second,
	}
}

func (c *e2eRelayClient) start() {
	c.wg.Add(2)
	go func() {
		defer c.wg.Done()
		c.connectLoop()
	}()
	go func() {
		defer c.wg.Done()
		c.keepaliveLoop()
	}()
}

// stop tears down the client and blocks until connectLoop and keepaliveLoop
// have both fully exited, so a caller that immediately starts a replacement
// client (e.g. the relay-pairing watcher reconnecting on a config change)
// never races the old client's goroutines for the relay's per-code daemon
// connection slot. Idempotent — safe to call more than once.
func (c *e2eRelayClient) stop() {
	c.stopOnce.Do(func() {
		close(c.stopCh)
		c.mu.Lock()
		if c.conn != nil {
			c.conn.Close()
		}
		c.connected = false
		c.paired = false
		c.mu.Unlock()
	})
	c.wg.Wait()
}

// sleepOrStop waits for d, or returns early (reporting false) if stop() is
// called in the meantime. Used to back off between reconnect attempts without
// delaying shutdown.
func (c *e2eRelayClient) sleepOrStop(d time.Duration) bool {
	select {
	case <-c.stopCh:
		return false
	case <-time.After(d):
		return true
	}
}

func (c *e2eRelayClient) connectLoop() {
	for {
		select {
		case <-c.stopCh:
			return
		default:
		}

		err := c.connect()
		if err != nil {
			log.Printf("e2e: connect failed: %v (retry in %v)", err, c.reconnectDelay)
			if !c.sleepOrStop(c.reconnectDelay) {
				return
			}
			if c.reconnectDelay < 30*time.Second {
				c.reconnectDelay *= 2
			}
			continue
		}
		c.reconnectDelay = 1 * time.Second
		c.messageLoop()

		// messageLoop returns either because stop() closed stopCh (in which
		// case exit immediately) or because the connection dropped on its own
		// (network blip, relay-side hiccup). For the latter, back off briefly
		// before redialing instead of hammering the relay with an instant
		// reconnect — without this, a single dropped connection can produce
		// several rapid daemon-role connects for the same pairing code within
		// a couple of seconds.
		select {
		case <-c.stopCh:
			return
		default:
		}
		if !c.sleepOrStop(1 * time.Second) {
			return
		}
	}
}

func (c *e2eRelayClient) connect() error {
	pubKeyB64 := base64URLEncode(c.publicKey[:])

	u := fmt.Sprintf("%s/ws/relay?role=daemon&code=%s&publicKey=%s",
		c.relayURL, c.pairingCode, url.QueryEscape(pubKeyB64))

	conn, err := websocket.Dial(u, "ws", "http://localhost/")
	if err != nil {
		return fmt.Errorf("websocket dial: %w", err)
	}

	c.mu.Lock()
	c.conn = conn
	c.connected = true
	c.mu.Unlock()

	log.Printf("e2e: connected to relay as daemon (code: %s)", c.pairingCode)
	return nil
}

func (c *e2eRelayClient) messageLoop() {
	for {
		select {
		case <-c.stopCh:
			return
		default:
		}

		var data []byte
		if err := websocket.Message.Receive(c.conn, &data); err != nil {
			log.Printf("e2e: receive error: %v", err)
			c.mu.Lock()
			c.connected = false
			c.paired = false
			c.conn = nil
			c.mu.Unlock()
			return
		}

		var msg struct {
			Type    string `json:"type"`
			Role    string `json:"role,omitempty"`
			From    string `json:"from,omitempty"`
			Payload string `json:"payload,omitempty"`
			PeerKey string `json:"peerPublicKey,omitempty"`
			Message string `json:"message,omitempty"`
		}

		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}

		switch msg.Type {
		case "pong":

		case "error":
			// The relay rejects a pairing connection (key mismatch, expired
			// unconfirmed code, or rate limited) by sending this frame, then
			// closing the connection — see daemon/push-backend/websocket_relay.go.
			// Log the reason before the next Receive hits the closed connection
			// and falls into the existing connectLoop backoff/retry, otherwise
			// a rejected pairing is silently indistinguishable from a network drop.
			log.Printf("e2e: relay rejected: %s", msg.Message)

		case "peer_joined":
			c.mu.Lock()
			key, err := deriveSessionKey(
				c.privateKey,
				msg.PeerKey,
				"lancer-relay",
				base64URLEncode(c.publicKey[:]),
				msg.PeerKey,
			)
			if err != nil {
				c.mu.Unlock()
				log.Printf("e2e: key derivation failed: %v", err)
				continue
			}
			c.sessionKey = key
			c.paired = true
			c.mu.Unlock()

			log.Printf("e2e: paired with phone (code: %s)", c.pairingCode)

		case "message":
			c.mu.Lock()
			key := c.sessionKey
			c.mu.Unlock()

			if key == nil || msg.Payload == "" {
				continue
			}

			var frame encryptedFrame
			if err := json.Unmarshal([]byte(msg.Payload), &frame); err != nil {
				log.Printf("e2e: frame unmarshal failed: %v", err)
				continue
			}

			plaintext, err := decryptFrame(&frame, key)
			if err != nil {
				log.Printf("e2e: decrypt failed: %v", err)
				continue
			}

			var inner struct {
				Type    string          `json:"type"`
				Payload json.RawMessage `json:"payload"`
			}
			if err := json.Unmarshal(plaintext, &inner); err != nil {
				log.Printf("e2e: inner unmarshal failed: %v", err)
				continue
			}

			if c.messageHandler != nil {
				// Hand the handler the UNWRAPPED inner payload. The phone wraps app
				// messages as {type, payload:{…typed params…}}; handlers unmarshal
				// those params directly, so passing the whole plaintext left every
				// field empty (silent no-op dispatch/approval over the relay).
				c.messageHandler(inner.Type, inner.Payload)
			}
		}
	}
}

func (c *e2eRelayClient) isPaired() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.paired && c.connected
}

func (c *e2eRelayClient) keepaliveLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-c.stopCh:
			return
		case <-ticker.C:
			c.mu.Lock()
			conn := c.conn
			c.mu.Unlock()

			if conn != nil {
				sendJSON(conn, map[string]interface{}{"type": "ping"})
			}
		}
	}
}

func (c *e2eRelayClient) sendMessage(msgType string, payload []byte) error {
	c.mu.Lock()
	conn := c.conn
	key := c.sessionKey
	paired := c.paired
	c.mu.Unlock()

	if conn == nil || !paired || key == nil {
		return fmt.Errorf("e2e: not connected or paired")
	}

	frame, err := encryptFrame(payload, key)
	if err != nil {
		return fmt.Errorf("e2e: encrypt failed: %w", err)
	}

	frameJSON, err := json.Marshal(frame)
	if err != nil {
		return err
	}

	msg := map[string]interface{}{
		"type":    "message",
		"target":  "phone",
		"payload": string(frameJSON),
	}

	msgData, _ := json.Marshal(msg)

	c.mu.Lock()
	err = websocket.Message.Send(c.conn, string(msgData))
	c.mu.Unlock()

	return err
}

func sendJSON(conn *websocket.Conn, v interface{}) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return websocket.Message.Send(conn, string(data))
}
