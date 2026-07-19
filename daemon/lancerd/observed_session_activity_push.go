package main

import (
	"time"
)

// How often to re-scan observed (on-disk) agent sessions for Live Activity
// push-to-start. Separate from startScheduler's 30s ticker — this is a
// different concern and wants to be a bit snappier when an owner starts an
// agent in a terminal with the phone app closed.
const observedActivityPollInterval = 12 * time.Second

// isObservedSessionActive reports whether an indexed session should surface a
// Live Activity. Matches the states buildSessionIndex assigns for "something
// is happening right now": recentlyActive (mtime within recentlyActiveWindow),
// plus the providerManaged working/waitingForInput states from `claude agents`.
func isObservedSessionActive(s SessionInfo) bool {
	switch s.State {
	case "recentlyActive", "working", "waitingForInput":
		return true
	default:
		return false
	}
}

// startObservedActivityPush runs the observed-session Live Activity poller
// until stop. Call next to startScheduler from the resident / legacy serve paths.
func (s *server) startObservedActivityPush(stop <-chan struct{}) {
	go s.runObservedActivityPushLoop(stop, observedActivityPollInterval)
}

func (s *server) runObservedActivityPushLoop(stop <-chan struct{}, interval time.Duration) {
	// Immediate first poll so a session that was already active at daemon
	// start (or just became active between ticks) is not delayed a full interval.
	s.pollObservedSessionsForActivityPush()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			s.pollObservedSessionsForActivityPush()
		}
	}
}

func (s *server) listSessionsForObservedPush() ([]SessionInfo, error) {
	if s.listObservedSessions != nil {
		return s.listObservedSessions(s.home)
	}
	return buildSessionIndex(s.home)
}

// pollObservedSessionsForActivityPush push-starts a Live Activity for each
// newly-active observed session. The set is keyed by the *vendor* session ID
// (so we de-dupe per observed transcript); the push itself MUST use the phone's
// device SessionID (dev.SessionID) — the push-backend registry is keyed by
// that identity, not the vendor CLI's transcript ID.
func (s *server) pollObservedSessionsForActivityPush() {
	sessions, err := s.listSessionsForObservedPush()
	if err != nil {
		return
	}

	active := make(map[string]SessionInfo, len(sessions))
	for _, sess := range sessions {
		if sess.SessionID == "" || !isObservedSessionActive(sess) {
			continue
		}
		active[sess.SessionID] = sess
	}

	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()

	s.observedPushMu.Lock()
	if s.observedPushed == nil {
		s.observedPushed = map[string]struct{}{}
	}
	for id := range s.observedPushed {
		if _, ok := active[id]; !ok {
			delete(s.observedPushed, id)
		}
	}
	var toPush []SessionInfo
	if dev != nil && dev.PushBackendURL != "" {
		for id, sess := range active {
			if _, already := s.observedPushed[id]; already {
				continue
			}
			s.observedPushed[id] = struct{}{}
			toPush = append(toPush, sess)
		}
	}
	s.observedPushMu.Unlock()

	for _, sess := range toPush {
		agent := sess.Provider
		// CRITICAL: sessionID is the phone's persistent device identity, NOT
		// sess.SessionID (the vendor CLI transcript id).
		s.postRunStartPush(dev, dev.SessionID, &agent, nil, "")
	}
}
