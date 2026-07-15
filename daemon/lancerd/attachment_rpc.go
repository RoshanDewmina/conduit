package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// attachment.put — phone uploads context files into ~/.lancer/attachments/
// for the agent to read from disk (Orca drop-dir pattern). Chunks are ≤256KB
// pre-encryption; the daemon reassembles, content-addresses by SHA-256, writes
// an immutable object + durable receipt, and returns opaque id + path +
// lowercase hex contentDigest. Append must look up the receipt — it cannot
// invent an id/path.

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

// attachmentPutResult is the wire result for a finalized put (and ok-only
// middle chunks). Field naming locked camelCase for the phone contract.
type attachmentPutResult struct {
	ID            string `json:"id,omitempty"`
	Path          string `json:"path,omitempty"`
	ContentDigest string `json:"contentDigest,omitempty"`
	OK            bool   `json:"ok,omitempty"`
}

// attachmentReceipt is the durable server-side identity for one put. Stored
// under <attachmentRoot>/receipts/<id>.json. Append/dispatch look up by id —
// client hostPath is never sole authority.
type attachmentReceipt struct {
	ID            string `json:"id"`
	ContentDigest string `json:"contentDigest"`
	ByteCount     int64  `json:"byteCount"`
	Name          string `json:"name"`
	RelPath       string `json:"relPath"` // relative to attachment root (objects/<digest>)
	CreatedAt     string `json:"createdAt"`
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
	if exists && p.Seq == 0 {
		// Client aborted mid-upload and is retrying from scratch — replace.
		exists = false
		delete(hub.uploads, key)
	}
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

	id, path, digest, err := writeAttachmentObject(sanitized, up.buf)
	delete(hub.uploads, key)
	if err != nil {
		return attachmentPutResult{}, err
	}
	return attachmentPutResult{
		ID:            id,
		Path:          path,
		ContentDigest: digest,
		OK:            true,
	}, nil
}

// writeAttachmentObject content-addresses data under the attachment root,
// writes a durable receipt, and returns the opaque id, absolute object path,
// and lowercase hex SHA-256 digest. Same bytes → same object path (idempotent
// content store); each successful put still mints a fresh receipt id so
// append binds to a server-issued identity.
func writeAttachmentObject(sanitizedName string, data []byte) (id, absPath, digest string, err error) {
	sum := sha256.Sum256(data)
	digest = hex.EncodeToString(sum[:])

	root, err := ensureAttachmentRoot()
	if err != nil {
		return "", "", "", err
	}

	relPath := filepath.Join("objects", digest)
	absPath = filepath.Join(root, relPath)
	objDir := filepath.Dir(absPath)
	if err := os.MkdirAll(objDir, 0o700); err != nil {
		return "", "", "", err
	}
	_ = os.Chmod(objDir, 0o700)

	// Idempotent content store: reuse only when the on-disk object hashes to
	// the same digest. Same-size different bytes are a conflict (fail closed).
	if fi, statErr := os.Lstat(absPath); statErr == nil {
		if !fi.Mode().IsRegular() {
			return "", "", "", fmt.Errorf("attachment object conflict")
		}
		existingDigest, _, herr := hashAttachmentFileNoFollow(absPath)
		if herr != nil || existingDigest != digest {
			return "", "", "", fmt.Errorf("attachment object conflict")
		}
	} else if !os.IsNotExist(statErr) {
		return "", "", "", statErr
	} else {
		tmp, tmpErr := os.CreateTemp(objDir, "att-*.tmp")
		if tmpErr != nil {
			return "", "", "", tmpErr
		}
		tmpName := tmp.Name()
		if _, werr := tmp.Write(data); werr != nil {
			_ = tmp.Close()
			_ = os.Remove(tmpName)
			return "", "", "", werr
		}
		if cerr := tmp.Close(); cerr != nil {
			_ = os.Remove(tmpName)
			return "", "", "", cerr
		}
		// Content-addressed object: owner-read-only to reduce same-length
		// replacement TOCTOU between verify and vendor reopen-by-path.
		_ = os.Chmod(tmpName, 0o400)
		if rerr := os.Rename(tmpName, absPath); rerr != nil {
			_ = os.Remove(tmpName)
			return "", "", "", rerr
		}
		_ = os.Chmod(absPath, 0o400)
	}

	id = newUUID()
	receipt := attachmentReceipt{
		ID:            id,
		ContentDigest: digest,
		ByteCount:     int64(len(data)),
		Name:          sanitizedName,
		RelPath:       filepath.ToSlash(relPath),
		CreatedAt:     time.Now().UTC().Format(time.RFC3339),
	}
	if err := writeAttachmentReceipt(root, receipt); err != nil {
		return "", "", "", err
	}
	return id, absPath, digest, nil
}

