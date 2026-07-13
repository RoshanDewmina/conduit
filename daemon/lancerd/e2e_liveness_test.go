package main

import "testing"

func TestNextReconnectBackoffDoublesAndCaps(t *testing.T) {
	cap := e2eMaxReconnectBackoff
	cur := e2eInitialReconnectBackoff
	want := []int64{2, 4, 8, 16, 30, 30, 30} // seconds, given a 1s start and 30s cap
	for i, wantSec := range want {
		cur = nextReconnectBackoff(cur, cap)
		if got := int64(cur.Seconds()); got != wantSec {
			t.Fatalf("step %d: nextReconnectBackoff = %ds, want %ds", i, got, wantSec)
		}
	}
}

func TestNextReconnectBackoffZeroStartsAtInitial(t *testing.T) {
	got := nextReconnectBackoff(0, e2eMaxReconnectBackoff)
	if got != e2eInitialReconnectBackoff {
		t.Fatalf("nextReconnectBackoff(0, ...) = %v, want %v", got, e2eInitialReconnectBackoff)
	}
}

func TestExpiredCodeTrackerBoundsRetries(t *testing.T) {
	tr := newExpiredCodeTracker(3)

	streak, exceeded := tr.record()
	if streak != 1 || exceeded {
		t.Fatalf("rejection 1: streak=%d exceeded=%v, want 1/false", streak, exceeded)
	}

	streak, exceeded = tr.record()
	if streak != 2 || exceeded {
		t.Fatalf("rejection 2: streak=%d exceeded=%v, want 2/false", streak, exceeded)
	}

	streak, exceeded = tr.record()
	if streak != 3 || !exceeded {
		t.Fatalf("rejection 3: streak=%d exceeded=%v, want 3/true", streak, exceeded)
	}
}

func TestExpiredCodeTrackerResetClearsStreak(t *testing.T) {
	tr := newExpiredCodeTracker(2)
	tr.record()
	tr.reset()

	streak, exceeded := tr.record()
	if streak != 1 || exceeded {
		t.Fatalf("after reset, rejection 1: streak=%d exceeded=%v, want 1/false", streak, exceeded)
	}
}

func TestDecideExpiryActionRemintsWhenUnconfirmed(t *testing.T) {
	if got := decideExpiryAction(false); got != expiryActionRemint {
		t.Fatalf("decideExpiryAction(everConfirmed=false) = %v, want expiryActionRemint", got)
	}
}

func TestDecideExpiryActionReregistersConfirmedPairing(t *testing.T) {
	if got := decideExpiryAction(true); got != expiryActionReregister {
		t.Fatalf("decideExpiryAction(everConfirmed=true) = %v, want expiryActionReregister", got)
	}
}
