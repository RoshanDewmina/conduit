package main

import (
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSanitizeAttachmentName(t *testing.T) {
	cases := []struct {
		in      string
		want    string
		wantErr bool
	}{
		{"photo.png", "photo.png", false},
		{"../../etc/passwd", "passwd", false},
		{"foo/bar.png", "bar.png", false},
		{`foo\bar.png`, "bar.png", false},
		{"..", "", true},
		{".", "", true},
		{"", "", true},
		{"   ", "", true},
	}
	for _, tc := range cases {
		got, err := sanitizeAttachmentName(tc.in)
		if tc.wantErr {
			if err == nil {
				t.Errorf("sanitize(%q) expected error, got %q", tc.in, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("sanitize(%q): %v", tc.in, err)
			continue
		}
		if got != tc.want {
			t.Errorf("sanitize(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestAttachmentPutChunkReassembly(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	payload := []byte("hello-attachment-world-0123456789")
	chunk1 := payload[:10]
	chunk2 := payload[10:]

	r1, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "note.txt",
		TotalBytes: int64(len(payload)),
		Seq:        0,
		DataBase64: base64.StdEncoding.EncodeToString(chunk1),
		Done:       false,
	})
	if err != nil {
		t.Fatalf("chunk0: %v", err)
	}
	if !r1.OK || r1.Path != "" {
		t.Fatalf("chunk0 result = %+v, want ok without path", r1)
	}

	r2, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "note.txt",
		TotalBytes: int64(len(payload)),
		Seq:        1,
		DataBase64: base64.StdEncoding.EncodeToString(chunk2),
		Done:       true,
	})
	if err != nil {
		t.Fatalf("chunk1: %v", err)
	}
	if r2.Path == "" {
		t.Fatal("expected path on final chunk")
	}
	if r2.ID == "" || !isValidContentDigest(r2.ContentDigest) {
		t.Fatalf("expected id+contentDigest on final chunk: %+v", r2)
	}
	wantDigest := sha256Hex(string(payload))
	if r2.ContentDigest != wantDigest {
		t.Fatalf("contentDigest = %q, want %q", r2.ContentDigest, wantDigest)
	}
	if !strings.Contains(r2.Path, filepath.Join(home, ".lancer", "attachments", "objects", wantDigest)) {
		t.Errorf("path %q not under objects/%s", r2.Path, wantDigest)
	}

	got, err := os.ReadFile(r2.Path)
	if err != nil {
		t.Fatalf("read written file: %v", err)
	}
	if string(got) != string(payload) {
		t.Fatalf("content = %q, want %q", got, payload)
	}

	info, err := os.Stat(r2.Path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if info.Mode().Perm() != 0o400 {
		t.Errorf("file mode = %o, want 0400", info.Mode().Perm())
	}
	dirInfo, err := os.Stat(filepath.Dir(r2.Path))
	if err != nil {
		t.Fatalf("stat dir: %v", err)
	}
	if dirInfo.Mode().Perm() != 0o700 {
		t.Errorf("dir mode = %o, want 0700", dirInfo.Mode().Perm())
	}
}

func TestAttachmentPutRejectsPathSeparatorsAfterSanitize(t *testing.T) {
	_, err := sanitizeAttachmentName("..")
	if err == nil {
		t.Fatal("expected error for ..")
	}
	_, err = sanitizeAttachmentName("/")
	if err == nil {
		t.Fatal("expected error for /")
	}
}

func TestAttachmentPutSizeCap(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	_, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "big.bin",
		TotalBytes: attachmentMaxBytes + 1,
		Seq:        0,
		DataBase64: base64.StdEncoding.EncodeToString([]byte("x")),
		Done:       true,
	})
	if err == nil {
		t.Fatal("expected size-cap error")
	}
	if !strings.Contains(err.Error(), "byte limit") {
		t.Errorf("error = %v, want byte limit", err)
	}
}

func TestAttachmentPutChunkSizeCap(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	big := make([]byte, attachmentMaxChunkBytes+1)
	_, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "chunk.bin",
		TotalBytes: int64(len(big)),
		Seq:        0,
		DataBase64: base64.StdEncoding.EncodeToString(big),
		Done:       true,
	})
	if err == nil {
		t.Fatal("expected chunk-size error")
	}
	if !strings.Contains(err.Error(), "chunk exceeds") {
		t.Errorf("error = %v, want chunk exceeds", err)
	}
}

