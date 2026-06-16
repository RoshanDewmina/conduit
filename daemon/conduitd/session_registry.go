package main

import (
	"sync"
	"time"
)

type ShimSession struct {
	ID        string    `json:"id"`
	Agent     string    `json:"agent"`
	TmuxName  string    `json:"tmuxName"`
	CWD       string    `json:"cwd"`
	PID       int       `json:"pid"`
	StartedAt time.Time `json:"startedAt"`
	Status    string    `json:"status"` // running | exited | failed
}

type sessionRegistry struct {
	mu       sync.RWMutex
	sessions map[string]ShimSession
}

func newSessionRegistry() *sessionRegistry {
	return &sessionRegistry{sessions: make(map[string]ShimSession)}
}

func (r *sessionRegistry) register(s ShimSession) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if s.StartedAt.IsZero() {
		s.StartedAt = time.Now()
	}
	r.sessions[s.ID] = s
}

func (r *sessionRegistry) unregister(id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.sessions, id)
}

func (r *sessionRegistry) get(id string) (ShimSession, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	s, ok := r.sessions[id]
	return s, ok
}

func (r *sessionRegistry) list() []ShimSession {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]ShimSession, 0, len(r.sessions))
	for _, s := range r.sessions {
		out = append(out, s)
	}
	return out
}

func (r *sessionRegistry) count() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.sessions)
}
