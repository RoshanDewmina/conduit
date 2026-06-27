package main

import (
	"os"
	"path/filepath"
)

const (
	socketFileName = "lancerd.sock"
	queueFileName  = "queue.json"
)

// lancerDir returns ~/.lancer (or LANCER_STATE_DIR for tests).
func lancerDir() (string, error) {
	if dir := os.Getenv("LANCER_STATE_DIR"); dir != "" {
		if err := os.MkdirAll(dir, 0700); err != nil {
			return "", err
		}
		return dir, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, ".lancer")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	return dir, nil
}

func socketPath() (string, error) {
	dir, err := lancerDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, socketFileName), nil
}

func queuePath() (string, error) {
	dir, err := lancerDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, queueFileName), nil
}
