package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// schedule is a simple interval-based recurring dispatch, persisted to
// ~/.lancer/schedules.json. Cron expressions are a future extension.
type schedule struct {
	ID           string  `json:"id"`
	Agent        string  `json:"agent"`
	CWD          string  `json:"cwd"`
	Prompt       string  `json:"prompt"`
	EverySeconds int64   `json:"everySeconds"`
	BudgetUSD    float64 `json:"budgetUSD"`
	LastRunUnix  int64   `json:"lastRunUnix"`
}

type scheduler struct {
	mu        sync.Mutex
	path      string
	schedules []schedule
}

func newScheduler(home string) *scheduler {
	s := &scheduler{path: filepath.Join(home, ".lancer", "schedules.json")}
	s.load()
	return s
}

func (s *scheduler) load() {
	data, err := os.ReadFile(s.path)
	if err != nil {
		return
	}
	var scs []schedule
	if json.Unmarshal(data, &scs) == nil {
		s.schedules = scs
	}
}

func (s *scheduler) persistLocked() {
	_ = os.MkdirAll(filepath.Dir(s.path), 0700)
	data, err := json.MarshalIndent(s.schedules, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(s.path, data, 0600)
}

func (s *scheduler) add(sc schedule) schedule {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sc.ID == "" {
		sc.ID = newUUID()
	}
	s.schedules = append(s.schedules, sc)
	s.persistLocked()
	return sc
}

func (s *scheduler) list() []schedule {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]schedule(nil), s.schedules...)
}

func (s *scheduler) remove(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := s.schedules[:0]
	removed := false
	for _, sc := range s.schedules {
		if sc.ID == id {
			removed = true
			continue
		}
		out = append(out, sc)
	}
	s.schedules = out
	if removed {
		s.persistLocked()
	}
	return removed
}

// due returns schedules whose interval has elapsed at now.
func (s *scheduler) due(now time.Time) []schedule {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []schedule
	for _, sc := range s.schedules {
		if sc.EverySeconds <= 0 {
			continue
		}
		if now.Unix()-sc.LastRunUnix >= sc.EverySeconds {
			out = append(out, sc)
		}
	}
	return out
}

func (s *scheduler) markRun(id string, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.schedules {
		if s.schedules[i].ID == id {
			s.schedules[i].LastRunUnix = now.Unix()
		}
	}
	s.persistLocked()
}

// tick fires every due schedule through dispatchFn (which applies the same
// policy + budget gate as a manual dispatch) and records the run time.
// `now` is injected so tests are deterministic.
func (s *scheduler) tick(now time.Time, dispatchFn func(dispatchParams) dispatchResult) int {
	due := s.due(now)
	for _, sc := range due {
		dispatchFn(dispatchParams{Agent: sc.Agent, CWD: sc.CWD, Prompt: sc.Prompt, BudgetUSD: sc.BudgetUSD})
		s.markRun(sc.ID, now)
	}
	return len(due)
}
