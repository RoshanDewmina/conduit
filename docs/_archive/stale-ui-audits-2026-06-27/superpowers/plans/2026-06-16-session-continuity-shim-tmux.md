# Session Continuity via Host Shim + tmux Container — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user types `claude` (or `codex`) in their host Terminal, the session is launched inside a Lancer-managed tmux container with hooks active from byte zero, registered with `lancerd`, and surfaced in the iOS app as a live, governable session they can attach to and continue.

**Architecture:** A three-layer host shim (PATH binary + shell function + `LANCER_*` env) intercepts the agent command and hands off to `lancerd` over its existing Unix socket. A new `ShimController` in `lancerd` registers the session, launches the real agent inside `tmux new-session -s lancer-<id>`, and emits `agentStatus` over the relay. The iOS app reuses the existing `TmuxClient` attach path and `AgentResumeBuilder` to open the live block terminal. A read-only **transcript watcher** polls `~/.claude/projects/**` to mirror pre-existing *bare* sessions (started without the shim) and offers a "Take over" action.

**Tech Stack:** Go (lancerd, `daemon/lancerd/`), POSIX sh / zsh / bash / fish (shim shell integration), Swift 6 strict-concurrency (LancerKit, `Packages/LancerKit/Sources/`), tmux ≥ 3.0.

## Global Constraints

- **Shim must fail open.** If `lancerd` is unreachable, the shim execs the real binary unmodified (zero added latency on the failure path). Verbatim rule: a broken Lancer install must never prevent `claude` from running.
- **Production paths keep the TOFU host-key prompt** (debug harnesses may auto-trust; the shim/daemon must not).
- **No second byte source.** The iOS side uses the single unified PTY; never spawn a parallel `SSHShell` (agent-contract.md §5).
- **tmux session names** must pass `isValidTmuxName` (alphanumeric, `-`, `_`, `.` only) — already enforced in `TmuxClient.swift:70`. Daemon-side names use the same charset: `lancer-<8hexid>`.
- **Go:** no cobra; extend the hand-rolled `switch os.Args[1]` in `daemon/lancerd/main.go:19`. Tests use the standard `testing` package; run `cd daemon/lancerd && go test ./...`.
- **Swift app-target build is authoritative** (`mcp__XcodeBuildMCP__build_sim`); `swift build` in `Packages/LancerKit` is the fast inner loop but skips `#if os(iOS)` code.
- **Hooks are file-based** (`~/.claude/settings.json` PreToolUse) — already active for ANY `claude` once `lancerd install` ran. The shim's job is session *registration + tmux containment*, not approval governance (that already works for bare sessions).
- **Do NOT `git commit` unless the user explicitly asks** (overrides the per-task commit steps below — leave commits staged-and-described; the owner commits).

---

## File Structure

| File | New/Mod | Responsibility |
|---|---|---|
| `daemon/lancerd/session_registry.go` | New | In-memory `sessionRegistry`: `register/unregister/get/list` shim-spawned sessions keyed by id. |
| `daemon/lancerd/session_registry_test.go` | New | Unit tests for registry concurrency + lifecycle. |
| `daemon/lancerd/tmux_session.go` | New | `tmuxLauncher` (a `launchFunc`) that spawns the agent inside `tmux new-session -d` and streams output via `capture-pane` polling. |
| `daemon/lancerd/tmux_session_test.go` | New | Tests with a fake tmux binary on PATH. |
| `daemon/lancerd/shim.go` | New | `runShim()` subcommand + `ShimSpawnEvent` JSON type + `handleShimSpawn()` daemon-side handler. |
| `daemon/lancerd/shim_test.go` | New | Round-trip test: spawn event over socket → registry entry + tmux launch (faked). |
| `daemon/lancerd/main.go` | Mod (`:19`, `:119`) | Add `case "shim":` → `runShim(os.Args[2:])`; add usage line. |
| `daemon/lancerd/conn.go` | Mod (`:14-41`) | Recognize the shim raw-JSON event (same envelope family as `agent-hook`). |
| `daemon/lancerd/resident.go` | Mod (`:91-109`) | Route a shim spawn event to `handleShimSpawn`. |
| `daemon/lancerd/e2e_router.go` | Mod (`:64-81`) | Wire the currently-unused `sendStatusUpdate()` so shim sessions emit `agentStatus`. |
| `daemon/lancerd/doctor.go` | Mod (`:71-86`) | Add `checkShimWrapper()` (PATH `claude` resolves to shim?). |
| `daemon/lancerd/transcript_watcher.go` | New | Poll `~/.claude/projects/**` for new/updated `<sessionId>.jsonl`; expose a read-only mirror list + "bare vs managed" classification. |
| `daemon/lancerd/transcript_watcher_test.go` | New | Tests over a temp projects dir. |
| `daemon/lancerd/install.sh` | Mod | Install shim binary + shell integration + env var; idempotent. |
| `daemon/lancerd/shim/lancer-shim.sh` | New | Reference shell-integration snippet sourced into rc files (function + env). |
| `Packages/LancerKit/Sources/LancerCore/Session.swift` | Mod (`:3-17`) | Add `origin: SessionOrigin` (`.appInitiated`/`.shimDiscovered`/`.bareMirror`). |
| `Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift` | Mod (`:272`) | Add `DaemonEvent.sessionDiscovered(SessionDiscoveredParams)`. |
| `Packages/LancerKit/Sources/AppFeature/SessionDiscovery.swift` | New | Consumes `sessionDiscovered` events, constructs a `FleetStore.Slot`, calls `fleetStore.add`. |
| `Packages/LancerKit/Sources/AppFeature/SessionDiscovery+Test.swift` | Test | Verifies a discovered session becomes a fleet slot in `.shimDiscovered` origin. |

