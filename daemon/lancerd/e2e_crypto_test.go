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
