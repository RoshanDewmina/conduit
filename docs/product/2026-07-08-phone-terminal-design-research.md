# Phone-native terminal, no separate SSH hop — competitor research (2026-07-08)

**Status:** partial. Only the web-research lane completed before the orchestrating
session was interrupted. The three planned codebase deep-dives — **R1 Orca**,
**R2 Happier**, **R3 Omnara/lfg/agent-native** — were dispatched as background
`cursor-agent` (Composer 2.5) processes but died with a process restart before
returning output; their output files are empty. The repos are still cloned at
`research-repos/{orca,happier,omnara,lfg,agent-native}` pending a decision on
whether to re-run them (see open question at the end).

## Ask

How do comparable products (Orca, Happy Coder, Omnara, T3 Code, Conductor,
GitHub Agent HQ, Codex remote, classic SSH-terminal tools) give a phone a live
terminal against a dev machine **without a dedicated SSH hop** — the pattern
Lancer wants to avoid (A2 just deleted the phone-as-SSH-client stack). The
replacement design is a `lancerd`-hosted PTY multiplexed over the already-paired
E2E relay connection.

## Findings (web lane only — codebase lanes incomplete, see Status)

### 1. T3 Code (Theo Browne / t3dotgg)
Desktop-only orchestration UI on top of coding-agent CLIs (currently Codex,
Claude Code "coming soon"). No mobile client, no terminal-over-websocket
feature — not a comparable for the phone-terminal ask.

### 2. Happy Coder (happy.engineering)
CLI wrapper + relay + mobile app. CLI encrypts session data client-side,
relay only forwards opaque blobs. Transport: WebSocket, explicitly
peer-to-peer ("no primary/secondary, two windows into the same session").
Reconnect: relay buffers blobs while the phone is offline; phone "catches up"
on reconnect — this is **message-log replay, not raw PTY byte-stream replay**.
Exact wire framing and resume semantics live only in the relay source
(not fetched in this pass).

### 3. Omnara (YC S25)
Not a PTY-mux at all. A CLI wrapper parses Claude Code's own session file
(`~/.claude/projects`) plus terminal output, then streams **normalized
structured messages** (diffs, logs, approve/reject) over SSE to web/mobile —
clients render structured UI, not an xterm surface. Session can migrate to a
cloud sandbox if the laptop drops.

### 4. Conductor / Conductor Cloud + wider ecosystem survey
Conductor: macOS app running agents in per-task git-worktree sandboxes, local
terminal/diff/review UI; "Conductor Cloud" moves agents into hosted sandboxes.
Broader taxonomy from a DEV Community survey of how people actually get phone
access to a terminal today:
- SSH over Tailscale (or Mosh) + reattach a persistent tmux.
- Browser terminal proxy (ttyd-style) — no SSH setup, just a URL.
- **CodeAgentsMobile** — SwiftUI iOS client, connects **over SSH directly**
  (can even provision a cloud VM) — exactly the pattern Lancer is moving away from.
- Agent Deck — session-manager TUI, not itself a mobile PTY transport.

### 5. Terragon (shut down Jan 2026, OSS snapshot remains)
Cloud-sandboxed background-agent orchestrator; task status/output streamed to
a web dashboard, mobile as a thin client of the same feed. No PTY-on-phone
story — "watch cloud-agent progress," not "run my local terminal from my phone."

### 6. OpenAI Codex app-server — the closest precedent
Single JSON-RPC 2.0 "app-server" is the source of truth; TUI, VS Code
extension, desktop app, and ChatGPT-mobile Codex surface are all thin clients
of the same protocol.
- **PTY-backed exec sessions**: client sets `tty: true` on start, gets a
  `processId`, drives it via `command/exec/write`, `command/exec/resize`,
  `command/exec/terminate` — PTY control modeled as **explicit RPC verbs**,
  not a raw byte pipe.
- **Remote transport**: app-server can bind a WebSocket listener for
  "Remote TUI mode," authenticated via a bearer capability token checked with
  constant-time SHA-256 comparison, expected behind TLS.
- **Mobile pairing**: ChatGPT mobile's Codex surface pairs via **QR code**
  shown during a host-side "remote access" enable flow; session traffic then
  rides the same authenticated JSON-RPC/WebSocket channel — no separate
  SSH tunnel per session.

This is architecturally the closest match to what Lancer wants: one
authenticated channel, JSON-RPC-shaped control messages, explicit
resize/write/terminate verbs instead of an opaque byte stream.

### 7. GitHub Agent HQ
"Consistent interface across GitHub, VS Code, mobile, and CLI" for
directing/monitoring agents. No published phone-native terminal/PTY transport
— reads as task/PR-level orchestration surfaced on mobile, not terminal streaming.

### 8. Blink Shell + Tailscale + Mosh (baseline contrast)
iOS Mosh/SSH client; with Tailscale, upgrades SSH to Mosh for roaming
resilience. This is the exact pattern Lancer wants to avoid: a **second,
dedicated transport connection** parallel to the app's own control channel,
with its own auth and reconnection logic.

### 9. Underlying transport patterns
- **tmux control mode** (`tmux -CC`): server owns all session state
  (scrollback, pane/window IDs) indefinitely; detach/reattach — even from a
  different machine — resumes with scrollback intact. `@id`s never reused for
  the server's lifetime, so a reconnecting client can reliably re-sync.
  **Strongest model for reconnect-and-resume.**
- **Mosh SSP**: two independent State Synchronization Protocol instances over
  UDP — client→server is ordered ("keystrokes typed"), server→client is
  best-effort and always converges on the latest screen state rather than
  replaying every intermediate frame. Roaming is stateless: any authenticated
  packet with a higher sequence number updates the server's return address —
  survives NAT/IP changes with no explicit reconnect handshake. AES-128-OCB3.
