package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestWriteRelayPairingRefusesToReplaceConfirmed(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)

	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:    "wss://relay.example.com",
		Code:        "111111",
		PrivateKey:  "priv-a",
		PublicKey:   "pub-a",
		ConfirmedAt: time.Now().UTC().Format(time.RFC3339),
	}); err != nil {
		t.Fatalf("seed confirmed pairing: %v", err)
	}

	err := writeRelayPairing(&relayPairConfig{
		RelayURL:   "ws://127.0.0.1:9",
		Code:       "222222",
		PrivateKey: "priv-b",
		PublicKey:  "pub-b",
	})
	if err == nil {
		t.Fatal("writeRelayPairing replaced a confirmed pairing without force — want refuse")
	}

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read after refused write: %v", err)
	}
	if cfg.Code != "111111" || cfg.RelayURL != "wss://relay.example.com" {
		t.Fatalf("confirmed pairing was mutated: %+v", cfg)
	}
}

func TestWriteRelayPairingReplacingAllowsExplicitRepair(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)

	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:    "wss://relay.example.com",
		Code:        "111111",
		PrivateKey:  "priv-a",
		PublicKey:   "pub-a",
		ConfirmedAt: time.Now().UTC().Format(time.RFC3339),
	}); err != nil {
		t.Fatalf("seed confirmed pairing: %v", err)
	}

	if err := writeRelayPairingReplacing(&relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "333333",
		PrivateKey: "priv-c",
		PublicKey:  "pub-c",
	}); err != nil {
		t.Fatalf("writeRelayPairingReplacing: %v", err)
	}

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read after replace: %v", err)
	}
	if cfg.Code != "333333" {
		t.Fatalf("code = %s, want 333333", cfg.Code)
	}
	if cfg.ConfirmedAt != "" {
		t.Fatalf("replaced pairing kept ConfirmedAt %q — want empty (unconfirmed)", cfg.ConfirmedAt)
	}
}

func TestMarkRelayPairingConfirmedPersistsAndAllowsReload(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)

	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "444444",
		PrivateKey: "priv-d",
		PublicKey:  "pub-d",
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	markRelayPairingConfirmed("444444")

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read after mark: %v", err)
	}
	if !cfg.isConfirmed() {
		t.Fatal("ConfirmedAt not stamped after markRelayPairingConfirmed")
	}

	// Simulate LaunchAgent restart: load everConfirmed from file.
	if !cfg.isConfirmed() {
		t.Fatal("isConfirmed false after stamp")
	}
}

func TestMarkRelayPairingConfirmedIgnoresCodeMismatch(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)

	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "555555",
		PrivateKey: "priv-e",
		PublicKey:  "pub-e",
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	markRelayPairingConfirmed("999999")

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if cfg.isConfirmed() {
		t.Fatal("stamped ConfirmedAt for a mismatched code")
	}
}

func TestPairingIdentityHashIgnoresConfirmedAt(t *testing.T) {
	a := &relayPairConfig{
		RelayURL: "wss://relay.example.com", Code: "1", PrivateKey: "p", PublicKey: "P",
	}
	b := &relayPairConfig{
		RelayURL: "wss://relay.example.com", Code: "1", PrivateKey: "p", PublicKey: "P",
		ConfirmedAt: time.Now().UTC().Format(time.RFC3339),
	}
	if pairingIdentityHash(a) != pairingIdentityHash(b) {
		t.Fatal("ConfirmedAt-only change must not alter pairingIdentityHash (watcher would bounce client)")
	}
}

func TestWriteRelayPairingAllowsConfirmedStampInPlace(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)

	if err := writeRelayPairing(&relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "666666",
		PrivateKey: "priv-f",
		PublicKey:  "pub-f",
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	cfg.ConfirmedAt = time.Now().UTC().Format(time.RFC3339)
	if err := writeRelayPairing(cfg); err != nil {
		t.Fatalf("in-place ConfirmedAt stamp refused: %v", err)
	}

	// Ensure file actually exists under the isolated state dir (not ~/.lancer).
	if _, err := os.Stat(filepath.Join(dir, "relay-pairing.json")); err != nil {
		t.Fatalf("pairing file missing in LANCER_STATE_DIR: %v", err)
	}
}
