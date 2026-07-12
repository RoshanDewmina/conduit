package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// attachment.put — phone uploads context files into ~/.lancer/attachments/
// for the agent to read from disk (Orca drop-dir pattern). Chunks are ≤256KB
// pre-encryption; the daemon reassembles, writes 0600, returns the host path.

const (
	attachmentMaxBytes      = 20 * 1024 * 1024 // 20 MiB / file
	attachmentMaxFiles      = 5
	attachmentMaxChunkBytes = 256 * 1024
)

type attachmentPutParams struct {
	ConversationID string `json:"conversationId,omitempty"`
	Name           string `json:"name"`
	TotalBytes     int64  `json:"totalBytes"`
	Seq            int    `json:"seq"`
	DataBase64     string `json:"dataBase64"`
	Done           bool   `json:"done"`
}

type attachmentPutResult struct {
	Path string `json:"path,omitempty"`
	OK   bool   `json:"ok,omitempty"`
}

type attachmentUpload struct {
	name       string
	totalBytes int64
	nextSeq    int
	buf        []byte
}

type attachmentUploadHub struct {
	mu      sync.Mutex
	uploads map[string]*attachmentUpload
}

func (s *server) attachmentHub() *attachmentUploadHub {
	s.attachmentsOnce.Do(func() {
		s.attachments = &attachmentUploadHub{uploads: make(map[string]*attachmentUpload)}
	})
	return s.attachments
}

func attachmentUploadKey(conversationID, name string) string {
	return conversationID + "\x00" + name
}

// sanitizeAttachmentName strips directory components and rejects empty / traversal names.
// Returns the cleaned basename, or an error when the name is unusable.
func sanitizeAttachmentName(name string) (string, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return "", fmt.Errorf("attachment name required")
	}
	// Collapse any path: take the last path element after normalizing separators.
	cleaned := strings.ReplaceAll(trimmed, "\\", "/")
	base := filepath.Base(cleaned)
	base = strings.TrimSpace(base)
	if base == "" || base == "." || base == ".." {
		return "", fmt.Errorf("invalid attachment name")
	}
	// filepath.Base already drops parents, but reject residual separators / dots.
	if strings.ContainsAny(base, `/\`) || strings.Contains(base, "..") {
		return "", fmt.Errorf("attachment name contains path separators")
	}
	return base, nil
}

func (s *server) handleAttachmentPut(p attachmentPutParams) (attachmentPutResult, error) {
	sanitized, err := sanitizeAttachmentName(p.Name)
	if err != nil {
		return attachmentPutResult{}, err
	}
	if p.TotalBytes <= 0 {
		return attachmentPutResult{}, fmt.Errorf("totalBytes must be positive")
	}
	if p.TotalBytes > attachmentMaxBytes {
		return attachmentPutResult{}, fmt.Errorf("file exceeds %d byte limit", attachmentMaxBytes)
	}
	if p.Seq < 0 {
		return attachmentPutResult{}, fmt.Errorf("seq must be non-negative")
	}

	raw, err := base64.StdEncoding.DecodeString(p.DataBase64)
	if err != nil {
		return attachmentPutResult{}, fmt.Errorf("invalid dataBase64: %w", err)
	}
	if len(raw) > attachmentMaxChunkBytes {
		return attachmentPutResult{}, fmt.Errorf("chunk exceeds %d byte limit", attachmentMaxChunkBytes)
	}
	// Empty middle chunks are useless; empty final chunk is allowed (done with no trailing bytes).
	if len(raw) == 0 && !p.Done {
		return attachmentPutResult{}, fmt.Errorf("empty chunk")
	}

	hub := s.attachmentHub()
	hub.mu.Lock()
	defer hub.mu.Unlock()

	key := attachmentUploadKey(p.ConversationID, sanitized)
	up, exists := hub.uploads[key]
	if !exists {
		if p.Seq != 0 {
			return attachmentPutResult{}, fmt.Errorf("unexpected seq %d for new upload", p.Seq)
		}
		// Cap concurrent in-flight reassemblies (memory bound); the per-message
		// 5-file rule is enforced client-side per composer send.
		if len(hub.uploads) >= attachmentMaxFiles {
			return attachmentPutResult{}, fmt.Errorf("at most %d concurrent attachment uploads", attachmentMaxFiles)
		}
		capHint := int(p.TotalBytes)
		if capHint > attachmentMaxChunkBytes*2 {
			capHint = attachmentMaxChunkBytes * 2
		}
		up = &attachmentUpload{
			name:       sanitized,
			totalBytes: p.TotalBytes,
			nextSeq:    0,
			buf:        make([]byte, 0, capHint),
		}
		hub.uploads[key] = up
	}

	if up.totalBytes != p.TotalBytes {
		delete(hub.uploads, key)
		return attachmentPutResult{}, fmt.Errorf("totalBytes mismatch")
	}
	if p.Seq != up.nextSeq {
		return attachmentPutResult{}, fmt.Errorf("expected seq %d, got %d", up.nextSeq, p.Seq)
	}
	if int64(len(up.buf))+int64(len(raw)) > attachmentMaxBytes {
		delete(hub.uploads, key)
		return attachmentPutResult{}, fmt.Errorf("file exceeds %d byte limit", attachmentMaxBytes)
	}
	if int64(len(up.buf))+int64(len(raw)) > up.totalBytes {
		delete(hub.uploads, key)
		return attachmentPutResult{}, fmt.Errorf("chunk overflows declared totalBytes")
	}

	up.buf = append(up.buf, raw...)
	up.nextSeq++

	if !p.Done {
		return attachmentPutResult{OK: true}, nil
	}

	if int64(len(up.buf)) != up.totalBytes {
		delete(hub.uploads, key)
		return attachmentPutResult{}, fmt.Errorf("assembled %d bytes, expected %d", len(up.buf), up.totalBytes)
	}

	path, err := writeAttachmentFile(sanitized, up.buf)
	delete(hub.uploads, key)
	if err != nil {
		return attachmentPutResult{}, err
	}
	return attachmentPutResult{Path: path, OK: true}, nil
}

func writeAttachmentFile(sanitizedName string, data []byte) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	day := time.Now().Format("2006-01-02")
	dir := filepath.Join(home, ".lancer", "attachments", day)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	// Tighten dir perms in case umask widened them.
	_ = os.Chmod(dir, 0o700)
	_ = os.Chmod(filepath.Join(home, ".lancer"), 0o700)
	_ = os.Chmod(filepath.Join(home, ".lancer", "attachments"), 0o700)

	filename := newUUID() + "-" + sanitizedName
	path := filepath.Join(dir, filename)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return "", err
	}
	_ = os.Chmod(path, 0o600)
	return path, nil
}
