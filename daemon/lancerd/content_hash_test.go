package main

import "testing"

// TestComputeContentHashDeterministicAndFieldSensitive proves the
// canonicalization is stable (same input → same hash) and that every field
// it covers actually participates (changing any one changes the digest),
// including across a field boundary — the \x1f separator must prevent
// "ab"+"c" from hashing the same as "a"+"bc".
func TestComputeContentHashDeterministicAndFieldSensitive(t *testing.T) {
	base := computeContentHash("echo hi", "", "/tmp", "")
	if again := computeContentHash("echo hi", "", "/tmp", ""); again != base {
		t.Fatalf("computeContentHash is not deterministic: %q vs %q", base, again)
	}

	variants := map[string]string{
		"command":   computeContentHash("echo bye", "", "/tmp", ""),
		"patch":     computeContentHash("echo hi", "diff --git a b", "/tmp", ""),
		"cwd":       computeContentHash("echo hi", "", "/other", ""),
		"toolInput": computeContentHash("echo hi", "", "/tmp", `{"x":1}`),
	}
	for field, v := range variants {
		if v == base {
			t.Fatalf("changing %s must change the hash, but it didn't", field)
		}
	}

	if computeContentHash("ab", "c", "", "") == computeContentHash("a", "bc", "", "") {
		t.Fatal("hash must not collide across a shifted field boundary")
	}
}

// TestApprovalResolveRejectsContentHashMismatch is the item-1 regression: a
// decision whose echoed contentHash doesn't match the pending event's stored
// ContentHash must be rejected without resolving the approval, so the real
// decision (or a corrected retry) can still land later.
func TestApprovalResolveRejectsContentHashMismatch(t *testing.T) {
	s := newApprovalStore()
	event := ApprovalEvent{
		ApprovalID:  "hash-1",
		Command:     "rm -rf /tmp/x",
		CWD:         "/tmp",
		ContentHash: computeContentHash("rm -rf /tmp/x", "", "/tmp", ""),
	}
	ch := s.add(event)

	if _, ok := s.resolve("hash-1", "approve", "", "not-the-real-hash"); ok {
		t.Fatal("resolve must reject a decision whose contentHash does not match the pending event")
	}
	select {
	case d := <-ch:
		t.Fatalf("no decision should have been delivered on a hash mismatch, got %+v", d)
	default:
	}
	pending := s.pendingEvents()
	if len(pending) != 1 || pending[0].ApprovalID != "hash-1" {
		t.Fatalf("approval must remain pending after a rejected mismatched decision, got %+v", pending)
	}

	if _, ok := s.resolve("hash-1", "approve", "", event.ContentHash); !ok {
		t.Fatal("resolve with the correct contentHash should succeed")
	}
	select {
	case d := <-ch:
		if d.decision != "approve" {
			t.Fatalf("decision = %q, want approve", d.decision)
		}
	default:
		t.Fatal("expected a decision to be delivered after a correct-hash resolve")
	}
}

// TestComputeContentHashCrossLanguageVector pins the shared vector also
// asserted by the Swift side (ApprovalContentHashTests.matchesGoVector) so a
// canonicalization change in either language breaks a test in that language.
func TestComputeContentHashCrossLanguageVector(t *testing.T) {
	const want = "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3"
	if got := computeContentHash("echo hi", "", "/tmp", ""); got != want {
		t.Fatalf("cross-language vector mismatch: got %s, want %s", got, want)
	}
}
