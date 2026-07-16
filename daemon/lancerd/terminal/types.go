// Package terminal owns interactive PTY sessions inside lancerd.
//
// Ported from Orca (MIT, Lovecast Inc.) — https://github.com/stablyai/orca
// Sources: src/main/daemon/types.ts, terminal-host-create-contract.ts
package terminal

// CreateOrAttachOptions mirrors Orca's createOrAttach request.
type CreateOrAttachOptions struct {
	SessionID string
	Cols      int
	Rows      int
	CWD       string
	Env       map[string]string
	Command   string // optional startup command written after spawn
}

// CreateOrAttachResult mirrors Orca's createOrAttach response.
type CreateOrAttachResult struct {
	IsNew      bool              `json:"isNew"`
	Snapshot   *Snapshot         `json:"snapshot,omitempty"`
	PID        int               `json:"pid"`
	ShellState string            `json:"shellState"`
	SessionID  string            `json:"sessionId"`
}

// Snapshot is the host-authoritative screen restore payload.
// Orca fills this from @xterm/headless SerializeAddon; we use a scrollback
// ring buffer that still matches the wire field names clients expect.
type Snapshot struct {
	SnapshotAnsi   string `json:"snapshotAnsi"`
	ScrollbackAnsi string `json:"scrollbackAnsi"`
	CWD            string `json:"cwd,omitempty"`
	Cols           int    `json:"cols"`
	Rows           int    `json:"rows"`
	OutputSequence uint64 `json:"outputSequence"`
}

// SessionInfo is a list row for terminal.list.
type SessionInfo struct {
	SessionID string `json:"sessionId"`
	PID       int    `json:"pid"`
	Cols      int    `json:"cols"`
	Rows      int    `json:"rows"`
	CWD       string `json:"cwd"`
	IsAlive   bool   `json:"isAlive"`
	Title     string `json:"title"`
}

// Client is a fan-out subscriber (relay phone, local adapter, etc.).
type Client interface {
	OnData(sessionID string, data []byte, sequence uint64)
	OnExit(sessionID string, code int)
}

// StreamOpcode mirrors Orca TerminalStreamOpcode
// (src/shared/terminal-stream-protocol.ts).
type StreamOpcode byte

const (
	OpcodeOutput         StreamOpcode = 1
	OpcodeSnapshotStart  StreamOpcode = 2
	OpcodeSnapshotChunk  StreamOpcode = 3
	OpcodeSnapshotEnd    StreamOpcode = 4
	OpcodeResized        StreamOpcode = 5
	OpcodeError          StreamOpcode = 6
	OpcodeInput          StreamOpcode = 7
	OpcodeResize         StreamOpcode = 8
	OpcodeSubscribe      StreamOpcode = 9
	OpcodeUnsubscribe    StreamOpcode = 10
	OpcodeSnapshotRequest StreamOpcode = 11
	OpcodeMetadata       StreamOpcode = 12
	OpcodeAck            StreamOpcode = 13
)

const (
	streamKind    = 0x74 // 't'
	streamVersion = 1
	headerBytes   = 16
)
