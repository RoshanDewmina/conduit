# Session Continuity Research Report

**Date:** 2026-06-16
**Author:** Architecture Research
**Scope:** Validate or challenge proposed A+B+C architecture for Lancer session continuity (adoption + resilience)

---

## Executive Summary

**A+B+C is the right v1 architecture, but A (shim wrapper) must be the sole hard dependency and B/C are read-only theatre without A. No competitor (Happy Coder, Omnara, Moshi) has solved bare-process adoption — they all require the agent to launch *through* their wrapper from byte zero. The tmux adoption path (C) works in practice (cmux, swarmux, tmux-mcp-agent all prove it) but carries fundamental security gaps (no tool-call interception, race conditions on concurrent input injection, control-character injection vectors) that make it acceptable only with a prominent "unguarded" indicator. The single biggest risk: the shim is fragile across shell environments (aliases, functions, `env` bypass, non-interactive shells) and requires a multi-layered strategy (PATH shim + shell function + managed env var) to be truly frictionless. The Claude Agent SDK (`@anthropic-ai/claude-agent-sdk`) is now mature enough to consider as an *alternative* to the PTY-spawn path for launched-through-lancer agents — it gives programmatic control without parsing terminal output, but sacrifices terminal compatibility. Recommended build order: (1) Shim + daemon-spawned PTY path, (2) transcript-based read-only mirror, (3) tmux adoption as optional opt-in with unguarded banner, (4) resilience via lancerd-launchd supervision + tmux for session persistence, deferring roaming to a future native protocol layer.**

---

## 1. Competitor Analysis: How They Solve (or Don't Solve) Adoption

### 1.1 Happy Coder (slopus/happy)

**Mechanism:** CLI wrapper. You run `happy` (or `happy gemini`, `happy codex`). Happy spawns the agent as a child process and communicates via PTY (interactive) OR the Claude Agent SDK (remote mode). A background daemon (`happy daemon`) manages sessions, WebSockets to Happy's server, and end-to-end encryption. There is NO mechanism to attach to an already-running bare `claude` / `codex` that was started outside Happy.

**Source:** https://slopus-happy-9.mintlify.app/components/cli  
**Source:** https://github.com/slopus/happy-cli (archived, merged into slopus/happy)  
**Source:** https://blog.denv.it/posts/im-happy-engineer-now/

**Key architectural details:**
- Daemon runs HTTP control server on `127.0.0.1` (local only). Lock files prevent multiple daemon instances.
- Uses Claude Code's `SessionStart` hook to discover session lifecycle: "The hook enables Happy to discover Claude's session ID dynamically, supporting both fresh starts and session resumption."
- Tracks "both daemon-spawned (remote) and terminal-spawned (local) sessions" — the latter means the daemon *detects* sessions started via `happy` in a terminal (not bare `claude`).
- **2026 migration:** Moved from PTY-wrapper to `@anthropic-ai/claude-agent-sdk` (commit `aa0014e`). This is significant — they chose SDK integration over terminal parsing for remote mode.
- Session restore: Uses `findCodexResumeFile(prevSessionId)` to find transcript files for resumption.

**Verdict for bare-process adoption:** Happy cannot adopt bare `claude` started outside its wrapper. It relies entirely on the A (shim) approach.

### 1.2 Omnara (YC S25)

**Mechanism:** Also a CLI wrapper. `pip install omnara && omnara`. Runs a headless daemon with outbound WebSocket. Supports local (your machine) and sandbox (Cloudflare container) execution. **2026 migration:** Deprecated the Claude-CLI-wrapper approach, moved to Claude Agent SDK for a "voice-first coding agent platform."

**Source:** https://www.ycombinator.com/launches/OCT-omnara-the-first-command-center-for-ai-agents-terminal-web-and-mobile  
**Source:** https://github.com/omnara-ai/omnara (README notes deprecation)  
**Source:** https://news.ycombinator.com/item?id=46991591

**Key details:**
- Earlier version parsed session files at `~/.claude/projects` and terminal output for mirroring.
- New architecture: built on Claude Agent SDK directly — no longer wraps the CLI.
- Cloud sandbox for offline resilience: "If your machine goes offline, Omnara can keep the agent running in the cloud so work continues."
- Workspace sync via git commits at each conversation turn.
- **"Continue Recent CLI Sessions"** feature: "Bring recent Claude Code or Codex context into Omnara" — read-only mirror of session transcripts, not live adoption.

