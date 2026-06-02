package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

func dataFilePath(envKey, defaultName string) string {
	if v := os.Getenv(envKey); v != "" {
		return v
	}
	if dir := os.Getenv("DATA_DIR"); dir != "" {
		return filepath.Join(dir, defaultName)
	}
	return filepath.Join(os.TempDir(), defaultName)
}

func loadJSONFile(path string, dest any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if len(data) == 0 {
		return nil
	}
	return json.Unmarshal(data, dest)
}

func saveJSONFile(path string, src any) error {
	data, err := json.MarshalIndent(src, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

type jsonFileStore struct {
	mu   sync.Mutex
	path string
}

func (s *jsonFileStore) load(dest any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return loadJSONFile(s.path, dest)
}

func (s *jsonFileStore) save(src any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return saveJSONFile(s.path, src)
}

func (s *jsonFileStore) update(mutate func() error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return mutate()
}
