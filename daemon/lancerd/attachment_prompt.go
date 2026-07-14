package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"unicode"
)

// attachment_prompt.go — secure attachment launch boundary for conversation
// append. Ledger / user-visible prompt stays exact as typed; only the
// ephemeral Claude vendor prompt carries a JSON attachment manifest with
// canonical host paths after server-side receipt + content verification.
//
// Security invariants:
//   - Persisted Prompt, titles, audit Command, run.Prompt, and phone-facing
//     error Message never include hostPath.
//   - Policy ContentHash binds clean-prompt argv + attachmentIdentityDigest
//     (server-issued id + contentDigest + safe metadata, count/order
//     deterministic) — not mutable path text — via computeContentHash's
//     toolInput field.
//   - Launch resolves receipt by opaque id; client hostPath is never sole
//     authority. Canonical path must sit inside the attachment root
//     (Abs+EvalSymlinks+filepath.Rel segment-safe). Re-hash immediately
//     before launch; same-length byte replacement fails.
//   - Vendor framing is a fixed header/footer wrapping json.Marshal output —
//     metadata/content are untrusted data, never line-oriented interpolation.
//   - Path manifest is Claude Code only; other agents fail closed path-free.
//   - Emitted tool/artifact/liveStatus/run.output/question.raw JSON redacts
//     verified attachment absolute paths (bounded placeholders) before
//     relay/ledger/receipt — never a global filesystem scrub.
//
// Residual TOCTOU (documented): Claude Code reopens files by path from the
// manifest after our verify. Objects are content-addressed + chmod 0400 to
// make same-length replacement impractical for the daemon user; a privileged
// attacker who can rewrite the object between verify and vendor open remains
// out of scope for this boundary.

const (
	attachmentVendorSectionHeader = "<<<LANCER_ATTACHMENTS>>>"
	attachmentVendorSectionFooter = "<<<END_LANCER_ATTACHMENTS>>>"
)

// resolvedAttachment is the post-validation launch view: canonical path under
// the attachment root plus the safe metadata echoed into the JSON manifest.
type resolvedAttachment struct {
	ID            string
	Name          string
	Kind          string
	MimeType      string
	ByteCount     int
	ContentDigest string
	HostPath      string // absolute canonical path inside attachment root
}

// vendorAttachmentManifest is the internal JSON block Claude receives. Fields
// are data, not instructions — json.Marshal escapes control characters.
type vendorAttachmentManifest struct {
	Attachments []vendorAttachmentManifestEntry `json:"attachments"`
}

type vendorAttachmentManifestEntry struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Kind          string `json:"kind"`
	MimeType      string `json:"mimeType,omitempty"`
	ByteCount     int    `json:"byteCount"`
	ContentDigest string `json:"contentDigest"`
	HostPath      string `json:"hostPath"`
}

