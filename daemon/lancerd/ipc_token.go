package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
)

// IPCProtocolVersion is the control-channel protocol version this daemon
// build speaks. A control client's hello.params.protocolVersion must match
// exactly or the daemon rejects the handshake (-32002).
const IPCProtocolVersion = 1

const ipcTokenFileName = "ipc-token"

// ipcTokenPath returns ~/.lancer/ipc-token (or LANCER_STATE_DIR for tests).
func ipcTokenPath() (string, error) {
	dir, err := lancerDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, ipcTokenFileName), nil
}

// ensureIPCToken generates ~/.lancer/ipc-token (32 random bytes, hex-encoded,
// mode 0600) if it does not already exist, then returns its contents. Called
// once at daemon startup so the control channel always has a token to check
// against without requiring a separate provisioning step.
func ensureIPCToken() (string, error) {
	path, err := ipcTokenPath()
	if err != nil {
		return "", err
	}
	if data, err := os.ReadFile(path); err == nil {
		return string(data), nil
	} else if !os.IsNotExist(err) {
		return "", err
	}

	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", fmt.Errorf("generate ipc token: %w", err)
	}
	token := hex.EncodeToString(raw[:])
	if err := os.WriteFile(path, []byte(token), 0600); err != nil {
		return "", fmt.Errorf("write ipc token: %w", err)
	}
	return token, nil
}

// readIPCToken reads the on-disk token without generating one. Used by the
// control handler on every connection so a token rotated/removed on disk
// takes effect without a daemon restart.
func readIPCToken() (string, error) {
	path, err := ipcTokenPath()
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
