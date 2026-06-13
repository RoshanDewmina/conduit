package main

import (
	"strings"
	"testing"
)

// TestApprovalResolveCaseInsensitive guards the live-relay decision path: the
// iOS app sends the approval ID via Swift's `UUID.uuidString` (UPPERCASE), while
// conduitd stores the hook event's ID lowercase. A case-sensitive lookup made
// every phone approval miss and the agent hung to the 120 s timeout (then
// auto-denied). UUIDs are case-insensitive (RFC 4122), so resolve must match
// regardless of case.
func TestApprovalResolveCaseInsensitive(t *testing.T) {
	s := newApprovalStore()
	lower := "cace8588-685d-4c34-8081-231fef1f974d"
	ch := s.add(ApprovalEvent{ApprovalID: lower})

	event, ok := s.resolve(strings.ToUpper(lower), "approve", "")
	if !ok {
		t.Fatalf("resolve with UPPERCASE id must match the lowercase-stored pending")
	}
	if event.ApprovalID != lower {
		t.Fatalf("resolved event ID = %q, want %q", event.ApprovalID, lower)
	}
	select {
	case d := <-ch:
		if d.decision != "approve" {
			t.Fatalf("hook decision = %q, want approve", d.decision)
		}
	default:
		t.Fatalf("the waiting hook's decision channel should have been signaled")
	}
}
