package main

import (
	"os"
	"path/filepath"
)

const (
	socketFileName = "conduitd.sock"
	queueFileName  = "queue.json"
)

// conduitDir returns ~/.conduit (or CONDUIT_STATE_DIR for tests).
func conduitDir() (string, error) {
	if dir := os.Getenv("CONDUIT_STATE_DIR"); dir != "" {
		if err := os.MkdirAll(dir, 0700); err != nil {
			return "", err
		}
		return dir, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, ".conduit")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	return dir, nil
}

func socketPath() (string, error) {
	dir, err := conduitDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, socketFileName), nil
}

func queuePath() (string, error) {
	dir, err := conduitDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, queueFileName), nil
}
