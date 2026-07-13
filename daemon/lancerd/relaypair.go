package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type relayPairConfig struct {
	RelayURL   string `json:"relayURL"`
	Code       string `json:"code"`
	PrivateKey string `json:"privateKey"` // base64url-encoded X25519 private key
	PublicKey  string `json:"publicKey"`  // base64url-encoded X25519 public key
	// ConfirmedAt is set once the first peer_joined completes for this
	// code+keypair (RFC3339 UTC). It is the durable daemon-side proxy for
	// the relay's in-memory PairedAt: survives LaunchAgent restart, binary
	// replace, and laptop reboot. Empty means the code has never completed
	// an exchange and is still eligible for REL-1 auto-remint on expiry.
	ConfirmedAt string `json:"confirmedAt,omitempty"`
}

func relayPairingPath() (string, error) {
	dir, err := lancerDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "relay-pairing.json"), nil
}

func readRelayPairing() (*relayPairConfig, error) {
	path, err := relayPairingPath()
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg relayPairConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	if cfg.RelayURL == "" || cfg.Code == "" || cfg.PrivateKey == "" || cfg.PublicKey == "" {
		return nil, fmt.Errorf("incomplete relay pairing config")
	}
	return &cfg, nil
}

func pairingIdentityChanged(old, cfg *relayPairConfig) bool {
	return old.RelayURL != cfg.RelayURL ||
		old.Code != cfg.Code ||
		old.PrivateKey != cfg.PrivateKey ||
		old.PublicKey != cfg.PublicKey
}

func (c *relayPairConfig) isConfirmed() bool {
	return c != nil && c.ConfirmedAt != ""
}

// writeRelayPairing persists cfg. Refuses to replace a *confirmed* pairing's
// identity (code/keys/URL) — that is what orphaned live phones when tests or
// accidental remints rewrote ~/.lancer/relay-pairing.json. Explicit onboarding
// re-pair must call writeRelayPairingReplacing instead.
func writeRelayPairing(cfg *relayPairConfig) error {
	return writeRelayPairingWithReplace(cfg, false)
}

// writeRelayPairingReplacing is the intentional onboarding / `lancerd pair` /
// agent.pair.begin path: it may orphan phones on the previous code, and logs
// that loudly.
func writeRelayPairingReplacing(cfg *relayPairConfig) error {
	return writeRelayPairingWithReplace(cfg, true)
}

func writeRelayPairingWithReplace(cfg *relayPairConfig, replaceConfirmed bool) error {
	path, err := relayPairingPath()
	if err != nil {
		return err
	}
	// The daemon has exactly ONE pairing slot: every phone paired to the old
	// code is silently orphaned the moment this file's identity changes (the
	// resident's watcher hot-swaps the live relay client within ~5s, and the
	// old phones keep dialing a code no daemon listens on). Confirmed
	// pairings are durable one-time onboarding — refuse silent overwrite
	// unless the caller opted into replaceConfirmed (explicit pair/unpair).
	if old, err := readRelayPairing(); err == nil {
		if old.isConfirmed() && pairingIdentityChanged(old, cfg) && !replaceConfirmed {
			return fmt.Errorf(
				"refusing to replace confirmed pairing (code %s); run 'lancerd pair' (explicit re-pair) or unpair first",
				old.Code,
			)
		}
		if old.Code != cfg.Code {
			fmt.Fprintf(os.Stderr,
				"lancerd: REPLACING existing relay pairing (code %s -> %s) — phones paired to the old code are orphaned and must re-pair\n",
				old.Code, cfg.Code)
		}
	}
	// A new identity always starts unconfirmed, even if the caller copied a
	// stamped struct.
	if old, err := readRelayPairing(); err == nil && pairingIdentityChanged(old, cfg) {
		cfg.ConfirmedAt = ""
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

// markRelayPairingConfirmed stamps ConfirmedAt on the current pairing file
// when the live client observes peer_joined. Identity (code/keys/URL) is
// unchanged so the relayPairWatcher must NOT bounce the client on this write
// (see identityHash below).
func markRelayPairingConfirmed(code string) {
	cfg, err := readRelayPairing()
	if err != nil {
		return
	}
	if cfg.Code != code {
		// File changed under us (explicit re-pair) — do not stamp the new code.
		return
	}
	if cfg.isConfirmed() {
		return
	}
	cfg.ConfirmedAt = time.Now().UTC().Format(time.RFC3339)
	if err := writeRelayPairing(cfg); err != nil {
		fmt.Fprintf(os.Stderr, "lancerd: warning: failed to persist pairing confirmation: %v\n", err)
	}
}

type relayPairWatcher struct {
	mu           sync.Mutex
	path         string
	lastIdentity [32]byte
	onChange     func(cfg *relayPairConfig)
	stopCh       chan struct{}
}

func newRelayPairWatcher(onChange func(cfg *relayPairConfig)) *relayPairWatcher {
	path, _ := relayPairingPath()
	return &relayPairWatcher{
		path:     path,
		onChange: onChange,
		stopCh:   make(chan struct{}),
	}
}

func pairingIdentityHash(cfg *relayPairConfig) [32]byte {
	// ConfirmedAt stamps must not count as an identity change — otherwise
	// markRelayPairingConfirmed would stop+restart the live client.
	sum := sha256.Sum256([]byte(
		cfg.RelayURL + "\x00" + cfg.Code + "\x00" + cfg.PrivateKey + "\x00" + cfg.PublicKey,
	))
	return sum
}

func (w *relayPairWatcher) start() {
	go w.pollLoop()
}

func (w *relayPairWatcher) stop() {
	close(w.stopCh)
}

func (w *relayPairWatcher) pollLoop() {
	w.updateIdentity()
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-w.stopCh:
			return
		case <-ticker.C:
			w.checkAndNotify()
		}
	}
}

func (w *relayPairWatcher) updateIdentity() {
	data, err := os.ReadFile(w.path)
	if err != nil {
		return
	}
	var cfg relayPairConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return
	}
	w.mu.Lock()
	w.lastIdentity = pairingIdentityHash(&cfg)
	w.mu.Unlock()
}

func (w *relayPairWatcher) checkAndNotify() {
	data, err := os.ReadFile(w.path)
	if err != nil {
		return
	}
	var cfg relayPairConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return
	}
	if cfg.RelayURL == "" || cfg.Code == "" || cfg.PrivateKey == "" || cfg.PublicKey == "" {
		return
	}
	hash := pairingIdentityHash(&cfg)
	w.mu.Lock()
	changed := hash != w.lastIdentity
	if changed {
		w.lastIdentity = hash
	}
	w.mu.Unlock()
	if !changed {
		return
	}
	if w.onChange != nil {
		w.onChange(&cfg)
	}
}