> **Parallelization note (for opencode dispatch):** Tasks 1–6 are lancerd-Go and touch disjoint new files except the small shared edits to `main.go`/`resident.go`/`e2e_router.go`/`doctor.go` — assign the shared-file edits to ONE agent (Task 7 "daemon wiring") to avoid collisions, or run Go tasks sequentially on one branch. Task 9 (iOS) and Task 8 (transcript) are independent and can run on separate worktrees in parallel with the Go work.

---

## Task 1: lancerd session registry

**Files:**
- Create: `daemon/lancerd/session_registry.go`
- Test: `daemon/lancerd/session_registry_test.go`

**Interfaces:**
- Produces:
  - `type ShimSession struct { ID, Agent, TmuxName, CWD string; PID int; StartedAt time.Time; Status string }`
  - `type sessionRegistry struct { … }` with `newSessionRegistry() *sessionRegistry`
  - `(*sessionRegistry) register(s ShimSession)`, `unregister(id string)`, `get(id string) (ShimSession, bool)`, `list() []ShimSession`, `count() int`
- Consumes: nothing (leaf).

- [ ] **Step 1: Write the failing test**

```go
package main

import "testing"

func TestSessionRegistryLifecycle(t *testing.T) {
	r := newSessionRegistry()
	r.register(ShimSession{ID: "abc123", Agent: "claudeCode", TmuxName: "lancer-abc123", Status: "running"})
	if r.count() != 1 {
		t.Fatalf("count = %d, want 1", r.count())
	}
	got, ok := r.get("abc123")
	if !ok || got.TmuxName != "lancer-abc123" {
		t.Fatalf("get = %+v ok=%v", got, ok)
	}
	r.unregister("abc123")
	if r.count() != 0 {
		t.Fatalf("count after unregister = %d, want 0", r.count())
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd daemon/lancerd && go test -run TestSessionRegistryLifecycle ./...`
Expected: FAIL — `undefined: newSessionRegistry`.

- [ ] **Step 3: Implement the registry**

```go
package main

import (
	"sync"
	"time"
)

type ShimSession struct {
	ID        string    `json:"id"`
	Agent     string    `json:"agent"`
	TmuxName  string    `json:"tmuxName"`
	CWD       string    `json:"cwd"`
	PID       int       `json:"pid"`
	StartedAt time.Time `json:"startedAt"`
	Status    string    `json:"status"` // running | exited | failed
}

type sessionRegistry struct {
	mu       sync.RWMutex
	sessions map[string]ShimSession
}

func newSessionRegistry() *sessionRegistry {
	return &sessionRegistry{sessions: make(map[string]ShimSession)}
}

func (r *sessionRegistry) register(s ShimSession) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if s.StartedAt.IsZero() {
		s.StartedAt = time.Now()
	}
	r.sessions[s.ID] = s
}

func (r *sessionRegistry) unregister(id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.sessions, id)
}

func (r *sessionRegistry) get(id string) (ShimSession, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	s, ok := r.sessions[id]
	return s, ok
}

func (r *sessionRegistry) list() []ShimSession {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]ShimSession, 0, len(r.sessions))
	for _, s := range r.sessions {
		out = append(out, s)
	}
	return out
}

func (r *sessionRegistry) count() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.sessions)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd daemon/lancerd && go test -run TestSessionRegistryLifecycle ./...`
Expected: PASS.

- [ ] **Step 5: Add the registry to the server struct**

In `daemon/lancerd/server.go`, add a `sessions *sessionRegistry` field to the `server` struct and initialize it in `newServer()` with `sessions: newSessionRegistry()`. (Find the struct literal in `newServer`; add the field assignment.)

- [ ] **Step 6: Commit (stage only — owner commits)**

```bash
git add daemon/lancerd/session_registry.go daemon/lancerd/session_registry_test.go daemon/lancerd/server.go
git commit -m "feat(lancerd): add in-memory shim session registry"
```

---

## Task 2: tmux launcher

**Files:**
- Create: `daemon/lancerd/tmux_session.go`
- Test: `daemon/lancerd/tmux_session_test.go`

**Interfaces:**
- Consumes: the existing `launchFunc` signature `func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error)` (`dispatch.go:95`) and `emitFunc` (`dispatch.go:90`).
- Produces: `func tmuxLauncher(tmuxName string) launchFunc` — returns a launcher that runs the agent inside a detached tmux session named `tmuxName`, polling `tmux capture-pane` and emitting `agent.run.output` chunks + a terminal `agent.run.status`.

**Background (verified):** `realLauncher` (`dispatch.go:97-159`) uses `exec.Command` + stdout/stderr pipes; tmux-detached sessions have no direct pipe, so output is read via `tmux capture-pane -p -t <name>`. `TmuxClient.swift` already uses `tmux new-session -d -s <name>` on the iOS side; mirror that command shape.

