package main

import (
	"testing"
	"time"
)

// Regression: getQuotaGuard() held d.mu and then re-locked the non-reentrant
// d.mu while computing quota alerts, causing a permanent deadlock. Because the
// resident daemon services the phone attach on a single goroutine, the phone's
// connect-time agent.quota.status call wedged that loop, so every later frame —
// including agent.approval.response — was never read and the agent always
// auto-denied at the 120s timeout. getQuotaGuard must return promptly, including
// the alert path (cap configured + spend high enough to generate an alert).
func TestGetQuotaGuard_DoesNotDeadlock(t *testing.T) {
	d := newDispatcher()
	d.setProviderCap("anthropic", 10.0, 100.0)
	d.updateProviderSpend("anthropic", 9.5) // 95% of daily cap → exercises alert path

	done := make(chan QuotaGuardResult, 1)
	go func() { done <- d.getQuotaGuard() }()

	select {
	case res := <-done:
		if len(res.Providers) == 0 {
			t.Fatal("expected at least one provider in quota result")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("getQuotaGuard deadlocked while computing quota alerts")
	}
}
