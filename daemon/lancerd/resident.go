package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

// resident owns the Unix socket, policy-aware approval state, persistent queue, and optional attach client.
type resident struct {
	core  *server
	queue *diskQueue

	attachMu sync.Mutex
	attach   io.ReadWriteCloser
	writeMu  sync.Mutex

	// relayMu guards relayCode, the pairing code of the currently connected
	// relay client — connectRelay runs both from startup (main goroutine) and
	// from the pairing-file watcher goroutine.
	relayMu   sync.Mutex
	relayCode string
}

func runDaemon() error {
	r, err := newResident()
	if err != nil {
		return err
	}
	if _, err := ensureIPCToken(); err != nil {
		return fmt.Errorf("ensure ipc token: %w", err)
	}
	ensureClaudeHookWiredOnBoot()              // so plain dispatches launch immediately (hook still gates tools)
	r.core.startScheduler(make(chan struct{})) // fires due schedules for the process lifetime

	// Wire E2E relay if a pairing config exists.
	r.wireRelayFromPairing()

	// Watch for relay-pairing.json changes (pair command or relay-attach).
	r.startRelayWatch()

	return r.listen()
}

func newResident() (*resident, error) {
	qPath, err := queuePath()
	if err != nil {
		return nil, err
	}
	// newServer opens the conversation store (and failOrphanedRunningTurns) before
	// restoreQueue runs — load-bearing so dead-run approvals can be pruned.
	core := newServer(serverHome())
	r := &resident{
		core:  core,
		queue: newDiskQueue(qPath),
	}
	core.approvalRetired = func(id string) error {
		return r.queue.remove(id)
	}
	core.setEmitter(r.writeToAttach)
	if err := r.restoreQueue(); err != nil {
		return nil, fmt.Errorf("restore queue: %w", err)
	}
	return r, nil
}

func (r *resident) listen() error {
	sockPath, err := socketPath()
	if err != nil {
		return err
	}
	_ = os.Remove(sockPath)

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return fmt.Errorf("listen unix %s: %w", sockPath, err)
	}
	defer func() { ln.Close(); os.Remove(sockPath) }()

	fmt.Fprintf(os.Stderr, "lancerd daemon listening on %s\n", sockPath)
	for {
		conn, err := ln.Accept()
		if err != nil {
			return err
		}
		go r.handleConnection(conn)
	}
}

func (r *resident) restoreQueue() error {
	events, err := r.queue.readAll()
	if err != nil {
		return err
	}
	var survivors, pruned []ApprovalEvent
	for _, event := range events {
		if approvalRunIsDead(r.core.conversations, event.RunID) {
			pruned = append(pruned, event)
			continue
		}
		survivors = append(survivors, event)
		r.core.approvals.add(event)
	}
	if len(pruned) == 0 {
		return nil
	}
	if err := r.queue.replace(survivors); err != nil {
		return err
	}
	parts := make([]string, len(pruned))
	for i, e := range pruned {
		parts[i] = e.ApprovalID + "/" + e.RunID
	}
	log.Printf("restoreQueue: pruned %d stale approval(s): %s", len(pruned), strings.Join(parts, ", "))
	return nil
}

// approvalRunIsDead reports whether a queued approval's run is known-dead and
// must be dropped on startup. Fail-closed toward keeping the human in the loop:
// empty RunID, missing store, non-terminal status, or unknown lookup errors → keep.
// Terminal status or absent turn → drop (never auto-approve).
func approvalRunIsDead(store *conversationStore, runID string) bool {
	if runID == "" || store == nil {
		return false
	}
	status, err := store.runStatus(runID)
	if err != nil {
		// runStatus maps sql.ErrNoRows to a plain fmt.Errorf (no %w today);
		// also accept errors.Is in case a later change wraps errNoLedgerTurn.
		if errors.Is(err, errNoLedgerTurn) || strings.Contains(err.Error(), errNoLedgerTurn.Error()) {
			return true
		}
		return false
	}
	return isTerminalRunStatus(status)
}

func (r *resident) handleConnection(conn net.Conn) {
	// Defense-in-depth on top of the 0700 state dir: reject any peer whose UID
	// is not the daemon owner's. Same-user hook/attach/shim/control clients pass.
	if uid, err := peerUID(conn); err != nil || uid != uint32(os.Getuid()) {
		conn.Close()
		return
	}

	_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	first, framed, err := readFirstMessage(conn)
	if err != nil {
		conn.Close()
		return
	}
	_ = conn.SetReadDeadline(time.Time{})

	if framed && isAttachHello(first) {
		r.serveAttach(conn, first)
		return
	}
	if framed && isHelloControl(first) {
		r.serveControl(conn, first)
		return
	}
	if !framed {
		if isShimSpawn(first) {
			r.core.handleShimSpawnConn(conn, first)
			return
		}
		r.core.handleHookWithNotify(conn, first, r.notifyAttachOrQueue, r.clientReachable)
		return
	}
	conn.Close()
}

// clientReachable reports whether an escalated approval can plausibly reach a
// human: a live attach client, a paired E2E relay phone, or a registered push
// device. When none holds, handleHookWithNotify fast-auto-approves after a short
// grace instead of blocking 120s (Finding #10).
func (r *resident) clientReachable() bool {
	r.attachMu.Lock()
	attached := r.attach != nil
	r.attachMu.Unlock()
	if attached {
		return true
	}
	if r.core.relayPaired() {
		return true
	}
	return r.core.deviceRegistered()
}

