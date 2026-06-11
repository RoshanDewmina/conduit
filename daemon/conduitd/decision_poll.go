package main

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type backendDecision struct {
	ApprovalID      string `json:"approvalId"`
	Decision        string `json:"decision"`
	EditedToolInput string `json:"editedToolInput,omitempty"`
}

// decisionPoller pulls phone-posted decisions from push-backend and resolves the
// matching pending approvals — the path that works when no SSH client is attached.
type decisionPoller struct {
	resolve             func(id, decision, edited string) (ApprovalEvent, bool)
	pollIntervalForTest time.Duration

	mu      sync.Mutex
	running bool
	stop    chan struct{}
}

func newDecisionPoller(resolve func(id, decision, edited string) (ApprovalEvent, bool)) *decisionPoller {
	return &decisionPoller{resolve: resolve}
}

func (p *decisionPoller) interval() time.Duration {
	if p.pollIntervalForTest > 0 {
		return p.pollIntervalForTest
	}
	return 3 * time.Second
}

// ensureRunning starts the poll loop once for a given backend URL + session.
func (p *decisionPoller) ensureRunning(backendURL, sessionID string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running || backendURL == "" || sessionID == "" {
		return
	}
	p.running = true
	p.stop = make(chan struct{})
	go p.loop(backendURL, sessionID, p.stop)
}

func (p *decisionPoller) stopForTest() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running {
		close(p.stop)
		p.running = false
	}
}

func (p *decisionPoller) loop(backendURL, sessionID string, stop chan struct{}) {
	ticker := time.NewTicker(p.interval())
	defer ticker.Stop()
	endpoint := strings.TrimRight(backendURL, "/") + "/decisions?sessionId=" + url.QueryEscape(sessionID)
	client := &http.Client{Timeout: 10 * time.Second}
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			resp, err := client.Get(endpoint)
			if err != nil {
				continue
			}
			var body struct {
				Decisions []backendDecision `json:"decisions"`
			}
			_ = json.NewDecoder(resp.Body).Decode(&body)
			resp.Body.Close()
			for _, d := range body.Decisions {
				p.resolve(d.ApprovalID, d.Decision, d.EditedToolInput)
			}
		}
	}
}
