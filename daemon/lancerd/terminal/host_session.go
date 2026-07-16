// Ported from Orca (MIT, Lovecast Inc.) — https://github.com/stablyai/orca
// Source: src/main/daemon/session.ts (simplified: ring-buffer snapshot instead
// of @xterm/headless SerializeAddon).
package terminal

import (
	"io"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/creack/pty"
)

const scrollbackCap = 256 * 1024 // keep newest 256 KiB for attach snapshots

// Session is one daemon-owned interactive PTY.
type Session struct {
	id   string
	cmd  *exec.Cmd
	file *os.File

	mu       sync.Mutex
	cols     int
	rows     int
	cwd      string
	alive    bool
	exitCode int
	seq      uint64
	buf      []byte // newest-tail scrollback
	clients  []Client
	title    string
}

func spawnSession(id string, cols, rows int, cwd string, env map[string]string, command string) (*Session, error) {
	if cols <= 0 {
		cols = 80
	}
	if rows <= 0 {
		rows = 24
	}
	shell := os.Getenv("SHELL")
	if shell == "" {
		for _, candidate := range []string{"/bin/zsh", "/bin/bash", "/bin/sh"} {
			if _, err := os.Stat(candidate); err == nil {
				shell = candidate
				break
			}
		}
	}
	if shell == "" {
		shell = "/bin/sh"
	}
	// Login shells (-l) can hang or skip rc files in CI; interactive non-login is enough.
	cmd := exec.Command(shell)
	if cwd != "" {
		cmd.Dir = cwd
	}
	cmd.Env = os.Environ()
	cmd.Env = append(cmd.Env, "TERM=xterm-256color", "COLORTERM=truecolor")
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}

	f, err := pty.StartWithSize(cmd, &pty.Winsize{Cols: uint16(cols), Rows: uint16(rows)})
	if err != nil {
		return nil, err
	}

	s := &Session{
		id:    id,
		cmd:   cmd,
		file:  f,
		cols:  cols,
		rows:  rows,
		cwd:   cwd,
		alive: true,
		title: "shell",
	}
	go s.readLoop()

	if command != "" {
		// Give the shell a moment to settle, then write the startup command.
		go func() {
			time.Sleep(80 * time.Millisecond)
			_, _ = s.Write([]byte(command + "\n"))
		}()
	}
	return s, nil
}

func (s *Session) readLoop() {
	buf := make([]byte, 32*1024)
	for {
		n, err := s.file.Read(buf)
		if n > 0 {
			chunk := append([]byte(nil), buf[:n]...)
			s.fanout(chunk)
		}
		if err != nil {
			code := 0
			if s.cmd.ProcessState != nil {
				code = s.cmd.ProcessState.ExitCode()
			} else if err != io.EOF {
				code = 1
			}
			s.markExited(code)
			return
		}
	}
}

func (s *Session) fanout(data []byte) {
	s.mu.Lock()
	s.seq += uint64(len(data))
	s.appendScrollback(data)
	clients := append([]Client(nil), s.clients...)
	seq := s.seq
	id := s.id
	s.mu.Unlock()
	for _, c := range clients {
		c.OnData(id, data, seq)
	}
}

func (s *Session) appendScrollback(data []byte) {
	s.buf = append(s.buf, data...)
	if len(s.buf) > scrollbackCap {
		s.buf = append([]byte(nil), s.buf[len(s.buf)-scrollbackCap:]...)
	}
}

func (s *Session) markExited(code int) {
	s.mu.Lock()
	if !s.alive {
		s.mu.Unlock()
		return
	}
	s.alive = false
	s.exitCode = code
	clients := append([]Client(nil), s.clients...)
	id := s.id
	s.clients = nil
	s.mu.Unlock()
	for _, c := range clients {
		c.OnExit(id, code)
	}
}

// Write sends bytes to the PTY (Orca terminal.write / terminal.send).
func (s *Session) Write(data []byte) (int, error) {
	s.mu.Lock()
	alive := s.alive
	f := s.file
	s.mu.Unlock()
	if !alive || f == nil {
		return 0, os.ErrClosed
	}
	return f.Write(data)
}

// Resize ports Orca terminal.resize.
func (s *Session) Resize(cols, rows int) error {
	if cols <= 0 || rows <= 0 {
		return nil
	}
	s.mu.Lock()
	s.cols = cols
	s.rows = rows
	f := s.file
	alive := s.alive
	s.mu.Unlock()
	if !alive || f == nil {
		return os.ErrClosed
	}
	return pty.Setsize(f, &pty.Winsize{Cols: uint16(cols), Rows: uint16(rows)})
}

// AttachClient registers a fan-out subscriber (last-attach-wins for mobile).
func (s *Session) AttachClient(c Client) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clients = append(s.clients, c)
}

// DetachAllClients clears subscribers (Orca reattach pattern).
func (s *Session) DetachAllClients() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clients = nil
}

// GetSnapshot returns the scrollback ring as snapshotAnsi.
func (s *Session) GetSnapshot() *Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	return &Snapshot{
		SnapshotAnsi:   string(s.buf),
		ScrollbackAnsi: "",
		CWD:            s.cwd,
		Cols:           s.cols,
		Rows:           s.rows,
		OutputSequence: s.seq,
	}
}

func (s *Session) Info() SessionInfo {
	s.mu.Lock()
	defer s.mu.Unlock()
	pid := 0
	if s.cmd != nil && s.cmd.Process != nil {
		pid = s.cmd.Process.Pid
	}
	return SessionInfo{
		SessionID: s.id,
		PID:       pid,
		Cols:      s.cols,
		Rows:      s.rows,
		CWD:       s.cwd,
		IsAlive:   s.alive,
		Title:     s.title,
	}
}

func (s *Session) IsAlive() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.alive
}

func (s *Session) PID() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cmd != nil && s.cmd.Process != nil {
		return s.cmd.Process.Pid
	}
	return 0
}

// Kill terminates the session (tombstone handled by Host).
func (s *Session) Kill() {
	s.mu.Lock()
	f := s.file
	cmd := s.cmd
	s.mu.Unlock()
	if f != nil {
		_ = f.Close()
	}
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}
	s.markExited(-1)
}
