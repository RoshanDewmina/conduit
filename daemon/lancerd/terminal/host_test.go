package terminal

import (
	"bytes"
	"sync"
	"testing"
	"time"
)

func TestEncodeDecodeStreamFrame(t *testing.T) {
	payload := []byte("hello\n")
	frame := EncodeStreamFrame(OpcodeOutput, 7, 0x100000002, payload)
	op, streamID, seq, out, ok := DecodeStreamFrame(frame)
	if !ok {
		t.Fatal("decode failed")
	}
	if op != OpcodeOutput || streamID != 7 || seq != 0x100000002 {
		t.Fatalf("header mismatch: op=%d stream=%d seq=%d", op, streamID, seq)
	}
	if !bytes.Equal(out, payload) {
		t.Fatalf("payload = %q, want %q", out, payload)
	}
}

func TestCreateOrAttachWriteAndSnapshot(t *testing.T) {
	h := NewHost()
	collector := &collectClient{}
	res, err := h.CreateOrAttach(CreateOrAttachOptions{
		SessionID: "sess-1",
		Cols:      80,
		Rows:      24,
		Command:   "printf 'ORCA_PING\\n'",
	}, collector)
	if err != nil {
		t.Fatalf("CreateOrAttach: %v", err)
	}
	if !res.IsNew {
		t.Fatal("expected isNew")
	}

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if bytes.Contains(collector.bytes(), []byte("ORCA_PING")) {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !bytes.Contains(collector.bytes(), []byte("ORCA_PING")) {
		t.Fatalf("did not observe ORCA_PING in output: %q", collector.bytes())
	}

	reattach, err := h.CreateOrAttach(CreateOrAttachOptions{
		SessionID: "sess-1",
		Cols:      100,
		Rows:      30,
	}, collector)
	if err != nil {
		t.Fatalf("reattach: %v", err)
	}
	if reattach.IsNew {
		t.Fatal("expected reattach isNew=false")
	}
	if reattach.Snapshot == nil || !bytes.Contains([]byte(reattach.Snapshot.SnapshotAnsi), []byte("ORCA_PING")) {
		t.Fatalf("snapshot missing ORCA_PING: %+v", reattach.Snapshot)
	}

	if err := h.Kill("sess-1"); err != nil {
		t.Fatalf("kill: %v", err)
	}
	_, err = h.CreateOrAttach(CreateOrAttachOptions{SessionID: "sess-1", Cols: 80, Rows: 24}, nil)
	if err == nil {
		t.Fatal("expected tombstone to reject recreate")
	}
}

type collectClient struct {
	mu  sync.Mutex
	buf []byte
}

func (c *collectClient) OnData(_ string, data []byte, _ uint64) {
	c.mu.Lock()
	c.buf = append(c.buf, data...)
	c.mu.Unlock()
}
func (c *collectClient) OnExit(string, int) {}
func (c *collectClient) bytes() []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]byte(nil), c.buf...)
}