func (r *resident) serveAttach(conn net.Conn, _ []byte) {
	r.attachMu.Lock()
	if r.attach != nil {
		r.attachMu.Unlock()
		conn.Close()
		fmt.Fprintln(os.Stderr, "lancerd daemon: attach rejected (another client connected)")
		return
	}
	r.attach = conn
	r.attachMu.Unlock()

	defer func() {
		r.attachMu.Lock()
		if r.attach == conn {
			r.attach = nil
		}
		r.attachMu.Unlock()
		conn.Close()
	}()

	if err := r.drainToAttach(); err != nil {
		fmt.Fprintf(os.Stderr, "lancerd daemon: drain queue: %v\n", err)
	}

	for {
		frame, err := readFrame(conn)
		if err != nil {
			if err != io.EOF {
				fmt.Fprintf(os.Stderr, "lancerd daemon: attach read: %v\n", err)
			}
			return
		}
		var msg rpcMessage
		if err := json.Unmarshal(frame, &msg); err != nil {
			continue
		}
		r.handleAttachMessage(&msg)
	}
}

func (r *resident) handleAttachMessage(msg *rpcMessage) {
	r.core.handleMessage(msg)
}

func (r *resident) drainToAttach() error {
	events := r.core.approvals.pendingEvents()
	for _, event := range events {
		notification, err := marshalPendingNotification(event)
		if err != nil {
			continue
		}
		if err := r.writeToAttach(notification); err != nil {
			return err
		}
	}
	return nil
}

func (r *resident) notifyAttachOrQueue(event ApprovalEvent) error {
	if err := r.queue.add(event); err != nil {
		return err
	}
	notification, err := marshalPendingNotification(event)
	if err != nil {
		return err
	}
	if err := r.writeToAttach(notification); err == nil {
		return nil
	}
	return nil
}

func (r *resident) writeToAttach(data []byte) error {
	r.attachMu.Lock()
	conn := r.attach
	r.attachMu.Unlock()
	if conn == nil {
		return fmt.Errorf("no attach client")
	}
	r.writeMu.Lock()
	defer r.writeMu.Unlock()
	return writeFrame(conn, data)
}

// wireRelayFromPairing reads relay-pairing.json and, if present, creates the
// E2E relay client + router and installs them on the resident's server.
func (r *resident) wireRelayFromPairing() {
	cfg, err := readRelayPairing()
	if err != nil {
		return // no pairing file yet — daemon runs without relay
	}
	migrated, err := migrateRetiredHostedRelay(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "lancerd daemon: refused retired hosted relay migration: %v\n", err)
		return
	}
	if migrated {
		fmt.Fprintf(os.Stderr, "lancerd daemon: migrated hosted relay endpoint to %s; pairing identity preserved\n", cfg.RelayURL)
	}
	r.connectRelay(cfg)
}

// connectRelay creates an E2E relay client for the given config, wires the
// router to the server, and starts the client.
func (r *resident) connectRelay(cfg *relayPairConfig) {
	// Decode the persisted keypair.
	privRaw, err := base64.RawURLEncoding.DecodeString(cfg.PrivateKey)
	if err != nil || len(privRaw) != 32 {
		fmt.Fprintf(os.Stderr, "lancerd daemon: invalid private key in relay pairing\n")
		return
	}
	pubRaw, err := base64.RawURLEncoding.DecodeString(cfg.PublicKey)
	if err != nil || len(pubRaw) != 32 {
		fmt.Fprintf(os.Stderr, "lancerd daemon: invalid public key in relay pairing\n")
		return
	}
	var privKey, pubKey [32]byte
	copy(privKey[:], privRaw)
	copy(pubKey[:], pubRaw)

	client := newE2ERelayClientWithKey(cfg.RelayURL, cfg.Code, nil, privKey, pubKey)
	if client == nil {
		fmt.Fprintf(os.Stderr, "lancerd daemon: failed to create relay client\n")
		return
	}
	// Durable confirmation survives process restart — seed everConfirmed
	// before the first dial so a code_expired after backend cold-start never
	// remints a phone that already completed exchange on this identity.
	if cfg.isConfirmed() {
		client.everConfirmed = true
	}

	router := newE2ERouter(client, r.core)
	r.core.setE2ERouter(router)
	client.start()
	r.relayMu.Lock()
	r.relayCode = cfg.Code
	r.relayMu.Unlock()
	fmt.Fprintln(os.Stderr, "lancerd daemon: E2E relay started")
}

// startRelayWatch monitors relay-pairing.json for changes and (re)connects the
// E2E relay when a new pairing is written (e.g. by lancerd pair).
func (r *resident) startRelayWatch() {
	w := newRelayPairWatcher(func(cfg *relayPairConfig) {
		// If a router already exists, stop its client and reconnect. This is
		// how pairing completes (pair/begin writes the file, this reconnects
		// on the new code) — but it equally means a re-pair silently orphans
		// every phone on the previous code, so log the transition explicitly.
		if r.core.e2e != nil {
			r.relayMu.Lock()
			oldCode := r.relayCode
			r.relayMu.Unlock()
			if oldCode != "" && oldCode != cfg.Code {
				fmt.Fprintln(os.Stderr, "lancerd daemon: relay pairing identity changed — dropping the previous relay session; phones on it are orphaned until re-paired")
			}
			r.core.e2e.client.stop()
		}
		r.connectRelay(cfg)
	})
	w.start()
}
