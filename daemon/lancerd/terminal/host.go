// Ported from Orca (MIT, Lovecast Inc.) — https://github.com/stablyai/orca
// Source: src/main/daemon/terminal-host.ts
package terminal

import (
	"fmt"
	"sync"
	"time"
)

const defaultMaxTombstones = 1000

// Host owns all interactive terminal sessions for a lancerd process.
// One sessionId → one PTY; createOrAttach reattaches when live.
type Host struct {
	mu         sync.Mutex
	sessions   map[string]*Session
	tombstones map[string]time.Time
	maxTomb    int
}

func NewHost() *Host {
	return &Host{
		sessions:   make(map[string]*Session),
		tombstones: make(map[string]time.Time),
		maxTomb:    defaultMaxTombstones,
	}
}

// CreateOrAttach creates a new PTY or reattaches to a live one.
func (h *Host) CreateOrAttach(opts CreateOrAttachOptions, client Client) (CreateOrAttachResult, error) {
	if opts.SessionID == "" {
		return CreateOrAttachResult{}, fmt.Errorf("sessionId is required")
	}

	h.mu.Lock()
	if _, killed := h.tombstones[opts.SessionID]; killed {
		h.mu.Unlock()
		return CreateOrAttachResult{}, fmt.Errorf("session %s was killed", opts.SessionID)
	}
	existing := h.sessions[opts.SessionID]
	h.mu.Unlock()

	if existing != nil && existing.IsAlive() {
		existing.DetachAllClients()
		if client != nil {
			existing.AttachClient(client)
		}
		snap := existing.GetSnapshot()
		return CreateOrAttachResult{
			IsNew:      false,
			Snapshot:   snap,
			PID:        existing.PID(),
			ShellState: "ready",
			SessionID:  opts.SessionID,
		}, nil
	}

	if existing != nil {
		existing.Kill()
		h.mu.Lock()
		delete(h.sessions, opts.SessionID)
		h.mu.Unlock()
	}

	sess, err := spawnSession(opts.SessionID, opts.Cols, opts.Rows, opts.CWD, opts.Env, opts.Command)
	if err != nil {
		return CreateOrAttachResult{}, err
	}
	if client != nil {
		sess.AttachClient(client)
	}

	h.mu.Lock()
	h.sessions[opts.SessionID] = sess
	h.mu.Unlock()

	return CreateOrAttachResult{
		IsNew:      true,
		Snapshot:   nil,
		PID:        sess.PID(),
		ShellState: "ready",
		SessionID:  opts.SessionID,
	}, nil
}

func (h *Host) Write(sessionID string, data []byte) (int, error) {
	sess, err := h.live(sessionID)
	if err != nil {
		return 0, err
	}
	return sess.Write(data)
}

func (h *Host) Resize(sessionID string, cols, rows int) error {
	sess, err := h.live(sessionID)
	if err != nil {
		return err
	}
	return sess.Resize(cols, rows)
}

func (h *Host) Kill(sessionID string) error {
	h.mu.Lock()
	sess := h.sessions[sessionID]
	if sess != nil {
		delete(h.sessions, sessionID)
	}
	h.tombstones[sessionID] = time.Now()
	h.trimTombstonesLocked()
	h.mu.Unlock()
	if sess == nil {
		return fmt.Errorf("session not found: %s", sessionID)
	}
	sess.Kill()
	return nil
}

func (h *Host) List() []SessionInfo {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := make([]SessionInfo, 0, len(h.sessions))
	for id, sess := range h.sessions {
		if !sess.IsAlive() {
			delete(h.sessions, id)
			continue
		}
		out = append(out, sess.Info())
	}
	return out
}

func (h *Host) GetSnapshot(sessionID string) (*Snapshot, error) {
	sess, err := h.live(sessionID)
	if err != nil {
		return nil, err
	}
	return sess.GetSnapshot(), nil
}

func (h *Host) Attach(sessionID string, client Client) (*Snapshot, error) {
	sess, err := h.live(sessionID)
	if err != nil {
		return nil, err
	}
	sess.DetachAllClients()
	if client != nil {
		sess.AttachClient(client)
	}
	return sess.GetSnapshot(), nil
}

func (h *Host) live(sessionID string) (*Session, error) {
	h.mu.Lock()
	sess := h.sessions[sessionID]
	h.mu.Unlock()
	if sess == nil || !sess.IsAlive() {
		return nil, fmt.Errorf("session not found: %s", sessionID)
	}
	return sess, nil
}

func (h *Host) trimTombstonesLocked() {
	for len(h.tombstones) > h.maxTomb {
		var oldestID string
		var oldest time.Time
		for id, t := range h.tombstones {
			if oldestID == "" || t.Before(oldest) {
				oldestID = id
				oldest = t
			}
		}
		delete(h.tombstones, oldestID)
	}
}