// isValidContentDigest reports whether s is a lowercase hex SHA-256 digest.
func isValidContentDigest(s string) bool {
	if len(s) != 64 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

// attachmentIdentityDigest returns a deterministic hex SHA-256 over attachment
// identity for ContentHash binding: count and order matter; each entry binds
// server-issued id + contentDigest + safe metadata (name/kind/mime/byteCount).
// hostPath and previewCacheKey are excluded so mutable transport paths cannot
// forge or invalidate a governed decision. Empty/nil attachments yield "".
func attachmentIdentityDigest(atts []conversationAttachmentReference) string {
	if len(atts) == 0 {
		return ""
	}
	parts := make([]string, 0, len(atts)*6)
	for _, a := range atts {
		parts = append(parts,
			a.ID,
			a.ContentDigest,
			a.Name,
			a.Kind,
			a.MimeType,
			fmt.Sprintf("%d", a.ByteCount),
		)
	}
	sum := sha256.Sum256([]byte(strings.Join(parts, "\x1f")))
	return hex.EncodeToString(sum[:])
}

// pathHasControlOrDelimiter reports whether s contains characters that must
// never appear in a hostPath used inside the vendor manifest (NUL/controls,
// newlines, or framing delimiter substrings).
func pathHasControlOrDelimiter(s string) bool {
	if s == "" {
		return true
	}
	if strings.Contains(s, attachmentVendorSectionHeader) || strings.Contains(s, attachmentVendorSectionFooter) {
		return true
	}
	for _, r := range s {
		if r == 0 || unicode.IsControl(r) {
			return true
		}
	}
	return false
}

// pathInsideRoot reports whether candidate (already absolute) resolves inside
// root via EvalSymlinks + filepath.Rel without ".." escape. Both root and
// candidate are symlink-evaluated. Non-regular final files fail.
func pathInsideRoot(root, candidate string) (canonical string, err error) {
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("attachment path rejected")
	}
	evalRoot, err := filepath.EvalSymlinks(absRoot)
	if err != nil {
		return "", fmt.Errorf("attachment path rejected")
	}
	absCand, err := filepath.Abs(candidate)
	if err != nil {
		return "", fmt.Errorf("attachment path rejected")
	}
	// Evaluate the parent so a dangling final component still allows Rel, then
	// Lstat the final path to reject symlink files and non-regular nodes.
	parent := filepath.Dir(absCand)
	evalParent, err := filepath.EvalSymlinks(parent)
	if err != nil {
		return "", fmt.Errorf("attachment path rejected")
	}
	finalName := filepath.Base(absCand)
	if finalName == "." || finalName == ".." || finalName == string(filepath.Separator) {
		return "", fmt.Errorf("attachment path rejected")
	}
	joined := filepath.Join(evalParent, finalName)
	fi, err := os.Lstat(joined)
	if err != nil {
		return "", fmt.Errorf("attachment path rejected")
	}
	if fi.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("attachment path rejected")
	}
	if !fi.Mode().IsRegular() {
		return "", fmt.Errorf("attachment path rejected")
	}
	// Also reject if evaluating the full path (when it exists as a non-link)
	// escapes the root — belt and suspenders with Rel on the joined path.
	rel, err := filepath.Rel(evalRoot, joined)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("attachment path rejected")
	}
	if strings.Contains(rel, string(filepath.Separator)+".."+string(filepath.Separator)) || strings.HasPrefix(rel, "..") {
		return "", fmt.Errorf("attachment path rejected")
	}
	return joined, nil
}

// safeAttachmentError builds a phone/audit-safe error that may mention id/name
// only — never hostPath or the attachment root.
func safeAttachmentError(a conversationAttachmentReference, reason string) error {
	safeName := sanitizeAttachmentPromptField(a.Name)
	safeID := sanitizeAttachmentPromptField(a.ID)
	if safeName == "" {
		safeName = "attachment"
	}
	if safeID == "" {
		return fmt.Errorf("%s: %s", safeName, reason)
	}
	return fmt.Errorf("%s (%s): %s", safeName, safeID, reason)
}

// resolveAndVerifyAttachments looks up each ref's put receipt, enforces the
// attachment-root trust boundary, and re-hashes file bytes immediately before
// launch. Returns canonical resolved entries for the vendor manifest.
// Errors never include hostPath.
func resolveAndVerifyAttachments(atts []conversationAttachmentReference) ([]resolvedAttachment, error) {
	if len(atts) == 0 {
		return nil, nil
	}
	root, err := ensureAttachmentRoot()
	if err != nil {
		return nil, fmt.Errorf("attachment storage unavailable")
	}
	out := make([]resolvedAttachment, 0, len(atts))
	for _, a := range atts {
		resolved, err := resolveAndVerifyOne(root, a)
		if err != nil {
			return nil, err
		}
		out = append(out, resolved)
	}
	return out, nil
}