- [ ] **Step 1: Write the failing test (fake tmux on PATH)**

```go
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeFakeTmux installs a script named "tmux" early on PATH that records argv.
func writeFakeTmux(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	script := "#!/bin/sh\necho \"$@\" >> \"" + filepath.Join(dir, "calls.log") + "\"\nexit 0\n"
	if err := os.WriteFile(filepath.Join(dir, "tmux"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return dir
}

func TestTmuxLauncherStartsDetachedSession(t *testing.T) {
	dir := writeFakeTmux(t)
	launch := tmuxLauncher("lancer-test01")
	var statuses []string
	emit := func(method string, params any) {
		if method == "agent.run.status" {
			statuses = append(statuses, method)
		}
	}
	_, err := launch([]string{"claude", "--resume", "x"}, "/tmp", "run1", emit)
	if err != nil {
		t.Fatalf("launch: %v", err)
	}
	log, _ := os.ReadFile(filepath.Join(dir, "calls.log"))
	if !strings.Contains(string(log), "new-session") || !strings.Contains(string(log), "lancer-test01") {
		t.Fatalf("tmux not invoked with new-session/name: %q", log)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd daemon/lancerd && go test -run TestTmuxLauncher ./...`
Expected: FAIL — `undefined: tmuxLauncher`.

- [ ] **Step 3: Implement `tmuxLauncher`**

```go
package main

import (
	"context"
	"os/exec"
	"time"
)

// tmuxLauncher returns a launchFunc that runs the agent inside a detached tmux
// session. Output is polled from capture-pane and emitted as agent.run.output
// chunks; on session death it emits a terminal agent.run.status.
func tmuxLauncher(tmuxName string) launchFunc {
	return func(argv []string, cwd, runID string, emit emitFunc) (*procHandle, error) {
		// new-session -d -s <name> -c <cwd> -- argv...
		args := []string{"new-session", "-d", "-s", tmuxName}
		if cwd != "" {
			args = append(args, "-c", expandHome(cwd))
		}
		args = append(args, "--")
		args = append(args, argv...)
		if err := exec.Command("tmux", args...).Run(); err != nil {
			return nil, err
		}
		emitRunStatus(emit, runID, "running", nil)

		ctx, cancel := context.WithCancel(context.Background())
		h := &procHandle{cancel: cancel} // procHandle already carries a cancel; see dispatch.go
		go pollTmuxPane(ctx, tmuxName, runID, emit)
		return h, nil
	}
}

func pollTmuxPane(ctx context.Context, tmuxName, runID string, emit emitFunc) {
	var lastLen int
	seq := 0
	ticker := time.NewTicker(400 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			out, err := exec.Command("tmux", "capture-pane", "-p", "-t", tmuxName).Output()
			if err != nil {
				// session gone → terminal status, stop polling.
				emitRunStatus(emit, runID, "exited", nil)
				return
			}
			if len(out) > lastLen {
				chunk := string(out[lastLen:])
				lastLen = len(out)
				seq++
				emit("agent.run.output", map[string]any{
					"runId": runID, "stream": "stdout", "chunk": chunk, "seq": seq,
				})
			}
		}
	}
}
```

> **Implementer note:** Confirm the real `procHandle` struct shape in `dispatch.go` (around `:143`) and adapt the returned handle + how `kill` cancels the poll. If `procHandle` has no `cancel` field, add one or store the `context.CancelFunc` so `applyRunControl(stop)` can cancel `pollTmuxPane` and run `tmux kill-session -t <name>`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd daemon/lancerd && go test -run TestTmuxLauncher ./...`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add daemon/lancerd/tmux_session.go daemon/lancerd/tmux_session_test.go
git commit -m "feat(lancerd): tmux-container launcher with capture-pane streaming"
```

---

## Task 3: shim spawn-intent IPC (subcommand + handler)

**Files:**
- Create: `daemon/lancerd/shim.go`
- Test: `daemon/lancerd/shim_test.go`
- Modify: `daemon/lancerd/main.go:19,119`, `daemon/lancerd/conn.go:14-41`, `daemon/lancerd/resident.go:91-109`

**Interfaces:**
- Produces:
  - `type ShimSpawnEvent struct { Kind string `json:"lancerKind"`; Agent, CWD string; Argv []string }` (`Kind == "shim.spawn"` discriminates it from an `ApprovalEvent` on the same raw-JSON socket path).
  - `type ShimSpawnReply struct { Action string `json:"action"`; TmuxName string `json:"tmuxName,omitempty"`; Reason string `json:"reason,omitempty"` }` — `Action` is `"attached"` (daemon launched in tmux; shim should exit 0) or `"passthrough"` (shim must exec the real binary).
  - `func runShim(args []string) error` — the client side run on the host.
  - `func (s *server) handleShimSpawn(ev ShimSpawnEvent) ShimSpawnReply` — daemon side.

**Background (verified):** The socket at `~/.lancer/lancerd.sock` carries two protocols distinguished by first byte (`conn.go:14-41`): raw JSON (`{`) for `agent-hook`, length-prefixed framing for `serve`. The shim reuses the **raw-JSON** path. `resident.go:91-109` dispatches raw JSON → `handleHookWithNotify`; add a discriminator so `lancerKind=="shim.spawn"` routes to `handleShimSpawn` instead.