**Verdict:** Even Omnara's "Continue Recent CLI Sessions" is transcript-based read-only mirror (our B), not live adoption. The SDK migration confirms the industry trend: integrating at the SDK level beats terminal output parsing.

### 1.3 Moshi (getmoshi.app)

**Mechanism:** Mobile SSH/Mosh terminal. NOT a session continuity tool per se. Moshi gives your phone a *real* terminal emulator. It relies on:
1. **Mosh** (UDP transport) for roaming resilience across network changes
2. **tmux** for process lifetime management ("The strongest setup is mosh for transport plus tmux for process lifetime")

**Source:** https://getmoshi.app/docs/terminal-sessions  
**Source:** https://mosh.org/  
**Source:** https://github.com/mobile-shell/mosh

**Key quotes:**
- "Mosh can survive network changes, but it does not keep the remote shell alive after the remote process exits. tmux handles that part."
- "Moshi does not run your code in Moshi's cloud and does not replace your agent CLI."
- Has `moshi-hook` for agent event notifications (SessionStart, approvals, etc.) — similar to Claude Code hooks.
- `MOSHI_CLIENT=1` env var so shell configs can detect Moshi connections.

**Verdict:** Moshi solves *resilience* (our problem #1) through Mosh + tmux, but solves *adoption* (problem #2) not at all — it's a real terminal; whatever you run in it runs normally. No wrapper, no adoption hooks.

### 1.4 Anyone solving bare-process adoption?

**No competitor does this.** Happy Coder tried to detect "terminal-spawned sessions" but this refers to sessions started via `happy` in a terminal (not bare `claude`). Omnara's "Continue Recent" is read-only. Moshi doesn't attempt it.

**The technical reality is clear: you cannot retroactively gain PTY-level control of a process you did not spawn.** The only options are:
1. Wrapper/shim (A) — launch under your control from byte zero
2. Transcript monitoring (B) — read-only mirror
3. Multiplexer injection (C) — best-effort r/w via tmux

---

## 2. Technical Options for Adopting an Already-Running Process

### 2.1 tmux/screen/zellij pipe-pane + send-keys (feasible, production-proven)

**How it works:**
- `tmux pipe-pane -t <target> -o 'command'` redirects pane output to a process's stdin.
- `tmux send-keys -t <target> 'command' Enter` injects keystrokes into the pane.
- `tmux capture-pane -t <target> -p -S -<lines>` reads visible pane content.
- `tmux list-panes -a -F '{format}'` discovers all panes.

**Evidence of production use:**
- **cmux** (manaflow-ai/cmux): Full-featured terminal multiplexer with Claude Code/Codex session restore. Uses env-var-based wrapper shim (`CMUX_CLAUDE_WRAPPER_SHIM`) immune to PATH/function shadowing. 5900+ commits, active 2026. https://github.com/manaflow-ai/cmux
- **tmux-mcp-agent**: Exposes tmux as an MCP server for AI agents to control remote servers through jump hosts. https://github.com/quink-black/tmux-mcp-agent
- **swarmux**: Multi-agent system using `tmux send-keys -l` for literal text, separate Enter key. https://github.com/6missedcalls/swarmux
- **tmux-sane**: High-level primitives preventing AI agents from making unreliable keystroke-level decisions. https://github.com/ryancnelson/tmux-sane

**Key issue raised in Claude Code issue #60943:** "The `tmux send-keys` path is brittle for exactly the reason you name: pty injection corrupts in-flight input from a human typing in the same pane. But there is a second failure mode: even when no human is typing, two agents injecting into the same pane concurrently can produce interleaved input." https://github.com/anthropics/claude-code/issues/60943

**Verdict:** Works for read/write control, but NO tool-call interception, no approval firewall, race conditions on concurrent input. Acceptable for unguarded/best-effort mode only.

### 2.2 reptyr (Linux-only, blocked on macOS)

**How it works:** Uses `ptrace` syscall to detach process from old terminal and attach to new one. Changes controlling terminal, dup2s new terminal fds.

**Restrictions:**
- Linux only. FreeBSD partial. **macOS: not supported.** The author states: "A port to other operating systems may be technically feasible, but requires significant low-level knowledge of the relevant platform." https://github.com/nelhage/reptyr/
- Requires `ptrace` access: `kernel.yama.ptrace_scope = 0` (disabled by default on Ubuntu 10.10+).
- Cannot attach to setuid binaries or daemons already detached from terminal.

**macOS SIP analysis:** macOS System Integrity Protection blocks `task_for_pid()` for protected processes. Hardened Runtime further restricts process introspection. The reptyr approach is effectively **blocked on macOS without disabling SIP**, which is unacceptable for a production tool. https://specterops.io/blog/2025/08/21/armed-and-dangerous-dylib-injection-on-macos/

**Verdict:** Non-starter for macOS. Do not depend on this.

### 2.3 ptrace/dup2 fd-stealing (macOS infeasible per above)

Same restrictions as reptyr, plus SIP + Hardened Runtime. Detailed analysis from SpecterOps (Aug 2025) confirms this is locked down: `task_for_pid()` blocked, `DYLD_INSERT_LIBRARIES` stripped for system binaries, `CS_DEBUGGED` required for unsigned page execution. https://specterops.io/blog/2025/08/21/armed-and-dangerous-dylib-injection-on-macos/

**Verdict:** Do not pursue.

### 2.4 PTY-proxy / pre-loaded wrapper (the shim approach — A)

Competing industry consensus: every player uses wrappers. Happy Coder, Omnara, cmux all install a `claude` wrapper that routes through their daemon.

**cmux's approach is the most robust studied:**
- Installs a shell function that wraps `claude` (and other agents).
- Adds a fallback managed env var `CMUX_CLAUDE_WRAPPER_SHIM` that's inherited by every descendant shell regardless of PATH/function shadowing.
- The wrapper injects `--settings` flags to wire Claude Code hooks.
- Falls back to bare `claude` if the shim path is stale/broken.
- Wraps in `/bin/sh -c` for non-POSIX shells (fish, tcsh).
- Handles `$SHELL -lic` restoration. https://github.com/manaflow-ai/cmux/pull/5721

**Verdict:** This is the robust path. Match cmux's sophistication.

### 2.5 Reading agent transcript files for read-only mirror (B)

All three major agents persist session transcripts to disk:

| Agent | Transcript Location | Format |
|-------|-------------------|--------|
| Claude Code | `~/.claude/projects/<encoded-cwd>/*.jsonl` | JSONL | 
| Codex CLI | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | JSONL |
| Gemini CLI | `~/.gemini/tmp/<project_hash>/` (checkpoints), `--session-file <path>` | JSON |

**Sources:**
- https://code.claude.com/docs/en/sessions — "Transcripts are stored as JSONL at `~/.claude/projects/<name>/*.jsonl`"
- https://inventivehq.com/knowledge-base/openai/how-to-resume-sessions — "Codex CLI stores all session transcripts as JSONL files under ~/.codex/sessions/YYYY/MM/DD/"
- https://github.com/google-gemini/gemini-cli/blob/HEAD/docs/reference/commands.md — Gemini checkpoint location

**Important nuance:** Claude Code session files use a directory name derived from the absolute working directory with every non-alphanumeric character replaced by `-`. The SDK provides `listSessions()` and `getSessionMessages()` for programmatic access. https://code.claude.com/docs/en/agent-sdk/sessions

**The "take over" affordance challenge:** Reading transcript gives you the conversation history. To actually take over, you need to either:
- Launch a new session with `--resume <session-id>` (works if the original process has been stopped)
- Or attach via tmux (C) if the process is still running

**The cmux approach confirms B+C fusion:** Claude Code session restore uses the `transcript_path` from the SessionStart hook as the source of truth, and only offers resume once the transcript file exists and is non-empty. https://github.com/manaflow-ai/cmux/pull/4079

---

## 3. Claude Code, Codex CLI, Gemini CLI: First-Class External Control?

### 3.1 Claude Code

**Key finding:** Claude Code now has a mature **Agent SDK** (`@anthropic-ai/claude-agent-sdk`) that provides programmatic control without PTY/terminal parsing. This is a game-changer that the proposal doesn't discuss.

**SDK capabilities:**
- Python and TypeScript packages
- `query()` method for programmatic agent invocation
- `SessionStore` adapter for cross-host session persistence (S3, Redis, Postgres)
- Tool approval callbacks (approve/deny tool calls programmatically)
- Hooks: `SessionStart`, `SessionEnd`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, etc.
- `listSessions()`, `getSessionMessages()` for transcript enumeration
- `resume <session-id>` for continuing conversations

**Sources:**
- https://code.claude.com/docs/en/headless — "The Agent SDK gives you the same tools, agent loop, and context management that power Claude Code"
- https://code.claude.com/docs/en/agent-sdk/sessions — Resume/fork across hosts
- https://code.claude.com/docs/en/agent-sdk/session-storage — SessionStore adapters
- https://code.claude.com/docs/en/agent-sdk/hooks — "Hooks are callback functions that run your code in response to agent events"

**What's missing (confirmed by open issues):**
- **No IPC socket/server mode.** Claude Code has no `--listen` flag or control socket.
- **No external wake mechanism.** Issue #60943 confirms "there is no way for an external process to trigger a new turn in a running Claude Code interactive session without typing into the terminal via `tmux send-keys` or similar pty injection." https://github.com/anthropics/claude-code/issues/60943
- SessionStart fires POST to daemon via hook. **Happy Coder and cmux both exploit this.**

**Hooks architecture for lancerd integration:**
```
SessionStart → POST http://127.0.0.1:<lancerd-port>/hook
```
This is how Happy discovers session IDs dynamically. Lancerd should register itself as a Claude Code HTTP hook (`.claude/settings.json` or `hooks/hooks.json`).

### 3.2 Codex CLI

**Remote control option:**
- `codex app-server --listen ws://IP:PORT` — starts a WebSocket server for external control
- `codex --remote ws://host:port` — connect TUI to app server
- `codex --remote unix://PATH` — Unix socket option
- `codex exec --json` for headless with session ID
- `codex resume <session-id>` or `codex resume --last`
- Sessions at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`

**Sources:**
- https://developers.openai.com/codex/cli/reference — "Use `--remote ws://host:port` to connect the TUI to an app server"
- https://github.com/openai/codex/issues/14544 — Exec session resume discriminator
- https://deepwiki.com/openai/codex/4.2-headless-execution-mode-(codex-exec)

**Significance:** Codex's app server mode is the closest thing to a first-class external control mechanism among all three agents. This could be a cleaner path than tmux injection for Codex sessions.

### 3.3 Gemini CLI

**Resume controls:**
- `gemini --resume` (resume latest), `gemini --resume <id>`, `gemini --resume --session-file <path>`
- Export: `/export-session <filename>` or `/chat share <filename>.json`
- Headless: `gemini -p "prompt" --output-format json` (includes session ID since PR #14504)
- Checkpoints: `~/.gemini/tmp/<project_hash>/`

**Sources:**
- https://github.com/google-gemini/gemini-cli/blob/HEAD/docs/cli/headless.md
- https://geminicli.com/docs/cli/session-management/ — "You can resume a previous session to continue the conversation with all prior context restored"
- https://github.com/google-gemini/gemini-cli/pull/26514 — Session export/import feature
- https://github.com/google-gemini/gemini-cli/issues/14435 — Session ID in JSON output

**No SDK for Gemini CLI** (as of June 2026) — it's a Node.js CLI, not a library with programmatic hooks.

---

## 4. Shell Shim Robustness Analysis (Question 3)

### Failure Modes Identified

| Failure Mode | Impact | Mitigation |
|---|---|---|
| User's own alias: `alias claude='nocorrect claude'` | Wrapper bypass | Shell function approach (bash functions shadow aliases when same name) |
| User's own function: `claude() { ... }` | Function can shadow wrapper | Managed env var (cmux's approach) |
| `env claude ...` bypass | Skips shell functions/aliases | Only solvable at the PATH level (shim binary, not function) |
| Non-interactive shell | Aliases not expanded | PATH-level shim binary + shell function both needed |
| IDE/another tool spawning `claude` | Bypasses wrapper entirely | Need shim at binary level (rename original, put wrapper in PATH) |
| Multiple shells, different configs | Inconsistent behavior | Multi-shell support (zsh, bash, fish, tcsh) |
| PATH ordering after package install | Wrapper gets shadowed | Install shim to a dedicated bin dir, verify precedence |
| `$SHELL -lic` reload | Wrapper path stale | `[ -x "$shim" ]` guard with PATH fallback |

### The Two-Layer Strategy (proven by cmux)

1. **PATH-level shim binary** (`~/bin/claude` → actual `claude` at `/somewhere/bin/claude`): covers non-interactive shells, `env` bypass, IDE invocations.
2. **Shell function** (installed in `.zshrc`/`.bashrc`): takes priority over aliases, can do richer logic.
3. **Managed env var** (`LANCER_CLAUDE_WRAPPER_SHIM`): inherited by all descendants, immune to PATH clobber. Used as master token that the function/binary resolves.

**Source:** cmux approach validated at https://github.com/manaflow-ai/cmux/pull/5721

### Recommended lancerd Shim Implementation

```
~/.local/bin/claude  →  lancer-shim (executable)
~/.config/lancer/shell-integration.zsh  →  shell function + alias setup
~/.config/lancer/shell-integration.bash
~/.config/lancer/shell-integration.fish

# On install:
# 1. Rename real claude to claude.real
# 2. Place lancer-shim as claude in PATH
# 3. Source shell integration (handled by the shim itself ala rbenv/pyenv)
# 4. Set LANCER_CLAUDE_WRAPPER_SHIM in terminal env (Ghostty/Warp/terminal profiles)
```

The shim executable should `exec` the real binary with `--settings` flags appended for hook wiring, and communicate the spawning PID to lancerd.

---

## 5. Resilience Patterns (Question 5)

### Process Detachment

| Method | Process survives parent exit? | Can reattach? | macOS native? |
|--------|-------------------------------|---------------|---------------|
| `nohup` | Partial (SIGHUP ignored, but still in same process group) | No | Yes |
| `disown` | Partial (shell won't kill, but same session) | No | Yes |
| `setsid` | **Yes** (new session, no controlling terminal) | No | Yes |
| `launchd` | **Yes** (supervised, automatic restart) | No | **Yes (native)** |
| `systemd-run --scope` | Yes (new cgroup) | No | No |
| **tmux** | Yes (server owns the PTY) | **Yes** | Yes |
| dtach/abduco | Yes | **Yes** | Yes |
| `setsid + tmux` | Yes + Yes | **Yes** | Yes |

**Key insight from Unix process lifecycle analysis:** `nohup` only tells the process to ignore SIGHUP, but it remains in the same session and process group. When the shell exits, it sends SIGHUP to the *entire process group*. `setsid` creates a new session, fully detaching from the original terminal. https://blog.margrop.net/en/post/setsid-daemon-process-survival/

**For lancerd-spawned agents:** lancerd already manages the child process. The resilience question is what happens when lancerd restarts:
1. **Option 1: Re-parent to launchd.** Use `launchd` plist with `KeepAlive` and `RunAtLoad`. On restart, lancerd finds existing agent processes via PID file, re-attaches via tmux sockets.
2. **Option 2: Run inside tmux.** Spawn the agent inside a named tmux session (`lancer-<session-id>`). Reattach by looking up tmux sessions on lancerd restart.
3. **Option 3: SDK mode.** The agent runs "inside" lancerd's process as a client of the Agent SDK — no PTY persistence needed.

**recommended for v1:** Use tmux as the session container for lancerd-spawned agents. This gives:
- Session survives lancerd restart
- Can attach/detach without losing terminal state
- Works identically for the adoption path (C) — if user is already in tmux, we're already compatible

### Transport Resilience (Roaming)

| Protocol | Roaming | Survives sleep | Survives IP change | Encryption | Maturity |
|----------|---------|----------------|-------------------|------------|----------|
| **SSH** | No | No (TCP timeout) | No | Yes | Battle-tested |
| **Mosh** | Yes | Yes | Yes | AES-128-OCB | 10+ years |
| **Eternal Terminal** | No (TCP) | Yes (reconnect) | No | AES | Production |
| **neosh (QUIC)** | Yes | Yes | Yes | TLS 1.3 | Young |
| **Tailscale/WireGuard** | Yes | Yes | Yes | WireGuard | Battle-tested |

**Mosh** is the most proven mobile roaming protocol. It uses the State Synchronization Protocol (SSP) over UDP: "the client sends datagrams to the server with increasing sequence numbers, including a heartbeat at least once every three seconds. Every time the server receives an authentic packet from the client with a sequence number higher than any it has previously received, the IP source address of that packet becomes the server's new target." https://mosh.org/

**Eternal Terminal** (TCP with reconnect) is simpler but less robust on mobile: "ET uses TCP, so you need an open port on your server." https://eternalterminal.dev/

**Recommendation:** **Don't build transport resilience yourself.** You already have Tailscale tunnel (WireGuard) in the architecture. WireGuard handles roaming at the network layer — the phone's Tailscale IP doesn't change as you switch networks. If the phone reconnects to Tailscale, the tunnel re-establishes and the SSH or relay connection survives. This makes a custom QUIC/roaming layer premature for v1.

**However**, the *transport* resilience is separate from *session* resilience. Even with a perfect tunnel, if the SSH session inside times out or the lancerd-streaming WebSocket breaks, you need state sync:
- For read-only: the stream can resume from last-known cursor position
- For input: lancerd must buffer keystrokes until reconnect

**Recommendation for v1:** TCP/Tailscale tunnel + lancerd internal buffering for transport drop. Defer Mosh/Eternal Terminal integration to v2. The tmux-based session persistence already solves the harder problem (process survival).

---

## 6. Security Implications of Adoption/Injection Paths

### 6.1 tmux send-keys Injection Risks

**Established attack surface (multiple CVEs and security fixes in 2025-2026):**

1. **Control character injection:** `tmux send-keys -l` sends literal characters, including `\n` which executes as Enter. PR #2323 in oh-my-claudecode (Apr 2026) sanitizes control characters: "A newline would execute as Enter in the target pane shell. `execFile` prevents shell injection but `-l` flag sends literal keystrokes including `\n` as Enter." https://github.com/Yeachan-Heo/oh-my-claudecode/pull/2323

2. **`send-keys` command injection:** PR #2028 (Mar 2026) blocks `send-keys` in worker bash commands: "A team worker could use `tmux send-keys -t 'command' Enter` to inject commands into leader or sibling worker panes." https://github.com/Yeachan-Heo/oh-my-claudecode/pull/2028

3. **Shell command injection via tmux commands:** Using `run-shell` instead of `send-keys` can execute arbitrary shell commands in the tmux server process. https://github.com/flplima/tmuxy/blob/main/docs/SECURITY.md

4. **Race condition on concurrent input:** Two senders injecting into the same pane concurrently can produce interleaved input that parses as a single malformed command. No lock mechanism exists. https://github.com/anthropics/claude-code/issues/60943

### 6.2 The Approval Firewall Gap for Adopted Sessions

This is the critical architectural point: **tmux-adopted sessions bypass lancerd's approval firewall entirely.**

- Daemon-spawned sessions: lancerd owns the PTY → can parse OSC-133 markers, intercept tool calls, route approvals.
- tmux-adopted sessions: lancerd writes to `send-keys` and reads via `capture-pipe` → has NO visibility into tool calls, NO ability to block commands.

**Impact:** An adopted bare session could execute `rm -rf /` and lancerd couldn't stop it. The approval firewall is a no-op.

**Mitigation strategies:**
1. **Prominent "unguarded" indicator** — red banner: *"This session was started outside Lancer. Approvals, audit, and risk scoring are not available."*
2. **Never auto-approve anything in adopted sessions.** Even simple operations should prompt on phone.
3. **Audit log the adoption event** — "Session <id> adoption via tmux at <timestamp>. Unguarded mode."
4. **Consider a restricted mode** — adopted sessions can only send text and read output, no sudo, no destructive commands. (Limited enforceability through tmux.)

### 6.3 Shim Security

The shim approach is **more secure** than adoption, because:
- Session starts under lancerd's PTY from byte zero
- All tool calls go through the approval firewall
- The audit log is complete
- No injection race conditions

**Risk:** If the shim is bypassed (user runs `\claude` or `env claude`), the user gets a bare session invisible to Lancer. **This is a UX problem, not a security vulnerability** — the user chose to bypass. Surface the "you're running outside Lancer" check in the shim when possible, but accept the limitation.

---

## 7. Verdict and Build Order

### Is A+B+C the right v1 architecture?

**Yes, with critical caveats:**

| Component | Value | Effort | Risk | Must Have for v1? |
|-----------|-------|--------|------|-------------------|
| **A: Shim** | **High** — full control, approvals, audit | Medium | Medium (shell compatibility) | **Yes** |
| **B: Read-only transcripts** | Medium — visibility for bare sessions | Low | Low | **Yes** (cheap, high perceived value) |
| **B→Takeover affordance** | High — lets user convert read-only to controlled | Medium | Low | **Yes** (killer feature) |
| **C: tmux adoption** | Medium — r/w control of bare sessions | Medium | **High (no approval firewall)** | **No — ship as Beta** |
| **Claude Agent SDK** | **Very High** — full programmatic control | Medium | Low (vendor dependency) | **Strongly consider** |

### Single Biggest Risk

**The shim will fail silently for some users** due to shell environment complexity. Non-interactive shells, `env` bypass, `$SHELL -lic` path rebuilding, and user-installed alias managers will cause support issues. **Mitigation:** Implement the three-layer strategy (shim binary + shell function + managed env var) as cmux has done, and add a `lancer doctor` command to diagnose wrapper coverage.

### Additional Recommendations Beyond A+B+C

1. **Integrate Claude Agent SDK as a first-class launch mode.** For sessions started *through* Lancer, offer both "terminal" (PTY with OSC-133 parsing) and "SDK" (programmatic, no terminal UI, full approval control). The SDK gives you structured tool calls, permission callbacks, and session persistence for free. Happy Coder already migrated to this model.

2. **Don't build transport resilience (Mosh/QUIC) yet.** Tailscale/WireGuard already handles roaming at the network layer. Focus on process persistence (tmux) and application-level buffering (lancerd caches stream until client reconnects).

3. **The "take over" affordance should use `claude --resume` (new process), not tmux injection.** When a user taps "Take Over" on a read-only transcript session:
   - Stop the old bare session (or leave it running)
   - Launch a new session under lancerd with `claude --resume <session-id>`
   - This gives full approval firewall, audit, and terminal streaming
   - Works across all three agents (all support `--resume`)

4. **Session discovery needs a reconnection protocol for lancerd.** When the phone reconnects after being offline:
   - lancerd enumerates tmux sessions, finds running agents
   - Reads transcript files for session summaries
   - Pushes "These sessions are still running — continue from phone?" to the app

### Recommended Build Order

```
Phase 1 (v1 MVP):
  └── A: Shim wrapper for claude (PATH binary + shell function + env var)
  └── lancerd PTY spawn path (OSC-133 parsing, approval firewall, streaming)
  └── B: Transcript watcher (poll ~/.claude/projects/, surface recent sessions)
  └── "Take Over" via --resume (stop old, start new with full control)
  └── Resilience: tmux container + launchd KeepAlive for lancerd

Phase 2 (v1.x):
  └── C: tmux adoption (pipe-pane + send-keys, "unguarded" indicator)
  └── Claude Agent SDK integration for remote-mode sessions
  └── Session store adapter (cross-host resume)
  └── Codex WS app-server discovery (codex app-server --listen)
  └── Gemini --session-file import

Phase 3 (v2):
  └── Native roaming protocol (QUIC or Mosh integration)
  └── Multi-agent session management
  └── Cloud tier (offload agent to cloud when host sleeps)
```

---

## Sources Index

| Topic | Source URL |
|-------|-----------|
| Happy Coder CLI architecture | https://slopus-happy-9.mintlify.app/components/cli |
| Happy Coder session management | https://slopus-happy-9.mintlify.app/guides/session-management |
| Happy Coder GitHub (deprecated CLI) | https://github.com/slopus/happy-cli |
| Happy Coder SDK migration commit | https://github.com/slopus/happy/commit/aa0014e501fb7263ab4f80a2447e65a0d5079f5a |
| Happy Coder agent package | https://github.com/slopus/happy/tree/main/packages/happy-agent |
| Omnara YC launch | https://www.ycombinator.com/launches/OCT-omnara-the-first-command-center-for-ai-agents-terminal-web-and-mobile |
| Omnara GitHub (deprecated) | https://github.com/omnara-ai/omnara |
| Omnara HN discussion | https://news.ycombinator.com/item?id=46991591 |
| Omnara remote sandboxing | https://docs.omnara.com/remote-sandboxing |
| Moshi terminal sessions | https://getmoshi.app/docs/terminal-sessions |
| Mosh official site | https://mosh.org/ |
| Mosh GitHub | https://github.com/mobile-shell/mosh |
| Mosh academic paper | https://web.mit.edu/keithw/www/Winstein-Balakrishnan-Mosh.pdf |
| reptyr GitHub | https://github.com/nelhage/reptyr/ |
| reptyr blog post | https://blog.nelhage.com/2011/01/reptyr-attach-a-running-process-to-a-new-terminal/ |
| macOS injection analysis (SpecterOps) | https://specterops.io/blog/2025/08/21/armed-and-dangerous-dylib-injection-on-macos/ |
| Claude Code headless mode | https://code.claude.com/docs/en/headless |
| Claude Code sessions docs | https://code.claude.com/docs/en/sessions |
| Claude Code Agent SDK sessions | https://code.claude.com/docs/en/agent-sdk/sessions |
| Claude Code session storage | https://code.claude.com/docs/en/agent-sdk/session-storage |
| Claude Code hooks reference | https://code.claude.com/docs/en/hooks |
| Claude Code Agent SDK hooks | https://code.claude.com/docs/en/agent-sdk/hooks |
| Claude Code hooks guide | https://code.claude.com/docs/en/hooks-guide |
| Claude Code hooks integration | https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/ |
| Claude Code wake signal issue | https://github.com/anthropics/claude-code/issues/60943 |
| Codex CLI reference | https://developers.openai.com/codex/cli/reference |
| Codex CLI features | https://developers.openai.com/codex/cli/features |
| Codex exec mode (DeepWiki) | https://deepwiki.com/openai/codex/4.2-headless-execution-mode-(codex-exec) |
| Codex resume exec sessions issue | https://github.com/openai/codex/issues/14544 |
| Gemini CLI headless mode | https://google-gemini.github.io/gemini-cli/docs/cli/headless.html |
| Gemini CLI session management | https://geminicli.com/docs/cli/session-management/ |
| Gemini CLI session export PR | https://github.com/google-gemini/gemini-cli/pull/26514 |
| Gemini CLI session ID issue | https://github.com/google-gemini/gemini-cli/issues/14435 |
| cmux GitHub | https://github.com/manaflow-ai/cmux |
| cmux wrapper shim (env var approach) | https://github.com/manaflow-ai/cmux/pull/5721 |
| cmux Claude integration | https://manaflow-ai-cmux.mintlify.app/integrations/claude-code |
| cmux transcript verification | https://github.com/manaflow-ai/cmux/pull/4079 |
| cmux Codex wrapper issue | https://github.com/manaflow-ai/cmux/issues/4420 |
| cmux cwd-drift fix | https://github.com/manaflow-ai/cmux/pull/5154 |
| tmux-mcp-agent | https://github.com/quink-black/tmux-mcp-agent |
| swarmux | https://github.com/6missedcalls/swarmux |
| tmux-sane | https://github.com/ryancnelson/tmux-sane |
| tmux audit security (hoop.dev) | https://hoop.dev/blog/auditing-and-accountability-in-tmux-2/ |
| tmux sec vuln (oh-my-claudecode PR #2028) | https://github.com/Yeachan-Heo/oh-my-claudecode/pull/2028 |
| tmux control char sanitize (PR #2323) | https://github.com/Yeachan-Heo/oh-my-claudecode/pull/2323 |
| tmux injection sanitization (ntm) | https://github.com/Dicklesworthstone/ntm/commit/074005cae122c5eaf16a97e569d2387cd4d3349b |
| tmux security (tmuxy) | https://github.com/flplima/tmuxy/blob/main/docs/SECURITY.md |
| surrogate tool (tmux injection guard) | https://github.com/rawwerks/surrogate |
| Eternal Terminal | https://eternalterminal.dev/ |
| ET GitHub | https://github.com/MisterTea/EternalTerminal/ |
| neosh (QUIC terminal) | https://github.com/plucury/neosh |
| mish (Rust mosh over QUIC) | https://github.com/amedeedaboville/mish |
| shpool (tmux alternative) | https://github.com/shell-pool/shpool/ |
| dtach | https://github.com/crigler/dtach/ |
| abduco | https://github.com/martanne/abduco |
| Unix process lifecycle (setsid) | https://blog.margrop.net/en/post/setsid-daemon-process-survival/ |
| Shell alias shadowing | https://www.baeldung.com/linux/alias-run-shadowed-command |
| Alias wrapper recursion fix (mise) | https://github.com/jdx/mise/pull/8560 |
| alias-scripts tool | https://github.com/iannuttall/alias-scripts |
