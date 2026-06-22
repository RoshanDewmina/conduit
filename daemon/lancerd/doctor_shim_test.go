package main

import (
	"errors"
	"path/filepath"
	"testing"
)

func TestCheckShimWrapper_NotInstalled(t *testing.T) {
	look := func(string) (string, error) { return "", errors.New("not found") }
	r := checkShimWrapper(t.TempDir(), look)
	if r.status != statusFail {
		t.Fatalf("status = %v, want statusFail when claude absent", r.status)
	}
}

func TestCheckShimWrapper_OK(t *testing.T) {
	home := t.TempDir()
	binDir := filepath.Join(home, ".lancer", "bin")
	look := func(string) (string, error) { return filepath.Join(binDir, "claude"), nil }
	r := checkShimWrapper(home, look)
	if r.status != statusOK {
		t.Fatalf("status = %v, want statusOK", r.status)
	}
}