- [ ] **Step 1: Write the failing daemon-side test**

```go
package main

import "testing"

func TestHandleShimSpawnLaunchesTmux(t *testing.T) {
	writeFakeTmux(t) // from tmux_session_test.go (same package)
	s := newServer(t.TempDir())
	reply := s.handleShimSpawn(ShimSpawnEvent{
		Kind: "shim.spawn", Agent: "claude", CWD: "/tmp", Argv: []string{"claude"},
	})
	if reply.Action != "attached" {
		t.Fatalf("action = %q, want attached", reply.Action)
	}
	if reply.TmuxName == "" || s.sessions.count() != 1 {
		t.Fatalf("expected one registered session, got %d (tmux=%q)", s.sessions.count(), reply.TmuxName)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd daemon/lancerd && go test -run TestHandleShimSpawn ./...`
Expected: FAIL — `undefined: handleShimSpawn`.

- [ ] **Step 3: Implement `handleShimSpawn` + `runShim` + `ShimSpawnEvent`**

```go
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
	Kind  string   `json:"lancerKind"` // "shim.spawn"
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

func (s *server) handleShimSpawn(ev ShimSpawnEvent) ShimSpawnReply {
	id := newSessionID()
	tmuxName := "lancer-" + id
	agent := normalizeAgentSource(ev.Agent)

	runID := id
	launch := tmuxLauncher(tmuxName)
	emit := s.emitNotification
	if _, err := launch(ev.Argv, ev.CWD, runID, emit); err != nil {
		return ShimSpawnReply{Action: "passthrough", Reason: err.Error()}
	}
	s.sessions.register(ShimSession{
		ID: id, Agent: agent, TmuxName: tmuxName, CWD: ev.CWD, Status: "running",
	})
	s.emitShimStatus() // Task 5
	return ShimSpawnReply{Action: "attached", TmuxName: tmuxName}
}

// runShim is the host-side client. It connects to the daemon socket, sends a
// spawn intent, and either exits (daemon attached the session in tmux) or
// execs the real binary (fail-open).
func runShim(args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: lancerd shim <agent> [args...]")
	}
	agent := args[0]
	cwd, _ := os.Getwd()
	ev := ShimSpawnEvent{Kind: "shim.spawn", Agent: agent, CWD: cwd, Argv: args}

	reply, err := dialShimSpawn(ev) // dials sockPath(), writes JSON, reads reply
	if err != nil || reply.Action != "attached" {
		return execRealBinary(agent, args) // fail-open
	}
	// Daemon launched it in tmux; print a hint and exit cleanly.
	fmt.Fprintf(os.Stderr, "[lancer] session attached in tmux %s — open it in the Lancer app.\n", reply.TmuxName)
	return nil
}

func dialShimSpawn(ev ShimSpawnEvent) (ShimSpawnReply, error) {
	var reply ShimSpawnReply
	conn, err := net.Dial("unix", sockPath())
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

// execRealBinary replaces the current process with the real agent binary found
// AFTER the shim on PATH (resolve via $LANCER_REAL_<AGENT> or a `.real` suffix).
func execRealBinary(agent string, args []string) error {
	real := os.Getenv("LANCER_REAL_" + agent) // set by installer; e.g. /opt/homebrew/bin/claude
	if real == "" {
		return fmt.Errorf("real %s binary not found (LANCER_REAL_%s unset)", agent, agent)
	}
	return syscall.Exec(real, args, os.Environ())
}
```

> Confirm `sockPath()` is the exported accessor in `paths.go:32` (the report cites `~/.lancer/lancerd.sock`). If it is unexported as `socketPath()`, match that name.

- [ ] **Step 4: Wire `main.go` and the socket dispatch**

In `main.go:19` switch, add:
```go
	case "shim":
		if err := runShim(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, "lancerd shim:", err)
			os.Exit(1)
		}
```
Add to `usage()` (`:119`): `  lancerd shim <agent> ...  Intercept an agent launch and hand off to the daemon`.

In `resident.go:91-109` (raw-JSON branch), peek the decoded JSON: if `lancerKind == "shim.spawn"` decode as `ShimSpawnEvent` and reply with `handleShimSpawn`; else keep the existing `handleHookWithNotify` path. (The first-byte detection in `conn.go:14-41` already classifies raw JSON; the discriminator is the `lancerKind` field.)

- [ ] **Step 5: Run daemon-side test to verify it passes**

Run: `cd daemon/lancerd && go test -run 'TestHandleShimSpawn|TestSessionRegistry|TestTmuxLauncher' ./...`
Expected: PASS.

- [ ] **Step 6: Build the binary to confirm wiring compiles**

Run: `cd daemon/lancerd && go build ./...`
Expected: no errors.

- [ ] **Step 7: Commit (stage only)**

```bash
git add daemon/lancerd/shim.go daemon/lancerd/shim_test.go daemon/lancerd/main.go daemon/lancerd/resident.go daemon/lancerd/conn.go
git commit -m "feat(lancerd): shim spawn-intent subcommand + tmux handoff (fail-open)"
```

---

## Task 4: lancer-shim binary install + shell integration

