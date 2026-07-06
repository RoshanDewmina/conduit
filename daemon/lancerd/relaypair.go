package main

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// ErrRelayPairingOccupied is returned when a new pairing would replace an
// existing, different relay pairing. Callers that intentionally replace must
// pass allowReplace=true (CLI --force, RPC force flag).
var ErrRelayPairingOccupied = errors.New("relay pairing already configured")

type relayPairConfig struct {
	RelayURL   string `json:"relayURL"`
	Code       string `json:"code"`
	PrivateKey string `json:"privateKey"` // base64url-encoded X25519 private key
	PublicKey  string `json:"publicKey"`  // base64url-encoded X25519 public key
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

func writeRelayPairing(cfg *relayPairConfig) error {
	return writeRelayPairingAllowReplace(cfg, false)
}

func replaceRelayPairing(cfg *relayPairConfig) error {
	return writeRelayPairingAllowReplace(cfg, true)
}

func writeRelayPairingAllowReplace(cfg *relayPairConfig, allowReplace bool) error {
	path, err := relayPairingPath()
	if err != nil {
		return err
	}
	// The daemon has exactly ONE pairing slot: every phone paired to the old
	// code is orphaned the moment this file changes (the resident's watcher
	// hot-swaps the live relay client within ~5s). Refuse silent overwrites so
	// operators must explicitly force a replace (and see the orphan warning).
	if old, err := readRelayPairing(); err == nil && !sameRelayPairing(old, cfg) {
		if !allowReplace {
			fmt.Fprintf(os.Stderr,
				"lancerd: REFUSING to replace existing relay pairing (code %s) — phones paired to the old code would be orphaned; delete %s or pass --force to replace\n",
				old.Code, path)
			return fmt.Errorf("%w (existing code %s)", ErrRelayPairingOccupied, old.Code)
		}
		fmt.Fprintf(os.Stderr,
			"lancerd: REPLACING existing relay pairing (code %s -> %s) — phones paired to the old code are orphaned and must re-pair\n",
			old.Code, cfg.Code)
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func sameRelayPairing(a, b *relayPairConfig) bool {
	return a.RelayURL == b.RelayURL &&
		a.Code == b.Code &&
		a.PrivateKey == b.PrivateKey &&
		a.PublicKey == b.PublicKey
}

type relayPairWatcher struct {
	mu       sync.Mutex
	path     string
	lastHash [32]byte
	onChange func(cfg *relayPairConfig)
	stopCh   chan struct{}
}

func newRelayPairWatcher(onChange func(cfg *relayPairConfig)) *relayPairWatcher {
	path, _ := relayPairingPath()
	return &relayPairWatcher{
		path:     path,
		onChange: onChange,
		stopCh:   make(chan struct{}),
	}
}

func (w *relayPairWatcher) start() {
	go w.pollLoop()
}

func (w *relayPairWatcher) stop() {
	close(w.stopCh)
}

func (w *relayPairWatcher) pollLoop() {
	w.updateHash()
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

func (w *relayPairWatcher) updateHash() {
	data, err := os.ReadFile(w.path)
	if err != nil {
		return
	}
	w.mu.Lock()
	w.lastHash = sha256.Sum256(data)
	w.mu.Unlock()
}

func (w *relayPairWatcher) checkAndNotify() {
	data, err := os.ReadFile(w.path)
	if err != nil {
		return
	}
	hash := sha256.Sum256(data)
	w.mu.Lock()
	changed := hash != w.lastHash
	if changed {
		w.lastHash = hash
	}
	w.mu.Unlock()
	if !changed {
		return
	}
	var cfg relayPairConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return
	}
	if cfg.RelayURL == "" || cfg.Code == "" || cfg.PrivateKey == "" || cfg.PublicKey == "" {
		return
	}
	if w.onChange != nil {
		w.onChange(&cfg)
	}
}
