package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

func (s *server) maybePostRunCompletePush(params any) {
	m, ok := params.(map[string]any)
	if !ok {
		return
	}
	status, _ := m["status"].(string)
	if status != "exited" && status != "failed" {
		return
	}
	runID, _ := m["runId"].(string)
	if runID == "" {
		return
	}
	exitCode := 0
	if code, ok := m["exitCode"].(int); ok {
		exitCode = code
	}
	command := runID
	s.dispatcher.mu.Lock()
	if run := s.dispatcher.runs[runID]; run != nil && run.Prompt != "" {
		command = run.Prompt
	}
	s.dispatcher.mu.Unlock()

	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev == nil || dev.PushBackendURL == "" {
		return
	}
	go s.postRunCompletePush(dev, command, exitCode)
}

func (s *server) postRunCompletePush(dev *registeredDevice, command string, exitCode int) {
	hostname, _ := os.Hostname()
	payload := map[string]interface{}{
		"sessionId": dev.SessionID,
		"command":   command,
		"exitCode":  exitCode,
		"hostName":  hostname,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return
	}
	url := strings.TrimRight(dev.PushBackendURL, "/") + "/run-complete"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if secret := strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET")); secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "push-backend run-complete POST failed: %v\n", err)
		return
	}
	resp.Body.Close()
}

func (s *server) notifyWaitingForInputSessions(sessions []SessionInfo) {
	const debounce = 5 * time.Minute
	for _, sess := range sessions {
		if sess.State != "waitingForInput" {
			continue
		}
		s.needsInputMu.Lock()
		if s.needsInputNotified == nil {
			s.needsInputNotified = make(map[string]time.Time)
		}
		if last, ok := s.needsInputNotified[sess.SessionID]; ok && time.Since(last) < debounce {
			s.needsInputMu.Unlock()
			continue
		}
		s.needsInputNotified[sess.SessionID] = time.Now()
		s.needsInputMu.Unlock()

		s.deviceMu.RLock()
		dev := s.device
		s.deviceMu.RUnlock()
		if dev == nil || dev.PushBackendURL == "" {
			continue
		}
		go s.postNeedsInputPush(dev, sess)
	}
}

func (s *server) postNeedsInputPush(dev *registeredDevice, sess SessionInfo) {
	hostname, _ := os.Hostname()
	title := sess.Title
	if title == "" {
		title = "Agent session"
	}
	payload := map[string]interface{}{
		"sessionId":       dev.SessionID,
		"hostName":        hostname,
		"agent":           sess.Provider,
		"vendorSessionId": sess.SessionID,
		"title":           title,
		"kind":            "needsInput",
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return
	}
	url := strings.TrimRight(dev.PushBackendURL, "/") + "/needs-input"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if secret := strings.TrimSpace(os.Getenv("APPROVAL_RELAY_SECRET")); secret != "" {
		req.Header.Set("Authorization", "Bearer "+secret)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "push-backend needs-input POST failed: %v\n", err)
		return
	}
	resp.Body.Close()
}