func TestAttachmentPutFileCap(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	// Fill the in-flight cap with incomplete uploads.
	for i := 0; i < attachmentMaxFiles; i++ {
		name := strings.Repeat("a", i+1) + ".txt"
		_, err := s.handleAttachmentPut(attachmentPutParams{
			Name:       name,
			TotalBytes: 2,
			Seq:        0,
			DataBase64: base64.StdEncoding.EncodeToString([]byte("x")),
			Done:       false,
		})
		if err != nil {
			t.Fatalf("file %d: %v", i, err)
		}
	}
	_, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "overflow.txt",
		TotalBytes: 1,
		Seq:        0,
		DataBase64: base64.StdEncoding.EncodeToString([]byte("x")),
		Done:       true,
	})
	if err == nil {
		t.Fatal("expected in-flight cap error")
	}

	// Completing one upload frees its slot — the cap is concurrency, not lifetime.
	if _, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "a.txt",
		TotalBytes: 2,
		Seq:        1,
		DataBase64: base64.StdEncoding.EncodeToString([]byte("y")),
		Done:       true,
	}); err != nil {
		t.Fatalf("finishing upload: %v", err)
	}
	if _, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "after-free.txt",
		TotalBytes: 1,
		Seq:        0,
		DataBase64: base64.StdEncoding.EncodeToString([]byte("x")),
		Done:       true,
	}); err != nil {
		t.Fatalf("upload after freed slot: %v", err)
	}
}

func TestAttachmentPutRetryAfterAbort(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	s := newServer(t.TempDir())
	defer s.poller.stopForTest()

	// Start an upload, then abort mid-way (leave hub entry with nextSeq=1).
	if _, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "retry.txt",
		TotalBytes: 4,
		Seq:        0,
		DataBase64: base64.StdEncoding.EncodeToString([]byte("ab")),
		Done:       false,
	}); err != nil {
		t.Fatalf("first chunk: %v", err)
	}

	// Without restart semantics, seq 0 would fail with "expected seq 1".
	payload := []byte("ok!!")
	r, err := s.handleAttachmentPut(attachmentPutParams{
		Name:       "retry.txt",
		TotalBytes: int64(len(payload)),
		Seq:        0,
		DataBase64: base64.StdEncoding.EncodeToString(payload),
		Done:       true,
	})
	if err != nil {
		t.Fatalf("retry from seq 0: %v", err)
	}
	if r.Path == "" || !r.OK {
		t.Fatalf("retry result = %+v", r)
	}
	got, err := os.ReadFile(r.Path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != string(payload) {
		t.Fatalf("content = %q, want %q", got, payload)
	}
}

func TestE2ERouterAttachmentPutUnmarshalError(t *testing.T) {
	srv := newServer(t.TempDir())
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	router.handleMessage("attachmentPut", []byte(`{not-json`))

	msgType, raw := client.lastMessage()
	if msgType != "attachmentPutResult" {
		t.Fatalf("expected attachmentPutResult, got %q", msgType)
	}
	var env struct {
		Type    string `json:"type"`
		Payload struct {
			OK    bool   `json:"ok"`
			Error string `json:"error"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if env.Payload.OK {
		t.Fatal("expected ok=false")
	}
	if env.Payload.Error == "" {
		t.Fatal("expected error field set")
	}
}

func TestE2ERouterAttachmentPut(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	srv := newServer(t.TempDir())
	defer srv.poller.stopForTest()

	client := &fakeRelayClient{paired: true}
	router := newE2ERouter(nil, srv)
	router.client = client

	data := []byte("relay-bytes")
	payload, err := json.Marshal(map[string]interface{}{
		"name":       "shot.png",
		"totalBytes": len(data),
		"seq":        0,
		"dataBase64": base64.StdEncoding.EncodeToString(data),
		"done":       true,
	})
	if err != nil {
		t.Fatal(err)
	}
	router.handleMessage("attachmentPut", payload)

	msgType, raw := client.lastMessage()
	if msgType != "attachmentPutResult" {
		t.Fatalf("expected attachmentPutResult, got %q", msgType)
	}
	var env struct {
		Type    string `json:"type"`
		Payload struct {
			Path          string `json:"path"`
			ID            string `json:"id"`
			ContentDigest string `json:"contentDigest"`
			OK            bool   `json:"ok"`
			Error         string `json:"error"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if env.Payload.Error != "" {
		t.Fatalf("unexpected error: %q", env.Payload.Error)
	}
	if env.Payload.Path == "" || !env.Payload.OK {
		t.Fatalf("payload = %+v", env.Payload)
	}
	if env.Payload.ID == "" || env.Payload.ContentDigest == "" {
		t.Fatalf("missing id/contentDigest: %+v", env.Payload)
	}
	got, err := os.ReadFile(env.Payload.Path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != string(data) {
		t.Fatalf("content = %q", got)
	}
}
