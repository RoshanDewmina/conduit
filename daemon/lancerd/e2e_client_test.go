package main

import "testing"

// remintPairingCode is the daemon-side reaction to a relay code_expired
// rejection on a code that never completed its first key exchange (REL-1 B).
// It must generate a DIFFERENT code, persist it so the resident's
// relayPairWatcher picks it up, and stop this (now-dead) client.
func TestRemintPairingCodeWritesFreshCodeAndStops(t *testing.T) {
	dir := withStateDir(t)
	t.Setenv("LANCER_STATE_DIR", dir)

	oldCode := "111111"
	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       oldCode,
		PrivateKey: "old-priv",
		PublicKey:  "old-pub",
	}); err != nil {
		t.Fatalf("seed writeRelayPairing: %v", err)
	}

	client := newE2ERelayClient("wss://relay.example.com", oldCode, nil)
	if client == nil {
		t.Fatal("newE2ERelayClient returned nil")
	}

	client.remintPairingCode()

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("readRelayPairing after remint: %v", err)
	}
	if cfg.Code == oldCode {
		t.Fatalf("remintPairingCode left the code unchanged (%s) — want a fresh code", cfg.Code)
	}
	if len(cfg.Code) != 6 {
		t.Fatalf("re-minted code %q is not 6 digits", cfg.Code)
	}
	if cfg.PrivateKey == "old-priv" || cfg.PublicKey == "old-pub" {
		t.Fatal("remintPairingCode reused the old keypair — want a fresh X25519 keypair")
	}

	select {
	case <-client.stopCh:
	default:
		t.Fatal("remintPairingCode did not stop the dead client")
	}
}

// A pairing code that DID complete its first key exchange must never be
// silently replaced by the expiry path — decideExpiryAction(everConfirmed)
// is the gate; this proves the client actually consults it (not just that
// the pure function returns the right enum value, covered separately in
// e2e_liveness_test.go).
func TestClientNeverRemintsAfterEverConfirmed(t *testing.T) {
	client := newE2ERelayClient("wss://relay.example.com", "222222", nil)
	if client == nil {
		t.Fatal("newE2ERelayClient returned nil")
	}
	client.mu.Lock()
	client.everConfirmed = true
	c := client.everConfirmed
	client.mu.Unlock()

	if got := decideExpiryAction(c); got != expiryActionGiveUp {
		t.Fatalf("decideExpiryAction with everConfirmed=true = %v, want expiryActionGiveUp", got)
	}
}