**Files:**
- Create: `daemon/lancerd/shim/lancer-shim.sh`
- Modify: `daemon/lancerd/install.sh`

**Interfaces:**
- Produces: a PATH entry `~/.lancer/bin/claude` (and `codex`) that execs `lancerd shim <agent> "$@"`; a shell function `claude()` sourced into rc files that shadows aliases; env vars `LANCER_CLAUDE_WRAPPER_SHIM=1` and `LANCER_REAL_claude=<resolved path>`.

**Background (verified):** `install.sh` already installs the binary + launchd/systemd unit. The three-layer strategy (research doc §1) is required because PATH alone misses alias/function shadowing and non-interactive shells.

- [ ] **Step 1: Author the shell-integration snippet**

Create `daemon/lancerd/shim/lancer-shim.sh`:
```sh
# Lancer shim — source me from ~/.zshrc / ~/.bashrc (managed block).
# Layer 2: shell function shadows aliases and PATH alike.
export LANCER_CLAUDE_WRAPPER_SHIM=1
: "${LANCER_REAL_claude:=$(command -v claude 2>/dev/null)}"
export LANCER_REAL_claude
claude() {
  if [ -x "$HOME/.lancer/bin/claude" ]; then
    "$HOME/.lancer/bin/claude" "$@"
  else
    command claude "$@"
  fi
}
```
(fish variant uses `function claude` + `set -gx`; emit it conditionally when `~/.config/fish` exists.)

- [ ] **Step 2: Add the PATH shim + rc wiring to `install.sh`**

Append an idempotent block to `install.sh` that:
1. Writes `~/.lancer/bin/claude` (and `codex`) as:
   ```sh
   #!/bin/sh
   exec "$LANCERD_BIN" shim claude "$@"
   ```
   `chmod +x`. (`$LANCERD_BIN` is the installed `~/.lancer/bin/lancerd`.)
2. Resolves the real binary BEFORE inserting `~/.lancer/bin` on PATH, records it as `LANCER_REAL_claude` in `~/.lancer/shim.env`.
3. Inserts a managed, marker-delimited block (`# >>> lancer shim >>>` / `# <<< lancer shim <<<`) into `~/.zshrc` and `~/.bashrc` that prepends `~/.lancer/bin` to PATH and sources `lancer-shim.sh`. Idempotent: skip if the marker already present.

- [ ] **Step 3: Manual verification (host)**

Run:
```bash
bash daemon/lancerd/install.sh
exec "$SHELL" -l           # reload rc
command -v claude          # should resolve to ~/.lancer/bin/claude OR hit the function
type claude                # zsh/bash: should show the function or the shim path
```
Expected: `claude` resolves to the shim. With the daemon stopped, `claude --version` still works (fail-open passthrough).

- [ ] **Step 4: Commit (stage only)**

```bash
git add daemon/lancerd/shim/lancer-shim.sh daemon/lancerd/install.sh
git commit -m "feat(installer): three-layer claude shim (PATH + function + env), fail-open"
```

---

## Task 5: shim-session status emission over relay

**Files:**
- Modify: `daemon/lancerd/e2e_router.go:64-81`, `daemon/lancerd/server.go` (add `emitShimStatus`)

**Interfaces:**
- Consumes: `e2eRouter.sendStatusUpdate(...)` (`e2e_router.go:64-81`) — currently defined but **never called** (verified).
- Produces: `func (s *server) emitShimStatus()` — aggregates `s.sessions.list()` into a `StatusData{agent, model, sessionCount, usageUSD}` and sends it via the relay router so the iOS app's existing `agentStatus` ingestion (verified path B, `E2ERelayBridge.swift:133-141`) updates the fleet.

- [ ] **Step 1: Write the failing test**

```go
func TestEmitShimStatusCountsSessions(t *testing.T) {
	s := newServer(t.TempDir())
	s.sessions.register(ShimSession{ID: "a", Agent: "claudeCode", Status: "running"})
	s.sessions.register(ShimSession{ID: "b", Agent: "claudeCode", Status: "running"})
	got := s.shimStatusData("claudeCode")
	if got.SessionCount != 2 {
		t.Fatalf("sessionCount = %d, want 2", got.SessionCount)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd daemon/lancerd && go test -run TestEmitShimStatus ./...`
Expected: FAIL — `undefined: shimStatusData`.

- [ ] **Step 3: Implement `shimStatusData` + `emitShimStatus`**

```go
type relayStatusData struct {
	Agent        string  `json:"agent"`
	Model        string  `json:"model,omitempty"`
	SessionCount int     `json:"sessionCount"`
	UsageUSD     float64 `json:"usageUSD,omitempty"`
}

func (s *server) shimStatusData(agent string) relayStatusData {
	n := 0
	for _, ss := range s.sessions.list() {
		if ss.Agent == agent && ss.Status == "running" {
			n++
		}
	}
	return relayStatusData{Agent: agent, SessionCount: n}
}

func (s *server) emitShimStatus() {
	if s.e2e == nil {
		return
	}
	for _, agent := range []string{"claudeCode", "codex", "opencode"} {
		d := s.shimStatusData(agent)
		if d.SessionCount > 0 {
			s.e2e.sendStatusUpdate(d.Agent, d.Model, d.SessionCount, d.UsageUSD)
		}
	}
}
```
Match `sendStatusUpdate`'s real parameter list (`e2e_router.go:64`); adapt arg order/types if it differs.