- **ttyd / gotty / wetty**: PTY over WebSocket to xterm.js. ttyd prefixes each
  WS frame with a single message-type byte (input/resize/pause-resume/JSON
  control) so text and control share one connection unambiguously. Weak
  reconnect story — a dropped socket generally loses in-flight output;
  persistence (if any) comes from tmux/screen underneath, not the tool itself.
- **VS Code Remote** (SSH/Tunnels): a "VS Code Server" runs on the remote
  host; local UI talks over a multiplexed RPC channel. Terminal is one
  RPC-addressed channel among many (file ops, extension host, debug) inside
  that same connection — not a separate socket. Wire-level pty-host format
  isn't publicly documented.

## Transport-pattern summary

| Product | Where the PTY/process lives | Transport | Reconnect / replay |
|---|---|---|---|
| Happy Coder | Dev machine | WebSocket, E2E-encrypted blobs via relay, peer-to-peer | Relay buffers offline blobs; phone catches up (message-log replay) |
| Omnara | Dev machine | SSE, structured messages (not raw terminal) | Session can migrate to cloud sandbox; structured, not stream replay |
| Codex app-server | Local or remote host | JSON-RPC 2.0, stdio or WebSocket; PTY via explicit `command/exec/{write,resize,terminate}`; bearer-token WS auth | Not detailed publicly; RPC methods inherently resumable per-`processId` while app-server lives |
| Conductor / Conductor Cloud | Local worktree sandbox, or hosted (Cloud) | Native app UI locally; Cloud variant undocumented for phone-PTY | Not documented |
| Terragon (defunct) | Cloud sandbox container per task | Web dashboard push, mobile as thin client | Checkpoint-level (git branch + PR), not live PTY replay |
| CodeAgentsMobile | Dev machine or cloud VM | Dedicated SSH connection from iOS app | Standard SSH reconnect only |
| Blink Shell + Tailscale | Any Tailscale peer | Mosh (SSP/UDP) or SSH, separate from any app control channel | Mosh: stateless IP-roaming via SSP sequence numbers |
| tmux control mode | Tmux server, indefinitely | Text protocol over existing attach transport | Full resume: scrollback + running processes survive cross-machine reattach |
| ttyd / gotty / wetty | Host running the daemon | WebSocket, type-byte framed | Weak — dropped socket loses live output |
| VS Code Remote | Remote host's VS Code Server | Terminal multiplexed inside same SSH/tunnel RPC channel | Documented troubleshooting exists; wire semantics not public |

## Design recommendations for `lancerd`-hosted PTY over the existing relay

1. **Model the PTY as explicit RPC verbs inside the existing envelope, not a
   bare byte pipe** — mirror Codex's shape: `pty.open` (returns `sessionId`),
   `pty.write`, `pty.resize`, `pty.close`, server→client `pty.output` /
   `pty.exit`. Stays inside Lancer's current JSON envelope/E2E-encryption
   model; costs base64/JSON-safe encoding for raw bytes until binary framing
   lands (#2).

2. **Plan a binary-frame upgrade path now**, even if JSON ships first — ttyd's
   one-leading-type-byte model (input/output/resize/control) inside each WS
   frame is the simplest precedent for mixing terminal bytes and control
   messages on one socket without base64 bloat. Add a distinct binary frame
   type (`sessionId` + type byte + ciphertext) specifically for
   `pty.output`/`pty.write` so build-log/`tail -f` volume doesn't pay
   JSON+base64 tax on every frame.

3. **Chunk/batch PTY output server-side** into ~16–50ms windows before
   emitting a `pty.output` frame (ttyd/gotty pattern) — bounds
   messages-per-second without perceptible added latency.

4. **Adopt tmux control mode's server-owns-state model for reconnect, not
   mosh's frame-skipping model.** `lancerd` is the durable side — keep the
   PTY/process alive across phone disconnects. On `pty.open` for an existing
   `sessionId`, replay a bounded scrollback buffer (last N KB/lines) instead
   of nothing — tmux-style "resume where you left off," not gotty's
   "reconnect = blank pane."

5. **Monotonic per-session sequence numbers on output frames** (mosh-SSP
   style) so the phone can detect gaps on flaky cellular and request replay
   from the last acknowledged sequence, instead of silently losing output or
   re-rendering duplicates. One integer field on the existing envelope.

6. **Separate flow-control from the write path** — a `pty.pause`/`pty.resume`
   control message (ttyd has this) that the daemon honors by pausing PTY fd
   reads, so a slow phone doesn't force unbounded in-memory buffering or
   silent drops.

7. **Keep resize explicit and idempotent** — `pty.resize {sessionId, cols,
   rows}` as its own RPC (like Codex's `command/exec/resize`, distinct from
   `write`), daemon tolerant of resize/output race ordering.

8. **Reuse the existing relay's E2E-encryption and pairing/auth as-is for PTY
   frames** rather than a parallel secure channel — the one thing every
   non-SSH competitor here (Happy, Codex remote) gets right and
   Blink/CodeAgentsMobile get wrong: a second connection is a second attack
   surface and failure mode. PTY should be "new message types on the channel
   that already works," not "a new channel."

## Open gap

R1 (Orca — has terminal perf benchmarks worth learning from), R2 (Happier —
closest architectural cousin), and R3 (Omnara/lfg/agent-native codebase
detail) never completed. `research-repos/` still has the clones. Re-running
these against the design recommendations above (particularly to validate #2
binary framing and #4 scrollback-replay sizing against real implementations)
is worth doing before locking the wire format — flagged for the next
orchestration pass rather than blocking J2/A3, which don't depend on it.
