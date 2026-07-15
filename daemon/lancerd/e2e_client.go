package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/url"
	"strings"
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
	// pairedHandler fires after every peer_joined (initial pairing AND every
	// re-pair after either side reconnects). The router uses it to re-send
	// still-pending approvals: a phone that reconnected — or a relay that
	// swapped/orphaned a connection — has no other way to learn about an
	// escalation sent while delivery was broken.
	pairedHandler  func()
	stopCh         chan struct{}
	stopOnce       sync.Once
	wg             sync.WaitGroup
	reconnectDelay time.Duration

	// readTimeout is the per-Receive stale-connection deadline (see
	// messageLoop). Defaults to e2eReadTimeout; tests shrink it to run a
	// silent-drop scenario in milliseconds instead of e2eReadTimeout's real
	// 90s.
	readTimeout time.Duration

	// expiredCode tracks consecutive relay rejections of THIS pairing code
	// as "expired unconfirmed" across reconnect attempts. Bounded so a dead
	// code fails closed (giveUp) instead of retrying forever silently.
	expiredCode *expiredCodeTracker

	// everConfirmed is set once, the first time this client observes
	// peer_joined, and never cleared again (unlike paired, which drops on
	// every disconnect). Loaded from relay-pairing.json ConfirmedAt on
	// reconnect so a LaunchAgent/binary restart does not forget that this
	// code already completed an exchange — otherwise REL-1 remint would
	// orphan the phone after a backend cold-start + confirm-window race.
	// Used by decideExpiryAction.
	everConfirmed bool

	// sendSeq/sendGen/recv track the per-direction replay-resistance sequence
	// for the current pairing generation (see seqFrame/replaySequencer in
	// e2e_crypto.go). All reset on every new peer_joined session key:
	// sendSeq back to 0, sendGen to a freshly minted id, recv via reset().
	sendSeq uint64
	sendGen string
	recv    replaySequencer
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
		reconnectDelay: e2eInitialReconnectBackoff,
		readTimeout:    e2eReadTimeout,
		expiredCode:    newExpiredCodeTracker(e2eMaxExpiredCodeRejections),
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
		reconnectDelay: e2eInitialReconnectBackoff,
		readTimeout:    e2eReadTimeout,
		expiredCode:    newExpiredCodeTracker(e2eMaxExpiredCodeRejections),
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
		c.closeAndHalt()
	})
	c.wg.Wait()
}

// giveUp is stop()'s teardown, minus wg.Wait() — safe to call from INSIDE
// connectLoop's own goroutine (e.g. after a bounded number of expired-code
// rejections). Waiting on wg here would deadlock: connectLoop is the very
// goroutine wg.Wait() is waiting on. The external stop() path still works
// afterward — stopOnce makes closeAndHalt idempotent, and wg.Wait() there
// simply returns once both loop goroutines have exited on their own via the
// now-closed stopCh.
func (c *e2eRelayClient) giveUp(reason string) {
	c.stopOnce.Do(func() {
		c.closeAndHalt()
		log.Printf("e2e: giving up on relay pairing — %s", reason)
	})
}

// remintPairingCode generates a fresh pairing code + X25519 keypair exactly
// as `lancerd pair`/beginPairing do, persists it to relay-pairing.json, and
// stops this client. This client's own pairingCode is provably dead (the
// relay just rejected it as expired-unconfirmed) — reconnecting to it would
// only repeat the same rejection forever. The resident's relayPairWatcher
// picks up the file change within 5s and starts a new client on the new
// code; see startRelayWatch in resident.go.
func (c *e2eRelayClient) remintPairingCode() {
	code, err := generatePairingCode()
	if err != nil {
		c.giveUp(fmt.Sprintf("pairing code expired unconfirmed, re-mint failed: %v", err))
		return
	}
	priv, pub, err := generateKeyPair()
	if err != nil {
		c.giveUp(fmt.Sprintf("pairing code expired unconfirmed, re-mint failed: %v", err))
		return
	}
	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:   c.relayURL,
		Code:       code,
		PrivateKey: base64URLEncode(priv[:]),
		PublicKey:  base64URLEncode(pub[:]),
	}); err != nil {
		c.giveUp(fmt.Sprintf("pairing code expired unconfirmed, re-mint failed: %v", err))
		return
	}
	log.Printf("e2e: pairing code expired — re-minted a fresh code")
	c.giveUp("pairing code expired unconfirmed — re-minted a fresh code")
}

func (c *e2eRelayClient) closeAndHalt() {
	close(c.stopCh)
	c.mu.Lock()
	if c.conn != nil {
		c.conn.Close()
	}
	c.connected = false
	c.paired = false
	c.mu.Unlock()
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
			c.reconnectDelay = nextReconnectBackoff(c.reconnectDelay, e2eMaxReconnectBackoff)
			continue
		}
		c.reconnectDelay = e2eInitialReconnectBackoff
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

	log.Printf("e2e: connected to relay as daemon")
	return nil
}

