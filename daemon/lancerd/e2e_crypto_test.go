package main

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"testing"
)

// Proves the full pairing crypto end-to-end: two parties derive an identical
// session key from a shared X25519 secret + matching HKDF context, a frame
// sealed by one opens with the other's key, and any tampering fails closed.
func TestE2ECryptoRoundTrip(t *testing.T) {
	privA, pubA, err := generateKeyPair()
	if err != nil {
		t.Fatalf("generateKeyPair A: %v", err)
	}
	privB, pubB, err := generateKeyPair()
	if err != nil {
		t.Fatalf("generateKeyPair B: %v", err)
	}

	// The HKDF salt/info context (helperID + key material) must be identical on
	// both sides; only the X25519 shared secret differs by which key is private.
	const helperID = "helper-123"
	helperKeyB64 := base64URLEncode(pubA[:])
	appKeyB64 := base64URLEncode(pubB[:])

	keyA, err := deriveSessionKey(privA, base64URLEncode(pubB[:]), helperID, helperKeyB64, appKeyB64)
	if err != nil {
		t.Fatalf("deriveSessionKey A: %v", err)
	}
	keyB, err := deriveSessionKey(privB, base64URLEncode(pubA[:]), helperID, helperKeyB64, appKeyB64)
	if err != nil {
		t.Fatalf("deriveSessionKey B: %v", err)
	}

	if !bytes.Equal(keyA, keyB) {
		t.Fatalf("derived session keys disagree:\n A=%x\n B=%x", keyA, keyB)
	}
	if len(keyA) != 32 {
		t.Fatalf("session key length = %d, want 32", len(keyA))
	}
	if bytes.Equal(keyA, make([]byte, 32)) {
		t.Fatal("session key is all zero")
	}

	plaintext := []byte("approve: rm -rf /tmp/agent-scratch")
	frame, err := encryptFrame(plaintext, keyA)
	if err != nil {
		t.Fatalf("encryptFrame: %v", err)
	}

	got, err := decryptFrame(frame, keyB)
	if err != nil {
		t.Fatalf("decryptFrame with peer key: %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Fatalf("round-trip plaintext = %q, want %q", got, plaintext)
	}

	// A tampered ciphertext must fail the AEAD tag check, not silently decrypt.
	ctBytes, err := base64.RawURLEncoding.DecodeString(frame.Ciphertext)
	if err != nil {
		t.Fatalf("decode ciphertext: %v", err)
	}
	ctBytes[0] ^= 0xFF
	tampered := &encryptedFrame{
		Version:    frame.Version,
		Nonce:      frame.Nonce,
		Ciphertext: base64.RawURLEncoding.EncodeToString(ctBytes),
		Tag:        frame.Tag,
	}
	if _, err := decryptFrame(tampered, keyB); err == nil {
		t.Fatal("tampered ciphertext decrypted without error — AEAD integrity broken")
	}
}

// A key derived from a mismatched peer public key must not open the frame —
// guards against the derivation collapsing to a constant.
func TestE2ECryptoWrongPeerKeyFails(t *testing.T) {
	privA, _, _ := generateKeyPair()
	_, pubB, _ := generateKeyPair()
	privX, pubX, _ := generateKeyPair()

	const helperID = "helper-123"
	helperKeyB64 := base64URLEncode(pubX[:])
	appKeyB64 := base64URLEncode(pubB[:])

	keyA, err := deriveSessionKey(privA, base64URLEncode(pubB[:]), helperID, helperKeyB64, appKeyB64)
	if err != nil {
		t.Fatalf("deriveSessionKey A: %v", err)
	}
	// privX paired against pubB derives a different shared secret than privA/pubB.
	keyWrong, err := deriveSessionKey(privX, base64URLEncode(pubB[:]), helperID, helperKeyB64, appKeyB64)
	if err != nil {
		t.Fatalf("deriveSessionKey X: %v", err)
	}
	if bytes.Equal(keyA, keyWrong) {
		t.Fatal("unrelated key pair derived the same session key")
	}

	frame, err := encryptFrame([]byte("secret"), keyA)
	if err != nil {
		t.Fatalf("encryptFrame: %v", err)
	}
	if _, err := decryptFrame(frame, keyWrong); err == nil {
		t.Fatal("frame decrypted under the wrong session key")
	}
}

// TestE2EReplayedFrameRejected is the item-3 regression: the AEAD alone
// happily decrypts a captured/replayed frame a second time (it has no notion
// of "already seen"), so replay resistance must come from the seq envelope +
// replaySequencer layered on top. A frame that decrypts successfully twice
// must still only be ACCEPTED once by the sequencer. This exercises the
// legacy (no generation tag) path — gen == "" throughout — proving no
// regression against a not-yet-upgraded counterpart.
func TestE2EReplayedFrameRejected(t *testing.T) {
	priv, _, err := generateKeyPair()
	if err != nil {
		t.Fatalf("generateKeyPair: %v", err)
	}
	_, peer, err := generateKeyPair()
	if err != nil {
		t.Fatalf("generateKeyPair peer: %v", err)
	}
	key, err := deriveSessionKey(priv, base64URLEncode(peer[:]), "helper", "hk", "ak")
	if err != nil {
		t.Fatalf("deriveSessionKey: %v", err)
	}

	wrapped0, err := wrapSeq(0, []byte(`{"type":"approval","payload":{}}`))
	if err != nil {
		t.Fatalf("wrapSeq: %v", err)
	}
	frame, err := encryptFrame(wrapped0, key)
	if err != nil {
		t.Fatalf("encryptFrame: %v", err)
	}

	var seq replaySequencer

	// First delivery: decrypts and is accepted.
	plaintext, err := decryptFrame(frame, key)
	if err != nil {
		t.Fatalf("decryptFrame (first delivery): %v", err)
	}
	gotSeq, gotGen, _, err := unwrapSeq(plaintext)
	if err != nil {
		t.Fatalf("unwrapSeq: %v", err)
	}
	if gotGen != "" {
		t.Fatalf("legacy wrapSeq must produce an empty gen, got %q", gotGen)
	}
	if seq.accept(gotGen, gotSeq) != replayAccepted {
		t.Fatal("first delivery of seq=0 must be accepted")
	}

	// Replay: the identical captured frame decrypts successfully again (AEAD
	// has no memory), but the sequencer must reject it as already-seen.
	replayPlaintext, err := decryptFrame(frame, key)
	if err != nil {
		t.Fatalf("decryptFrame (replay) unexpectedly failed: %v", err)
	}
	replaySeq, replayGen, _, err := unwrapSeq(replayPlaintext)
	if err != nil {
		t.Fatalf("unwrapSeq (replay): %v", err)
	}
	if result := seq.accept(replayGen, replaySeq); result != replayRejectedReplay {
		t.Fatalf("a replayed frame (same seq) must be rejected as replayRejectedReplay, got %v", result)
	}

	// A genuinely new, higher sequence is still accepted.
	wrapped1, _ := wrapSeq(1, []byte(`{"type":"approval","payload":{}}`))
	frame1, err := encryptFrame(wrapped1, key)
	if err != nil {
		t.Fatalf("encryptFrame seq=1: %v", err)
	}
	plaintext1, err := decryptFrame(frame1, key)
	if err != nil {
		t.Fatalf("decryptFrame seq=1: %v", err)
	}
	gotSeq1, gotGen1, _, err := unwrapSeq(plaintext1)
	if err != nil {
		t.Fatalf("unwrapSeq seq=1: %v", err)
	}
	if seq.accept(gotGen1, gotSeq1) != replayAccepted {
		t.Fatal("a strictly-increasing new sequence must be accepted")
	}

	// reset() (a new pairing generation) allows seq=0 again — the legacy
	// no-gen path must behave exactly like the original bare counter.
	seq.reset()
	if seq.accept("", 0) != replayAccepted {
		t.Fatal("after reset(), seq=0 must be acceptable again (new generation)")
	}
}

// TestE2EGenerationGuardStopsCrossGenerationPoisoning is the exact scenario
// reproduced live on 2026-07-15 (both directions of the stuck-Working/Retry
// bug): a stale in-flight frame from a PREVIOUS reconnect generation arrives
// AFTER reset(), and — on the old bare-counter design — gets accepted because
// its seq is high, poisoning `last` so every legitimate new-generation frame
// (seq starting at 0) is rejected as "out of order" until the next
// peer_joined. The generation tag must close this: a frame tagged with a
// RETIRED generation is rejected without touching currentGen/last, so the new
// generation's low sequence numbers are unaffected.
func TestE2EGenerationGuardStopsCrossGenerationPoisoning(t *testing.T) {
	var seq replaySequencer

	// Generation A: frames 100, 101 accepted normally.
	if seq.accept("gen-A", 100) != replayAccepted {
		t.Fatal("gen-A seq=100 (first frame of first generation) must be accepted")
	}
	if seq.accept("gen-A", 101) != replayAccepted {
		t.Fatal("gen-A seq=101 must be accepted (strictly increasing within gen-A)")
	}

	// A peer_joined fires (daemon restarted / app relaunched) — reset().
	seq.reset()

	// A stale gen-A frame (seq=102, sent before the reconnect but delivered
	// after it) arrives. On the OLD bare-counter code this would be accepted
	// (102 > 0) and poison `last` to 102. The fix must reject it as a stale
	// generation and leave currentGen/last untouched.
	if result := seq.accept("gen-A", 102); result != replayRejectedStaleGeneration {
		t.Fatalf("stale gen-A seq=102 after reset() must be rejected as replayRejectedStaleGeneration, got %v", result)
	}

	// The new generation B's frames, starting at seq=0, MUST be accepted —
	// this is the exact assertion that fails on the old code (the bug: the
	// poisoned `last` from the stale frame rejects every new-generation frame
	// as "out of order" for the life of the connection).
	if seq.accept("gen-B", 0) != replayAccepted {
		t.Fatal("gen-B seq=0 (first frame of the new generation) must be accepted after a stale gen-A frame arrived")
	}
	if seq.accept("gen-B", 1) != replayAccepted {
		t.Fatal("gen-B seq=1 must be accepted (strictly increasing within gen-B)")
	}
	if seq.accept("gen-B", 2) != replayAccepted {
		t.Fatal("gen-B seq=2 must be accepted (strictly increasing within gen-B)")
	}

	// A later, even-more-stale gen-A frame (seq=103) must still be rejected —
	// gen-A stays retired even after gen-B has become current.
	if result := seq.accept("gen-A", 103); result != replayRejectedStaleGeneration {
		t.Fatalf("gen-A seq=103 must still be rejected as replayRejectedStaleGeneration after gen-B is current, got %v", result)
	}

	// True replay WITHIN gen-B (the current generation) must still be
	// rejected — the fix must not weaken in-generation replay resistance.
	if result := seq.accept("gen-B", 1); result != replayRejectedReplay {
		t.Fatalf("replaying gen-B seq=1 must be rejected as replayRejectedReplay, got %v", result)
	}
	if result := seq.accept("gen-B", 0); result != replayRejectedReplay {
		t.Fatalf("replaying gen-B seq=0 (below last) must be rejected as replayRejectedReplay, got %v", result)
	}
}

// TestE2EGenerationGuardLegacyPeerUnchanged proves a peer that never tags a
// frame with a generation (gen == "" on every frame — a not-yet-upgraded
// counterpart) sees byte-for-byte the same accept/reject decisions as the
// original bare monotonic counter, including across reset(). Co-deploy
// closes the security hole; this test guards against a regression for the
// window before both sides have upgraded.
func TestE2EGenerationGuardLegacyPeerUnchanged(t *testing.T) {
	var seq replaySequencer

	if seq.accept("", 0) != replayAccepted {
		t.Fatal("legacy first-ever seq=0 must be accepted")
	}
	if seq.accept("", 0) != replayRejectedReplay {
		t.Fatal("legacy replay of seq=0 must be rejected")
	}
	if seq.accept("", 1) != replayAccepted {
		t.Fatal("legacy seq=1 must be accepted")
	}
	if seq.accept("", 1) != replayRejectedReplay {
		t.Fatal("legacy replay of seq=1 must be rejected")
	}
	if seq.accept("", 0) != replayRejectedReplay {
		t.Fatal("legacy earlier seq=0 must be rejected even though seq=1 was already accepted")
	}

	seq.reset()
	if seq.accept("", 0) != replayAccepted {
		t.Fatal("after reset(), legacy seq=0 must be acceptable again")
	}

	// A legacy peer's stale in-flight frame (high seq from before reset)
	// arriving after reset() is still subject to the ORIGINAL bare-counter
	// check (gen == currentGen == ""), not the generation-guard rejection —
	// this is the documented no-regression tradeoff: only co-deploy (every
	// frame tagged) closes the hole completely.
	if seq.accept("", 1) != replayAccepted {
		t.Fatal("legacy seq=1 after reset() must be accepted (strictly increasing from the fresh seq=0)")
	}
}

// TestE2EGenerationGuardSeenGensCapEviction proves seenGens is bounded: once
// more than maxTrackedGenerations distinct generations have been retired, the
// OLDEST is evicted (FIFO) so a long-lived daemon with many reconnects can't
// grow this set without bound. A frame tagged with an evicted generation is
// no longer classified as "stale" (it looks like a brand-new generation) —
// an accepted tradeoff for boundedness, since a generation that old is
// realistically long gone from the wire.
func TestE2EGenerationGuardSeenGensCapEviction(t *testing.T) {
	var seq replaySequencer

	// Retire maxTrackedGenerations+1 distinct generations one at a time: each
	// new gen's first frame adopts it, retiring the previous currentGen into
	// seenGens. This produces maxTrackedGenerations+1 total remembers (gen-0
	// through gen-maxTrackedGenerations), one more than the cap, so the
	// oldest (gen-0) must be evicted.
	if seq.accept("gen-0", 0) != replayAccepted {
		t.Fatal("gen-0 seq=0 must be accepted")
	}
	for i := 1; i <= maxTrackedGenerations+1; i++ {
		gen := fmt.Sprintf("gen-%d", i)
		if seq.accept(gen, 0) != replayAccepted {
			t.Fatalf("first frame of %s must be accepted", gen)
		}
	}
	// Check gen-1 (retired more recently, still within the cap) BEFORE gen-0:
	// a stale-generation rejection doesn't mutate state, but the later
	// gen-0 check below (a genuinely-new-looking generation) does adopt and
	// evict, so order matters for this assertion.
	if result := seq.accept("gen-1", 999); result != replayRejectedStaleGeneration {
		t.Fatalf("gen-1 should still be tracked in seenGens (not evicted), got %v", result)
	}
	// gen-0 was the FIRST generation retired into seenGens, so it must be the
	// first evicted once the set exceeds its cap — a frame tagged with it now
	// looks like a brand-new (never-seen) generation rather than "stale".
	if result := seq.accept("gen-0", 999); result == replayRejectedStaleGeneration {
		t.Fatal("gen-0 should have been evicted from seenGens (FIFO) once the cap was exceeded, but it was still classified as stale")
	}
}
