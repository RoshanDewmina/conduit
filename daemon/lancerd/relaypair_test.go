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

	seed := &relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "444444",
		PrivateKey: "priv-d",
		PublicKey:  "pub-d",
	}
	if err := writeRelayPairing(seed); err != nil {
		t.Fatalf("seed: %v", err)
	}

	marked, err := markRelayPairingConfirmed(seed)
	if err != nil {
		t.Fatalf("mark: %v", err)
	}
	if !marked {
		t.Fatal("matching pairing was not marked confirmed")
	}

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

	mismatch := &relayPairConfig{
		RelayURL:   "wss://relay.example.com",
		Code:       "999999",
		PrivateKey: "priv-e",
		PublicKey:  "pub-e",
	}
	marked, err := markRelayPairingConfirmed(mismatch)
	if err != nil {
		t.Fatalf("mark mismatch: %v", err)
	}
	if marked {
		t.Fatal("mismatched identity was marked confirmed")
	}

	cfg, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if cfg.isConfirmed() {
		t.Fatal("stamped ConfirmedAt for a mismatched code")
	}
}

func TestMarkRelayPairingConfirmedDoesNotOverwriteExplicitRepair(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)

	stale := &relayPairConfig{
		RelayURL: "wss://relay.example.com", Code: "121212", PrivateKey: "priv-old", PublicKey: "pub-old",
	}
	if err := writeRelayPairing(stale); err != nil {
		t.Fatalf("seed stale identity: %v", err)
	}
	replacement := &relayPairConfig{
		RelayURL: "wss://relay.example.com", Code: "343434", PrivateKey: "priv-new", PublicKey: "pub-new",
	}
	if err := writeRelayPairingReplacing(replacement); err != nil {
		t.Fatalf("explicit repair: %v", err)
	}

	marked, err := markRelayPairingConfirmed(stale)
	if err != nil {
		t.Fatalf("stale confirm: %v", err)
	}
	if marked {
		t.Fatal("stale client marked replacement identity confirmed")
	}
	got, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read replacement: %v", err)
	}
	if pairingIdentityHash(got) != pairingIdentityHash(replacement) || got.isConfirmed() {
		t.Fatalf("stale confirm mutated replacement: %+v", got)
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

func TestWriteRelayPairingPreservesConfirmationForSameIdentity(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)
	confirmedAt := time.Now().UTC().Format(time.RFC3339)
	seed := &relayPairConfig{
		RelayURL: "wss://relay.example.com", Code: "676767", PrivateKey: "priv-same", PublicKey: "pub-same",
		ConfirmedAt: confirmedAt,
	}
	if err := writeRelayPairing(seed); err != nil {
		t.Fatalf("seed confirmed pairing: %v", err)
	}
	stale := &relayPairConfig{
		RelayURL: seed.RelayURL, Code: seed.Code, PrivateKey: seed.PrivateKey, PublicKey: seed.PublicKey,
	}
	if err := writeRelayPairing(stale); err != nil {
		t.Fatalf("rewrite same identity: %v", err)
	}
	got, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read pairing: %v", err)
	}
	if got.ConfirmedAt != confirmedAt {
		t.Fatalf("confirmation downgraded to %q, want %q", got.ConfirmedAt, confirmedAt)
	}
}

func TestMigrateRetiredHostedRelayPreservesConfirmedIdentity(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)
	confirmedAt := time.Now().UTC().Format(time.RFC3339)
	seed := &relayPairConfig{
		RelayURL: retiredHostedRelayURL,
		Code:     "777777", PrivateKey: "priv-g", PublicKey: "pub-g",
		ConfirmedAt: confirmedAt,
	}
	if err := writeRelayPairing(seed); err != nil {
		t.Fatalf("seed retired pairing: %v", err)
	}

	migrated, err := migrateRetiredHostedRelay(seed)
	if err != nil {
		t.Fatalf("migrateRetiredHostedRelay: %v", err)
	}
	if !migrated {
		t.Fatal("retired hosted endpoint was not migrated")
	}

	got, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read migrated pairing: %v", err)
	}
	if got.RelayURL != defaultRelayURL {
		t.Fatalf("RelayURL = %q, want %q", got.RelayURL, defaultRelayURL)
	}
	if got.Code != seed.Code || got.PrivateKey != seed.PrivateKey || got.PublicKey != seed.PublicKey || got.ConfirmedAt != confirmedAt {
		t.Fatalf("migration changed pairing identity or confirmation: %+v", got)
	}
	info, err := os.Stat(filepath.Join(dir, "relay-pairing.json"))
	if err != nil {
		t.Fatalf("stat migrated pairing: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %o, want 600", info.Mode().Perm())
	}
}

func TestMigrateRetiredHostedRelayBackfillsLegacyConfirmation(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("LANCER_STATE_DIR", dir)
	seed := &relayPairConfig{
		RelayURL: retiredHostedRelayURL,
		Code:     "787878", PrivateKey: "priv-legacy", PublicKey: "pub-legacy",
	}
	if err := writeRelayPairing(seed); err != nil {
		t.Fatalf("seed legacy pairing: %v", err)
	}

	migrated, err := migrateRetiredHostedRelay(seed)
	if err != nil {
		t.Fatalf("migrate legacy pairing: %v", err)
	}
	if !migrated {
		t.Fatal("legacy first-party pairing was not migrated")
	}
	got, err := readRelayPairing()
	if err != nil {
		t.Fatalf("read migrated legacy pairing: %v", err)
	}
	if got.RelayURL != defaultRelayURL || !got.isConfirmed() {
		t.Fatalf("legacy pairing was not migrated and backfilled: %+v", got)
	}
	if got.Code != seed.Code || got.PrivateKey != seed.PrivateKey || got.PublicKey != seed.PublicKey {
		t.Fatalf("legacy migration changed identity: %+v", got)
	}
}

func TestMigrateRetiredHostedRelayLeavesOtherEndpointsUnchanged(t *testing.T) {
	for _, relayURL := range []string{
		defaultRelayURL,
		"wss://self-host.example.com",
		retiredHostedRelayURL + ".attacker.example",
	} {
		t.Run(relayURL, func(t *testing.T) {
			dir := t.TempDir()
			t.Setenv("LANCER_STATE_DIR", dir)
			cfg := &relayPairConfig{
				RelayURL: relayURL,
				Code:     "888888", PrivateKey: "priv-h", PublicKey: "pub-h",
			}
			if err := writeRelayPairing(cfg); err != nil {
				t.Fatalf("seed pairing: %v", err)
			}
			migrated, err := migrateRetiredHostedRelay(cfg)
			if err != nil {
				t.Fatalf("migrate: %v", err)
			}
			if migrated {
				t.Fatalf("unexpected migration for %q", relayURL)
			}
			got, err := readRelayPairing()
			if err != nil {
				t.Fatalf("read: %v", err)
			}
			if got.RelayURL != relayURL {
				t.Fatalf("RelayURL changed to %q", got.RelayURL)
			}
		})
	}
}
