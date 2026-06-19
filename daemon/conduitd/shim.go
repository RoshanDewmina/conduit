package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"syscall"
)

type ShimSpawnEvent struct {
	Kind  string   `json:"conduitKind"` // "shim.spawn"
	Agent string   `json:"agent"`
	CWD   string   `json:"cwd"`
	Argv  []string `json:"argv"`
}

type ShimSpawnReply struct {
	Action   string `json:"action"` // attached | passthrough
	TmuxName string `json:"tmuxName,omitempty"`
	Reason   string `json:"reason,omitempty"`
}

func newSessionID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// isShimSpawn reports whether a raw-JSON daemon message is a shim spawn intent.
func isShimSpawn(payload []byte) bool {
	var probe struct {
		Kind string `json:"conduitKind"`
	}
	if err := json.Unmarshal(payload, &probe); err != nil {
		return false
	}
	return probe.Kind == "shim.spawn"
}

func (s *server) handleShimSpawn(ev ShimSpawnEvent) ShimSpawnReply {
	id := newSessionID()
	tmuxName := "conduit-" + id
	agent := normalizeAgentSource(ev.Agent)

	launch := tmuxLauncher(tmuxName)
	if _, err := launch(ev.Argv, ev.CWD, id, s.emitNotification); err != nil {
		return ShimSpawnReply{Action: "passthrough", Reason: err.Error()}
	}
	s.sessions.register(ShimSession{
		ID: id, Agent: agent, TmuxName: tmuxName, CWD: ev.CWD, Status: "running",
	})
	s.emitShimStatus()
	return ShimSpawnReply{Action: "attached", TmuxName: tmuxName}
}

// handleShimSpawnConn decodes a shim spawn event from a raw-JSON connection,
// launches it, and writes the JSON reply.
func (s *server) handleShimSpawnConn(conn net.Conn, payload []byte) {
	defer conn.Close()
	var ev ShimSpawnEvent
	if err := json.Unmarshal(payload, &ev); err != nil {
		_ = json.NewEncoder(conn).Encode(ShimSpawnReply{Action: "passthrough", Reason: "bad spawn event"})
		return
	}
	reply := s.handleShimSpawn(ev)
	_ = json.NewEncoder(conn).Encode(reply)
}

// runShim is the host-side client: connect to the daemon socket, send a spawn
// intent, and either exit (daemon attached in tmux) or exec the real binary.
func runShim(args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: conduitd shim <agent> [args...]")
	}
	agent := args[0]
	cwd, _ := os.Getwd()
	ev := ShimSpawnEvent{Kind: "shim.spawn", Agent: agent, CWD: cwd, Argv: args}

	reply, err := dialShimSpawn(ev)
	if err != nil || reply.Action != "attached" {
		return execRealBinary(agent, args)
	}
	fmt.Fprintf(os.Stderr, "[conduit] session attached in tmux %s — open it in the Conduit app.\n", reply.TmuxName)
	return nil
}

func dialShimSpawn(ev ShimSpawnEvent) (ShimSpawnReply, error) {
	var reply ShimSpawnReply
	sock, err := socketPath()
	if err != nil {
		return reply, err
	}
	conn, err := net.Dial("unix", sock)
	if err != nil {
		return reply, err
	}
	defer conn.Close()
	if err := json.NewEncoder(conn).Encode(ev); err != nil {
		return reply, err
	}
	if err := json.NewDecoder(conn).Decode(&reply); err != nil {
		return reply, err
	}
	return reply, nil
}

// execRealBinary replaces the current process with the real agent binary,
// resolved from CONDUIT_REAL_<agent> set by the installer (fail-open path).
func execRealBinary(agent string, args []string) error {
	real := os.Getenv("CONDUIT_REAL_" + agent)
	if real == "" {
		return fmt.Errorf("real %s binary not found (CONDUIT_REAL_%s unset)", agent, agent)
	}
	return syscall.Exec(real, args, os.Environ())
}

type relayStatusData struct {
	Agent        string
	Model        string
	SessionCount int
	UsageUSD     float64
	HostName     string
}

// shimStatusData aggregates running shim sessions for one agent into a status
// summary suitable for the relay agentStatus message.
func (s *server) shimStatusData(agent string) relayStatusData {
	n := 0
	for _, ss := range s.sessions.list() {
		if ss.Agent == agent && ss.Status == "running" {
			n++
		}
	}
	return relayStatusData{Agent: agent, SessionCount: n}
}

// emitShimStatus pushes an agentStatus update per known agent over the relay so
// the app's existing agentStatus ingestion updates the fleet with shim sessions.
func (s *server) emitShimStatus() {
	if s.e2e == nil {
		return
	}
	hostName, _ := os.Hostname()
	for _, agent := range []string{"claudeCode", "codex", "opencode"} {
		d := s.shimStatusData(agent)
		s.e2e.sendStatusUpdate(d.Agent, d.Model, d.SessionCount, d.UsageUSD, hostName)
	}
}
