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
	path, err := relayPairingPath()
	if err != nil {
		return err
	}
	// The daemon has exactly ONE pairing slot: every phone paired to the old
	// code is silently orphaned the moment this file changes (the resident's
	// watcher hot-swaps the live relay client within ~5s, and the old phones
	// keep dialing a code no daemon listens on, forever, with no error on
	// either side — root cause of the 2026-07-04 "phone never re-paired after
	// daemon restart" incident). Warn loudly whenever an existing, different
	// pairing is being replaced so the operator knows a re-pair of every
	// phone is now required.
	if old, err := readRelayPairing(); err == nil && old.Code != cfg.Code {
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