func writeAttachmentReceipt(root string, receipt attachmentReceipt) error {
	dir := filepath.Join(root, "receipts")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	_ = os.Chmod(dir, 0o700)
	raw, err := json.Marshal(receipt)
	if err != nil {
		return err
	}
	id := strings.TrimSpace(receipt.ID)
	if id == "" || strings.ContainsAny(id, `/\`) || strings.Contains(id, "..") {
		return fmt.Errorf("invalid attachment receipt id")
	}
	path := filepath.Join(dir, id+".json")

	// Crash-safe exclusive create: write the full receipt to a temp file, then
	// link into place. Link fails with EEXIST on UUID collision / ref replay so
	// an existing receipt is never overwritten (unlike Rename). Permissions 0600.
	tmp, err := os.CreateTemp(dir, "receipt-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(raw); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return err
	}
	_ = os.Chmod(tmpName, 0o600)
	if err := os.Link(tmpName, path); err != nil {
		_ = os.Remove(tmpName)
		if os.IsExist(err) {
			return fmt.Errorf("attachment receipt id collision")
		}
		// Fallback for filesystems where Link is unsupported: O_CREATE|O_EXCL.
		f, oerr := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if oerr != nil {
			if os.IsExist(oerr) {
				return fmt.Errorf("attachment receipt id collision")
			}
			return err
		}
		if _, werr := f.Write(raw); werr != nil {
			_ = f.Close()
			_ = os.Remove(path)
			return werr
		}
		if cerr := f.Close(); cerr != nil {
			_ = os.Remove(path)
			return cerr
		}
		_ = os.Chmod(path, 0o600)
		return nil
	}
	_ = os.Remove(tmpName)
	_ = os.Chmod(path, 0o600)
	return nil
}

func loadAttachmentReceipt(root, id string) (attachmentReceipt, error) {
	id = strings.TrimSpace(id)
	if id == "" || strings.ContainsAny(id, `/\`) || strings.Contains(id, "..") {
		return attachmentReceipt{}, fmt.Errorf("attachment receipt not found")
	}
	raw, err := os.ReadFile(filepath.Join(root, "receipts", id+".json"))
	if err != nil {
		if os.IsNotExist(err) {
			return attachmentReceipt{}, fmt.Errorf("attachment receipt not found")
		}
		return attachmentReceipt{}, fmt.Errorf("attachment receipt not found")
	}
	var receipt attachmentReceipt
	if err := json.Unmarshal(raw, &receipt); err != nil {
		return attachmentReceipt{}, fmt.Errorf("attachment receipt not found")
	}
	if receipt.ID != id || !isValidContentDigest(receipt.ContentDigest) || receipt.RelPath == "" {
		return attachmentReceipt{}, fmt.Errorf("attachment receipt not found")
	}
	return receipt, nil
}

// ensureAttachmentRoot returns the absolute, symlink-evaluated attachment
// root (~/.lancer/attachments), creating it with 0700 if needed.
func ensureAttachmentRoot() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	_ = os.MkdirAll(filepath.Join(home, ".lancer"), 0o700)
	_ = os.Chmod(filepath.Join(home, ".lancer"), 0o700)
	root := filepath.Join(home, ".lancer", "attachments")
	if err := os.MkdirAll(root, 0o700); err != nil {
		return "", err
	}
	_ = os.Chmod(root, 0o700)
	abs, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if err != nil {
		// Root may be brand-new with no intermediate symlinks; Abs is enough.
		if os.IsNotExist(err) {
			return abs, nil
		}
		return "", err
	}
	return resolved, nil
}
