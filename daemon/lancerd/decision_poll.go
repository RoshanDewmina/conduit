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

// decisionPoller pulls phone-posted decisions from push-backend and applies the
// matching pending approvals — the path that works when no SSH client is attached.
// apply is wired to server.applyDecision so poll-delivered decisions persist
// audit + approveAlways policy identically to the live-SSH respond path.
type decisionPoller struct {
	apply               func(id, decision, edited string) (ApprovalEvent, bool)
	pollIntervalForTest time.Duration

	mu         sync.Mutex
	running    bool
	relayToken string
	stop       chan struct{}
}

func newDecisionPoller(apply func(id, decision, edited string) (ApprovalEvent, bool)) *decisionPoller {
	return &decisionPoller{apply: apply}
}

func (p *decisionPoller) interval() time.Duration {
	if p.pollIntervalForTest > 0 {
		return p.pollIntervalForTest
	}
	return 3 * time.Second
}

// ensureRunning starts the poll loop once for a given backend URL + session,
// authenticating polls with the per-session relayToken.
func (p *decisionPoller) ensureRunning(backendURL, sessionID, relayToken string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running || backendURL == "" || sessionID == "" {
		return
	}
	p.relayToken = relayToken
	p.running = true
	p.stop = make(chan struct{})
	go p.loop(backendURL, sessionID, relayToken, p.stop)
}

func (p *decisionPoller) stopForTest() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running {
		close(p.stop)
		p.running = false
	}
}

func (p *decisionPoller) loop(backendURL, sessionID, relayToken string, stop chan struct{}) {
	ticker := time.NewTicker(p.interval())
	defer ticker.Stop()
	endpoint := strings.TrimRight(backendURL, "/") + "/decisions?sessionId=" + url.QueryEscape(sessionID)
	client := &http.Client{Timeout: 10 * time.Second}
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			req, err := http.NewRequest(http.MethodGet, endpoint, nil)
			if err != nil {
				continue
			}
			// Present the per-session capability token so the backend authorizes
			// this poll (constant-time compare). A 401 (unknown/expired token) just
			// yields no decisions this tick; lancerd's ~120s auto-deny backstops.
			if relayToken != "" {
				req.Header.Set("Authorization", "Bearer "+relayToken)
			}
			resp, err := client.Do(req)
			if err != nil {
				continue
			}
			var body struct {
				Decisions []backendDecision `json:"decisions"`
			}
			if resp.StatusCode == http.StatusOK {
				_ = json.NewDecoder(resp.Body).Decode(&body)
			}
			resp.Body.Close()
			for _, d := range body.Decisions {
				p.apply(d.ApprovalID, d.Decision, d.EditedToolInput)
			}
		}
	}
}