func resolveAndVerifyOne(root string, a conversationAttachmentReference) (resolvedAttachment, error) {
	if !isValidContentDigest(a.ContentDigest) {
		return resolvedAttachment{}, safeAttachmentError(a,
			"missing contentDigest — re-upload the attachment with a current daemon")
	}
	receipt, err := loadAttachmentReceipt(root, a.ID)
	if err != nil {
		return resolvedAttachment{}, safeAttachmentError(a,
			"no upload receipt — upload via attachment.put before append")
	}
	if receipt.ContentDigest != a.ContentDigest {
		return resolvedAttachment{}, safeAttachmentError(a, "contentDigest does not match upload receipt")
	}
	if receipt.ByteCount != int64(a.ByteCount) {
		return resolvedAttachment{}, safeAttachmentError(a, "byteCount does not match upload receipt")
	}

	// Display identity is server-authoritative: receipt.Name wins. A non-empty
	// client name that disagrees is rejected (no path leak); empty client name
	// is canonicalized to the receipt name for digest/manifest/UI metadata.
	displayName := strings.TrimSpace(receipt.Name)
	if displayName == "" {
		return resolvedAttachment{}, safeAttachmentError(a, "upload receipt name is invalid")
	}
	if clientName := strings.TrimSpace(a.Name); clientName != "" && clientName != displayName {
		return resolvedAttachment{}, safeAttachmentError(a, "name does not match upload receipt")
	}

	// Server-authoritative path from receipt — ignore client hostPath as authority.
	cand := filepath.Join(root, filepath.FromSlash(receipt.RelPath))
	// Content-addressed objects must live at objects/<digest>.
	wantRel := filepath.ToSlash(filepath.Join("objects", receipt.ContentDigest))
	if filepath.ToSlash(receipt.RelPath) != wantRel {
		return resolvedAttachment{}, safeAttachmentError(a, "upload receipt path is invalid")
	}
	canonical, err := pathInsideRoot(root, cand)
	if err != nil {
		return resolvedAttachment{}, safeAttachmentError(a, "attachment is missing or outside storage")
	}
	if pathHasControlOrDelimiter(canonical) {
		return resolvedAttachment{}, safeAttachmentError(a, "attachment path rejected")
	}
	// Optional client hostPath: if provided, it must resolve to the same canonical path.
	if hp := strings.TrimSpace(a.HostPath); hp != "" {
		if pathHasControlOrDelimiter(hp) {
			return resolvedAttachment{}, safeAttachmentError(a, "attachment path rejected")
		}
		clientCanon, cerr := pathInsideRoot(root, hp)
		if cerr != nil || clientCanon != canonical {
			return resolvedAttachment{}, safeAttachmentError(a, "hostPath does not match upload receipt")
		}
	}

	digest, size, err := hashAttachmentFileNoFollow(canonical)
	if err != nil {
		return resolvedAttachment{}, safeAttachmentError(a, "attachment is missing or unreadable")
	}
	if digest != a.ContentDigest || digest != receipt.ContentDigest {
		return resolvedAttachment{}, safeAttachmentError(a, "content changed since upload")
	}
	if size != int64(a.ByteCount) || size != receipt.ByteCount {
		return resolvedAttachment{}, safeAttachmentError(a, "content changed since upload")
	}

	return resolvedAttachment{
		ID:            a.ID,
		Name:          displayName,
		Kind:          a.Kind,
		MimeType:      a.MimeType,
		ByteCount:     a.ByteCount,
		ContentDigest: a.ContentDigest,
		HostPath:      canonical,
	}, nil
}

// hashAttachmentFileNoFollow opens path with O_NOFOLLOW (rejects a symlink
// final component), requires a regular file, and returns SHA-256 hex + size.
// Residual: after this returns the FD is closed; Claude reopens by path —
// see package comment.
func hashAttachmentFileNoFollow(path string) (digest string, size int64, err error) {
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return "", 0, err
	}
	f := os.NewFile(uintptr(fd), path)
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return "", 0, err
	}
	if !fi.Mode().IsRegular() {
		return "", 0, fmt.Errorf("not a regular file")
	}
	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return "", 0, err
	}
	if n != fi.Size() {
		return "", 0, fmt.Errorf("size mismatch while hashing")
	}
	return hex.EncodeToString(h.Sum(nil)), n, nil
}

// vendorAttachmentPrompt builds the ephemeral prompt Claude receives.
// With no attachments it returns cleanPrompt unchanged. With attachments it
// wraps a json.Marshal'd manifest in fixed delimiters, then the exact user
// text. Callers must pass resolveAndVerifyAttachments output.
func vendorAttachmentPrompt(cleanPrompt string, resolved []resolvedAttachment) (string, error) {
	if len(resolved) == 0 {
		return cleanPrompt, nil
	}
	entries := make([]vendorAttachmentManifestEntry, 0, len(resolved))
	for _, a := range resolved {
		if pathHasControlOrDelimiter(a.HostPath) {
			return "", fmt.Errorf("%s: attachment path rejected", sanitizeAttachmentPromptField(a.Name))
		}
		entries = append(entries, vendorAttachmentManifestEntry{
			ID:            a.ID,
			Name:          a.Name,
			Kind:          a.Kind,
			MimeType:      a.MimeType,
			ByteCount:     a.ByteCount,
			ContentDigest: a.ContentDigest,
			HostPath:      a.HostPath,
		})
	}
	raw, err := json.Marshal(vendorAttachmentManifest{Attachments: entries})
	if err != nil {
		return "", fmt.Errorf("attachment manifest encoding failed")
	}
	var b strings.Builder
	b.Grow(len(attachmentVendorSectionHeader) + len(raw) + len(attachmentVendorSectionFooter) + len(cleanPrompt) + 8)
	b.WriteString(attachmentVendorSectionHeader)
	b.WriteByte('\n')
	b.Write(raw)
	b.WriteByte('\n')
	b.WriteString(attachmentVendorSectionFooter)
	b.WriteString("\n\n")
	b.WriteString(cleanPrompt)
	return b.String(), nil
}

