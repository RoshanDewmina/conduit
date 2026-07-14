package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"syscall"
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
	return readRelayPairingAt(path)
}

func readRelayPairingAt(path string) (*relayPairConfig, error) {
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

func withRelayPairingLock(fn func(path string) error) error {
	path, err := relayPairingPath()
	if err != nil {
		return err
	}
	lock, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	return fn(path)
}

func writeRelayPairingAtomic(path string, cfg *relayPairConfig) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".relay-pairing-write-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if err := tmp.Chmod(0600); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
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
	return withRelayPairingLock(func(path string) error {
		candidate := *cfg
		old, readErr := readRelayPairingAt(path)
		if readErr != nil && !os.IsNotExist(readErr) && !replaceConfirmed {
			return fmt.Errorf("refusing to overwrite unreadable relay pairing: %w", readErr)
		}
		if readErr == nil {
			// The daemon has one pairing slot. Confirmed identities are durable
			// unless this is an explicit onboarding/re-pair path.
			if old.isConfirmed() && pairingIdentityChanged(old, &candidate) && !replaceConfirmed {
				return fmt.Errorf("refusing to replace confirmed pairing; run 'lancerd pair' (explicit re-pair) or unpair first")
			}
			if old.Code != candidate.Code {
				fmt.Fprintln(os.Stderr, "lancerd: REPLACING existing relay pairing identity — phones on the previous identity are orphaned and must re-pair")
			}
			if pairingIdentityChanged(old, &candidate) {
				candidate.ConfirmedAt = ""
			} else if old.isConfirmed() && candidate.ConfirmedAt == "" {
				// Confirmation is monotonic for an unchanged identity. A stale
				// caller must not silently downgrade an established pairing.
				candidate.ConfirmedAt = old.ConfirmedAt
			}
		}
		if err := writeRelayPairingAtomic(path, &candidate); err != nil {
			return err
		}
		*cfg = candidate
		return nil
	})
}

// migrateRetiredHostedRelay performs the one allowed endpoint-only identity
// migration. It preserves the pairing code, both keys, and ConfirmedAt while
// atomically replacing only the exact retired first-party URL. Custom and
// lookalike endpoints are never rewritten.
func migrateRetiredHostedRelay(cfg *relayPairConfig) (bool, error) {
	if cfg == nil {
		return false, nil
	}
	migrated := false
	err := withRelayPairingLock(func(path string) error {
		current, err := readRelayPairingAt(path)
		if err != nil {
			return err
		}
		if current.RelayURL != retiredHostedRelayURL {
			*cfg = *current
			return nil
		}
		current.RelayURL = defaultRelayURL
		// A persisted first-party legacy identity may predate ConfirmedAt. Treat
		// it conservatively as established so backend state loss can never
		// trigger an automatic code/key rotation that orphans its phone.
		if current.ConfirmedAt == "" {
			current.ConfirmedAt = time.Now().UTC().Format(time.RFC3339)
		}
		if err := writeRelayPairingAtomic(path, current); err != nil {
			return err
		}
		*cfg = *current
		migrated = true
		return nil
	})
	return migrated, err
}

// markRelayPairingConfirmed stamps ConfirmedAt on the current pairing file
// when the live client observes peer_joined. Identity (code/keys/URL) is
// unchanged so the relayPairWatcher must NOT bounce the client on this write
// (see identityHash below).
func markRelayPairingConfirmed(expected *relayPairConfig) (bool, error) {
	if expected == nil {
		return false, nil
	}
	marked := false
	err := withRelayPairingLock(func(path string) error {
		current, err := readRelayPairingAt(path)
		if err != nil {
			return err
		}
		if pairingIdentityHash(current) != pairingIdentityHash(expected) || current.isConfirmed() {
			return nil
		}
		current.ConfirmedAt = time.Now().UTC().Format(time.RFC3339)
		if err := writeRelayPairingAtomic(path, current); err != nil {
			return err
		}
		marked = true
		return nil
	})
	return marked, err
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
