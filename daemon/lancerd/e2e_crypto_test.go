package main

import (
	"bytes"
	"encoding/base64"
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
// must still only be ACCEPTED once by the sequencer.
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
	gotSeq, _, err := unwrapSeq(plaintext)
	if err != nil {
		t.Fatalf("unwrapSeq: %v", err)
	}
	if !seq.accept(gotSeq) {
		t.Fatal("first delivery of seq=0 must be accepted")
	}

	// Replay: the identical captured frame decrypts successfully again (AEAD
	// has no memory), but the sequencer must reject it as already-seen.
	replayPlaintext, err := decryptFrame(frame, key)
	if err != nil {
		t.Fatalf("decryptFrame (replay) unexpectedly failed: %v", err)
	}
	replaySeq, _, err := unwrapSeq(replayPlaintext)
	if err != nil {
		t.Fatalf("unwrapSeq (replay): %v", err)
	}
	if seq.accept(replaySeq) {
		t.Fatal("a replayed frame (same seq) must be rejected, not accepted a second time")
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
	gotSeq1, _, err := unwrapSeq(plaintext1)
	if err != nil {
		t.Fatalf("unwrapSeq seq=1: %v", err)
	}
	if !seq.accept(gotSeq1) {
		t.Fatal("a strictly-increasing new sequence must be accepted")
	}

	// reset() (a new pairing generation) allows seq=0 again.
	seq.reset()
	if !seq.accept(0) {
		t.Fatal("after reset(), seq=0 must be acceptable again (new generation)")
	}
}