- [ ] **Step 4: Run to verify it passes**

Run: `cd daemon/lancerd && go test -run TestEmitShimStatus ./...`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add daemon/lancerd/e2e_router.go daemon/lancerd/server.go
git commit -m "feat(lancerd): emit agentStatus for shim sessions over relay"
```

---

## Task 6: doctor — shim wrapper coverage check

**Files:**
- Modify: `daemon/lancerd/doctor.go:71-86`, `daemon/lancerd/doctor_test.go`

**Interfaces:**
- Produces: `func checkShimWrapper() checkResult` — `statusOK` if PATH `claude` resolves under `~/.lancer/bin`, `statusWarn` if the shim binary exists but PATH still points elsewhere, `statusFail` if not installed.

- [ ] **Step 1: Write the failing test**

```go
func TestCheckShimWrapper_NotInstalled(t *testing.T) {
	t.Setenv("PATH", t.TempDir()) // no claude here
	r := checkShimWrapper()
	if r.status != statusFail && r.status != statusWarn {
		t.Fatalf("status = %v, want fail/warn when shim absent", r.status)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd daemon/lancerd && go test -run TestCheckShimWrapper ./...`
Expected: FAIL — `undefined: checkShimWrapper`.

- [ ] **Step 3: Implement, following `checkAgentCLIs` (`doctor.go:189`) and `checkHooks` (`doctor.go:224`)**

```go
func checkShimWrapper() checkResult {
	p, err := exec.LookPath("claude")
	if err != nil {
		return checkResult{name: "shim wrapper", status: statusFail, detail: "claude not on PATH"}
	}
	home, _ := os.UserHomeDir()
	if strings.HasPrefix(p, filepath.Join(home, ".lancer", "bin")) {
		return checkResult{name: "shim wrapper", status: statusOK, detail: p}
	}
	return checkResult{name: "shim wrapper", status: statusWarn, detail: "claude resolves to " + p + " (shim not first on PATH)"}
}
```
Add `checkShimWrapper()` to the slice built in `collectDoctorResults()` (`doctor.go:71-86`).

- [ ] **Step 4: Run to verify it passes**

Run: `cd daemon/lancerd && go test -run 'TestCheckShimWrapper|TestDoctor' ./...`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add daemon/lancerd/doctor.go daemon/lancerd/doctor_test.go
git commit -m "feat(lancerd): doctor checks shim wrapper PATH coverage"
```

---

## Task 7: daemon wiring sanity (full build + test pass)

**Files:** none new — this task is the integration gate for the shared-file edits in Tasks 1–6.

- [ ] **Step 1: Full daemon test + vet**

Run: `cd daemon/lancerd && go vet ./... && go test ./...`
Expected: all PASS, no vet errors.

- [ ] **Step 2: Cross-build for the host targets the installer ships**

Run: `cd daemon/lancerd && GOOS=darwin GOARCH=arm64 go build -o /tmp/lancerd-darwin ./... && echo OK`
Expected: `OK`.

- [ ] **Step 3: Live smoke (host, manual)**

```bash
# Start the daemon, then in another shell:
~/.lancer/bin/lancerd daemon &
~/.lancer/bin/lancerd shim claude --version
tmux ls    # expect a lancer-XXXXXXXX session
```
Expected: `tmux ls` shows `lancer-<id>`; `lancerd doctor` shows the shim-wrapper check.

---

## Task 8: transcript watcher (read-only mirror of bare sessions)

**Files:**
- Create: `daemon/lancerd/transcript_watcher.go`
- Test: `daemon/lancerd/transcript_watcher_test.go`

**Interfaces:**
- Produces:
  - `type BareSession struct { SessionID, ProjectDir, CWD, TranscriptPath string; LastModified time.Time; Managed bool }`
  - `func scanTranscripts(projectsDir string) ([]BareSession, error)` — enumerate `<projectsDir>/*/*.jsonl`, read the FIRST and LAST line to extract `sessionId` + `cwd` (keys verified: every user/assistant line has `sessionId` and `cwd`).
  - `func classifyBare(b BareSession, running map[string]int) bool` — `Managed=true` when a tmux/lancer-parented process owns the session; else bare.

**Background (verified):** Layout is `~/.claude/projects/<encoded-project>/<sessionId>.jsonl`; `sessionId` (camelCase) appears on every message line and equals the filename UUID; some sessions are directory-only (handle gracefully). lancerd already counts these files (`agent_status_claude.go:25`) but never reads them. No `fsnotify` in repo — use a poll loop like `relayPairWatcher` (`relaypair.go:59`).

- [ ] **Step 1: Write the failing test over a temp projects dir**

```go
func TestScanTranscriptsExtractsSessionID(t *testing.T) {
	root := t.TempDir()
	proj := filepath.Join(root, "-Users-x-repo")
	os.MkdirAll(proj, 0o755)
	id := "114ca340-6508-4a10-aeb5-dcad9e1b6a71"
	line := `{"type":"user","sessionId":"` + id + `","cwd":"/Users/x/repo","message":{}}` + "\n"
	os.WriteFile(filepath.Join(proj, id+".jsonl"), []byte(line), 0o644)

	got, err := scanTranscripts(root)
	if err != nil || len(got) != 1 {
		t.Fatalf("got %d sessions err=%v", len(got), err)
	}
	if got[0].SessionID != id || got[0].CWD != "/Users/x/repo" {
		t.Fatalf("parsed %+v", got[0])
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd daemon/lancerd && go test -run TestScanTranscripts ./...`
Expected: FAIL — `undefined: scanTranscripts`.

- [ ] **Step 3: Implement `scanTranscripts` (read-only; never print message bodies)**

```go
func scanTranscripts(projectsDir string) ([]BareSession, error) {
	projDirs, err := os.ReadDir(projectsDir)
	if err != nil {
		return nil, err
	}
	var out []BareSession
	for _, pd := range projDirs {
		if !pd.IsDir() {
			continue
		}
		dir := filepath.Join(projectsDir, pd.Name())
		files, _ := os.ReadDir(dir)
		for _, f := range files {
			if f.IsDir() || filepath.Ext(f.Name()) != ".jsonl" {
				continue
			}
			path := filepath.Join(dir, f.Name())
			id, cwd := firstSessionMeta(path) // reads only the first line that has sessionId
			if id == "" {
				id = strings.TrimSuffix(f.Name(), ".jsonl")
			}
			info, _ := f.Info()
			out = append(out, BareSession{
				SessionID: id, ProjectDir: pd.Name(), CWD: cwd,
				TranscriptPath: path, LastModified: info.ModTime(),
			})
		}
	}
	return out, nil
}

func firstSessionMeta(path string) (id, cwd string) {
	f, err := os.Open(path)
	if err != nil {
		return "", ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<22)
	for sc.Scan() {
		var m struct {
			SessionID string `json:"sessionId"`
			CWD       string `json:"cwd"`
		}
		if json.Unmarshal(sc.Bytes(), &m) == nil && m.SessionID != "" {
			return m.SessionID, m.CWD
		}
	}
	return "", ""
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd daemon/lancerd && go test -run TestScanTranscripts ./...`
Expected: PASS.

- [ ] **Step 5: Add the 5s poll loop + surface bare sessions**

Add `func (s *server) startTranscriptWatcher()` modeled on `relayPairWatcher` (`relaypair.go:59`): every 5s call `scanTranscripts(<claudeDir>/projects)`, diff against last scan, and for new bare (`!Managed`) sessions emit a `sessionDiscovered` notification (Task 9 defines the iOS event). Call it from the daemon bootstrap where `startScheduler()` is started (`server.go:367`).

- [ ] **Step 6: Commit (stage only)**

```bash
git add daemon/lancerd/transcript_watcher.go daemon/lancerd/transcript_watcher_test.go daemon/lancerd/server.go
git commit -m "feat(lancerd): read-only transcript watcher for bare claude sessions"
```

> **Deferred to v1.x (out of scope per design):** the "Take over" action (kill bare PID + relaunch under tmux via `--resume`) and live send-keys into truly-bare sessions. The watcher delivers the read-only mirror only; "Take over" is Task-10 material once the read-only mirror is proven.

---

## Task 9: iOS — surface a discovered session in the fleet

**Files:**
- Modify: `Packages/LancerKit/Sources/LancerCore/Session.swift:3-17`, `Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift:272`
- Create: `Packages/LancerKit/Sources/AppFeature/SessionDiscovery.swift`
- Test: `Packages/LancerKit/Tests/LancerKitTests/SessionDiscoveryTests.swift`

**Interfaces:**
- Consumes: `DaemonEvent` stream (`DaemonChannel.events`, `LancerDProtocol.swift:272`), `FleetStore.add(_:)` (`FleetStore.swift:95`), `TmuxClient.attachOrCreate(name:)` (`TmuxClient.swift:30`).
- Produces:
  - `enum SessionOrigin: String, Codable, Sendable { case appInitiated, shimDiscovered, bareMirror }` on `Session`.
  - `case sessionDiscovered(SessionDiscoveredParams)` on `DaemonEvent`, where `SessionDiscoveredParams { sessionId: String; tmuxName: String?; agent: String?; cwd: String?; managed: Bool }`.
  - `@MainActor final class SessionDiscoveryCoordinator` with `func handle(_ params: SessionDiscoveredParams, on host: Host)` that builds a `FleetStore.Slot` (origin `.shimDiscovered` when `managed`, else `.bareMirror`) and calls `fleetStore.add`.

**Background (verified):** No "session appeared" event or "external" session concept exists today; `FleetStore.add` is the single UI insertion point. For `managed` (tmux) sessions the coordinator attaches via the existing `TmuxClient` path; for `bareMirror` it adds a read-only slot.

- [ ] **Step 1: Add the failing Swift test**

```swift
import XCTest
@testable import AppFeature
@testable import LancerCore

@MainActor
final class SessionDiscoveryTests: XCTestCase {
    func testDiscoveredManagedSessionBecomesShimOriginSlot() async {
        let store = FleetStore()
        let coord = SessionDiscoveryCoordinator(fleetStore: store)
        let params = SessionDiscoveredParams(sessionId: "abc123", tmuxName: "lancer-abc123",
                                             agent: "claudeCode", cwd: "/tmp", managed: true)
        coord.handle(params, on: .preview)
        XCTAssertEqual(store.slots.count, 1)
        XCTAssertEqual(store.slots.first?.session.origin, .shimDiscovered)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run (fast inner loop): `cd Packages/LancerKit && swift test --filter SessionDiscoveryTests`
Expected: FAIL — `SessionDiscoveryCoordinator` / `SessionOrigin` / `SessionDiscoveredParams` undefined.

- [ ] **Step 3: Add `SessionOrigin` to `Session`**

In `Session.swift`, add:
```swift
public enum SessionOrigin: String, Codable, Sendable {
    case appInitiated
    case shimDiscovered
    case bareMirror
}
```
Add `public var origin: SessionOrigin = .appInitiated` to the `Session` struct and to its initializer (default keeps existing call sites compiling).

- [ ] **Step 4: Add the `DaemonEvent` case + params**

In `LancerDProtocol.swift`, add `case sessionDiscovered(SessionDiscoveredParams)` to `DaemonEvent` and a `SessionDiscoveredParams` Codable struct; extend `DaemonEvent.decode(from:)` to map JSON-RPC method `"session.discovered"` → this case (mirror the `"agent.status"` mapping at `:293`).

- [ ] **Step 5: Implement `SessionDiscoveryCoordinator`**

```swift
#if os(iOS)
import LancerCore
import PersistenceKit

@MainActor
public final class SessionDiscoveryCoordinator {
    private let fleetStore: FleetStore
    public init(fleetStore: FleetStore) { self.fleetStore = fleetStore }

    public func handle(_ params: SessionDiscoveredParams, on host: Host) {
        let origin: SessionOrigin = params.managed ? .shimDiscovered : .bareMirror
        var session = Session(hostID: host.id)
        session.origin = origin
        session.tmuxName = params.tmuxName
        let slot = FleetStore.Slot(host: host, session: session)  // match Slot's real initializer
        fleetStore.add(slot)
    }
}
#endif
```
Adapt `FleetStore.Slot`'s real initializer (inspect `FleetStore.swift:95`); attach-or-create the tmux session for `.shimDiscovered` via `TmuxClient.attachOrCreate` when the slot's SSH session is live.

- [ ] **Step 6: Run the Swift test to verify it passes**

Run: `cd Packages/LancerKit && swift test --filter SessionDiscoveryTests`
Expected: PASS.

- [ ] **Step 7: Authoritative app-target build (catches `#if os(iOS)` + strict-concurrency)**

Use `mcp__XcodeBuildMCP__build_sim` (scheme `Lancer`, iPhone 17 Pro). Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit (stage only)**

```bash
git add Packages/LancerKit/Sources/LancerCore/Session.swift \
        Packages/LancerKit/Sources/LancerCore/LancerDProtocol.swift \
        Packages/LancerKit/Sources/AppFeature/SessionDiscovery.swift \
        Packages/LancerKit/Tests/LancerKitTests/SessionDiscoveryTests.swift
git commit -m "feat(ios): surface shim-discovered sessions in the fleet"
```

---

## Task 10: end-to-end verification

- [ ] **Step 1: Daemon suite green**

Run: `cd daemon/lancerd && go test ./...` → all PASS.

- [ ] **Step 2: iOS app-target build green**

`mcp__XcodeBuildMCP__build_sim` (Lancer / iPhone 17 Pro) → BUILD SUCCEEDED.

- [ ] **Step 3: Live host walk-through (manual, documented in PR description)**

1. `lancerd install` (installs shim), reload shell.
2. `lancerd daemon &`.
3. Type `claude` → confirm a `lancer-<id>` tmux session is created and `lancerd doctor` shows the shim check OK.
4. In the Lancer app (paired host), confirm the session appears as `.shimDiscovered` and the live block terminal attaches via tmux.
5. Stop the daemon, type `claude` again → confirm fail-open passthrough (real binary runs, no error).
6. Start a bare `claude` (bypass via `command claude`) → confirm it appears as a read-only `.bareMirror` after ≤5s.

---

## Spec coverage check

| Design requirement | Task |
|---|---|
| PATH shim + shell function + managed env var | Task 4 |
| `lancerd` receives spawn intent, registers session | Tasks 1, 3 |
| Launch real agent inside `tmux new-session -s lancer-<id>` | Task 2, 3 |
| Hooks active from byte zero | Global Constraints (file-based, already active) + Task 4 env |
| iOS sees session via relay + attaches via existing tmux path | Tasks 5, 9 |
| Transcript watcher: read-only mirror of bare sessions | Task 8 |
| Shim bypass / daemon-down → graceful fallback to real binary | Task 3 (`execRealBinary`), Task 10 step 5 |
| `lancer doctor` warns on broken wrapper coverage | Task 6 |
| Out of v1: live send-keys takeover of bare sessions; Agent SDK mode | Excluded (noted in Task 8) |

## Placeholder scan

- No `TBD`/`TODO` in steps; every code step shows code; every run step shows the command + expected output.
- Implementer notes flag the two spots needing a source cross-check (`procHandle` shape; `sendStatusUpdate`/`sockPath` exact signatures) rather than guessing — these are verification instructions, not placeholders.