func (c *e2eRelayClient) messageLoop() {
	for {
		select {
		case <-c.stopCh:
			return
		default:
		}

		// A read deadline is the fix for the daemon sitting on a silently
		// dropped connection forever: golang.org/x/net/websocket has no
		// RFC6455 control-frame ping (that's a gorilla/nhooyr-only API), so
		// this library's Receive blocks indefinitely with no way to notice a
		// connection that infra dropped without a FIN/RST (idle-connection
		// reaping, NAT/LB drop). Refreshed every iteration: any inbound frame
		// (including the "pong" the relay sends for our keepaliveLoop ping)
		// pushes the deadline forward, so a live-but-quiet connection never
		// times out — only a truly dead one does.
		if err := c.conn.SetReadDeadline(time.Now().Add(c.readTimeout)); err != nil {
			log.Printf("e2e: set read deadline failed: %v", err)
		}

		var data []byte
		if err := websocket.Message.Receive(c.conn, &data); err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				log.Printf("e2e: connection stale (no data in %v), reconnecting", c.readTimeout)
			} else {
				log.Printf("e2e: receive error: %v", err)
			}
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
			Code    string `json:"code,omitempty"`
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

			// "expired unconfirmed" (see push-backend's pairConfirmWindow) means
			// this code can never succeed again without a fresh pairing — redialing
			// it is a silent infinite loop, not recovery. Prefer the structured
			// "code" field (additive on the backend); fall back to the substring
			// match for an older backend that only sends "message".
			isExpired := msg.Code == "code_expired" ||
				(msg.Code == "" && strings.Contains(strings.ToLower(msg.Message), "expired"))
			if isExpired {
				c.mu.Lock()
				everConfirmed := c.everConfirmed
				c.mu.Unlock()

				switch decideExpiryAction(everConfirmed) {
				case expiryActionRemint:
					c.remintPairingCode()
					return
				case expiryActionReregister:
					// Keep code+keys. Connection close follows; connectLoop
					// redials and the backend allocates a fresh waiting slot.
					log.Printf("e2e: code_expired on confirmed pairing — re-registering same identity (not reminting)")
					c.expiredCode.reset()
				}
			}

		case "peer_joined":
			c.expiredCode.reset()
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
			c.everConfirmed = true
			c.sendSeq = 0
			if gen, genErr := newGeneration(); genErr != nil {
				log.Printf("e2e: failed to mint send generation id: %v", genErr)
				c.sendGen = ""
			} else {
				c.sendGen = gen
			}
			c.mu.Unlock()
			c.recv.reset()

			_, err = markRelayPairingConfirmed(&relayPairConfig{
				RelayURL:   c.relayURL,
				Code:       c.pairingCode,
				PrivateKey: base64URLEncode(c.privateKey[:]),
				PublicKey:  base64URLEncode(c.publicKey[:]),
			})
			if err != nil {
				log.Printf("e2e: failed to persist pairing confirmation: %v", err)
			}

			log.Printf("e2e: paired with phone")

			if c.pairedHandler != nil {
				c.pairedHandler()
			}

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

			seq, gen, body, err := unwrapSeq(plaintext)
			if err != nil {
				log.Printf("e2e: seq envelope unmarshal failed: %v", err)
				continue
			}
			switch c.recv.accept(gen, seq) {
			case replayAccepted:
				// fall through to dispatch below
			case replayRejectedStaleGeneration:
				log.Printf("e2e: rejecting stale-generation frame (gen=%q, seq=%d)", gen, seq)
				continue
			default:
				log.Printf("e2e: rejecting replayed or out-of-order frame (gen=%q, seq=%d)", gen, seq)
				continue
			}

			var inner struct {
				Type    string          `json:"type"`
				Payload json.RawMessage `json:"payload"`
			}
			if err := json.Unmarshal(body, &inner); err != nil {
				log.Printf("e2e: inner unmarshal failed: %v", err)
				continue
			}

			if c.messageHandler != nil {
				// Hand the handler the UNWRAPPED inner payload. The phone wraps app
				// messages as {type, payload:{…typed params…}}; handlers unmarshal
				// those params directly, so passing the whole plaintext left every
				// field empty (silent no-op dispatch/approval over the relay).
				//
				// Run the handler on its own goroutine — NEVER inline. Inline
				// handling serialized every phone RPC behind whatever the
				// previous one was doing; two live incidents (2026-07-11) wedged
				// ALL phone→daemon traffic for minutes: a hung git subprocess in
				// the receipt snapshot, then agent.sessions.list walking a 778MB
				// ~/.codex/sessions tree. Handlers are already concurrency-safe
				// (the SSH path invokes them from per-connection goroutines) and
				// sendMessage serializes the seq→encrypt→send critical section,
				// so replies cannot interleave on the wire. inner.Payload aliases
				// this iteration's receive buffer, which is freshly allocated per
				// Receive — safe to retain across the goroutine boundary.
				go c.messageHandler(inner.Type, inner.Payload)
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
	// The whole seq-assign → wrap → encrypt → send sequence must be one
	// critical section. Splitting it (assign seq under one lock, send under a
	// second one later) let two concurrent sends race: whichever finished
	// encryption first won the wire, regardless of which got the lower
	// sequence number — an out-of-order arrival the phone's replaySequencer
	// then silently rejects (its accept() requires strictly increasing), which
	// is exactly what broke chat/dispatch output streaming (many rapid
	// agentRunOutput sends from concurrent callback contexts) while the
	// single-message approval-decision path never exercised the race.
	c.mu.Lock()
	defer c.mu.Unlock()

	conn := c.conn
	key := c.sessionKey
	paired := c.paired

	if conn == nil || !paired || key == nil {
		return fmt.Errorf("e2e: not connected or paired")
	}

	seq := c.sendSeq
	c.sendSeq++
	gen := c.sendGen

	wrapped, err := wrapSeqGen(seq, gen, payload)
	if err != nil {
		return fmt.Errorf("e2e: seq envelope failed: %w", err)
	}

	frame, err := encryptFrame(wrapped, key)
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

	err = websocket.Message.Send(c.conn, string(msgData))

	return err
}

func sendJSON(conn *websocket.Conn, v interface{}) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return websocket.Message.Send(conn, string(data))
}