// sanitizeAttachmentPromptField strips control characters and framing
// delimiter substrings from metadata echoed into safe error text.
func sanitizeAttachmentPromptField(s string) string {
	if s == "" {
		return ""
	}
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		switch {
		case r == 0:
			continue
		case unicode.IsControl(r):
			b.WriteByte(' ')
		default:
			b.WriteRune(r)
		}
	}
	out := strings.TrimSpace(b.String())
	out = strings.ReplaceAll(out, attachmentVendorSectionHeader, "")
	out = strings.ReplaceAll(out, attachmentVendorSectionFooter, "")
	return out
}

// attachmentPathPlaceholders builds absolute-path → placeholder replacements
// for phone-facing tool/artifact JSON. Placeholders use attachmentId + name.
func attachmentPathPlaceholders(resolved []resolvedAttachment) map[string]string {
	if len(resolved) == 0 {
		return nil
	}
	m := make(map[string]string, len(resolved))
	for _, a := range resolved {
		if a.HostPath == "" {
			continue
		}
		label := a.Name
		if label == "" {
			label = "attachment"
		}
		m[a.HostPath] = fmt.Sprintf("attachment://%s (%s)", a.ID, label)
	}
	return m
}

// redactAttachmentPathsInText replaces verified resolved attachment absolute
// paths with placeholders (longest-first). When placeholders are present, also
// replaces the attachment root token itself — bounded to the verified set for
// this run, not a global filesystem scrub. Unrelated paths/text are unchanged.
// Used on phone/ledger/receipt-facing emits — vendor stdin is not altered.
func redactAttachmentPathsInText(s, root string, placeholders map[string]string) string {
	if s == "" {
		return s
	}
	out := s
	// Longest verified paths first so nested prefixes replace correctly.
	if len(placeholders) > 0 {
		paths := make([]string, 0, len(placeholders))
		for p := range placeholders {
			paths = append(paths, p)
		}
		sort.Slice(paths, func(i, j int) bool { return len(paths[i]) > len(paths[j]) })
		for _, p := range paths {
			if p != "" && strings.Contains(out, p) {
				out = strings.ReplaceAll(out, p, placeholders[p])
			}
		}
		// Bounded root token scrub only in attachment-backed runs (placeholders
		// non-empty) so a bare root echo cannot leak storage location.
		root = strings.TrimSpace(root)
		if root != "" && strings.Contains(out, root) {
			out = strings.ReplaceAll(out, root, "attachment://")
		}
	}
	return out
}

// redactAttachmentPathsInParams returns a shallow-copied param map with
// attachment absolute paths redacted in phone/ledger-facing string fields.
func redactAttachmentPathsInParams(method string, params any, root string, placeholders map[string]string) any {
	if len(placeholders) == 0 && strings.TrimSpace(root) == "" {
		return params
	}
	m, ok := params.(map[string]any)
	if !ok || m == nil {
		return params
	}
	switch method {
	case "agent.tool.start", "agent.question.raw":
		if raw, ok := m["inputJSON"].(string); ok && raw != "" {
			cp := cloneStringAnyMap(m)
			cp["inputJSON"] = redactAttachmentPathsInText(raw, root, placeholders)
			return cp
		}
	case "agent.artifact":
		if raw, ok := m["payloadJSON"].(string); ok && raw != "" {
			cp := cloneStringAnyMap(m)
			cp["payloadJSON"] = redactAttachmentPathsInText(raw, root, placeholders)
			return cp
		}
	case liveStatusMethod:
		if raw, ok := m["target"].(string); ok && raw != "" {
			cp := cloneStringAnyMap(m)
			cp["target"] = redactAttachmentPathsInText(raw, root, placeholders)
			return cp
		}
	case "agent.run.output":
		if raw, ok := m["chunk"].(string); ok && raw != "" {
			cp := cloneStringAnyMap(m)
			cp["chunk"] = redactAttachmentPathsInText(raw, root, placeholders)
			return cp
		}
	}
	return params
}

func cloneStringAnyMap(m map[string]any) map[string]any {
	cp := make(map[string]any, len(m))
	for k, v := range m {
		cp[k] = v
	}
	return cp
}
