Read-only scan of the three research repos — I'll map their structure and trace the architectures you called out.
# R3 Research Report: Omnara, lfg, agent-native

**Scope:** Read-only analysis of `research-repos/omnara`, `research-repos/lfg`, `research-repos/agent-native`. No files modified.

---

## Executive summary

| Repo | What it is | Terminal over network? | Phone/mobile control plane? |
|------|------------|------------------------|-----------------------------|
| **Omnara (this clone)** | Deprecated CLI-wrapper + hosted dashboard; dual transport | **Yes** — WebSocket PTY relay (`omnara terminal`) | **Yes** — native iOS/Android apps + PWA web |
| **lfg** | Self-hosted Bun control plane on the dev machine | **Yes** — WebSocket PTY (`/api/term`) + tmux | **Yes** — installable PWA over Tailscale (not a native app) |
| **agent-native** | Framework for building agent-first apps | **No** productized remote terminal | **Partial** — Dispatch has Telegram remote `/code` commands; not a phone IDE |

**Cloud sandbox “session migrates on laptop drop”:** Not implemented or documented in this Omnara clone. README points to a new closed platform at omnara.com (Claude Agent SDK). **Cannot determine migration mechanics from this codebase.**

---

## 1. Omnara (`research-repos/omnara`)

> **Repo status:** README states this version is **deprecated** (CLI-wrapper around Claude Code). New product is at omnara.com; legacy dashboard at claude.omnara.com through ~end of 2025.

### 1.1 Core architecture (two parallel paths)

Omnara is **not** “100% structured messages.” It runs **two distinct remote-access paths**:

#### Path A — CLI wrapper + session JSONL → REST → SSE (structured chat)

**Mechanics:**

1. **Local PTY runs the agent CLI** (`claude_wrapper_v3.py` uses `pty.fork()` and execs `claude --session-id <uuid>`).
2. **Parallel JSONL tail** watches Claude’s on-disk transcript:
   - Base: `~/.claude/projects/<sanitized-cwd>/*.jsonl` (or `CLAUDE_CONFIG_DIR`)
   - Session file name matches `agent_instance_id`: `{agent_instance_id}.jsonl`
3. Each JSONL line is parsed; `user` / `assistant` entries become structured content and are **POSTed** via `OmnaraClient.send_message()` / `send_user_message()`.
4. **Permission/plan prompts** are also extracted from a **terminal ANSI buffer** (not only JSONL) and sent as structured messages with `[OPTIONS]…[/OPTIONS]` blocks.
5. **Mobile/web clients** subscribe to **SSE** backed by **PostgreSQL LISTEN/NOTIFY** on per-instance channels `message_channel_{instance_id}`.

**Evidence:**

```429:502:research-repos/omnara/src/integrations/cli_wrappers/claude_code/claude_wrapper_v3.py
    def monitor_claude_jsonl(self):
        """Monitor Claude's JSONL log file for messages"""
        ...
                expected_filename = f"{self.agent_instance_id}.jsonl"
        ...
                        line = f.readline()
                        if line:
                            try:
                                data = json.loads(line.strip())
                                self.process_claude_log_entry(data)
```

```862:904:research-repos/omnara/src/integrations/cli_wrappers/claude_code/claude_wrapper_v3.py
    def run_claude_with_pty(self):
        ...
        cmd = [claude_path, "--session-id", self.agent_instance_id]
        ...
        self.child_pid, self.master_fd = pty.fork()
        if self.child_pid == 0:
            os.environ["CLAUDE_CODE_ENTRYPOINT"] = "jsonlog-wrapper"
            os.execvp(cmd[0], cmd)
```

```260:345:research-repos/omnara/src/backend/api/agents.py
@router.get("/agent-instances/{instance_id}/messages/stream")
async def stream_messages(...):
    ...
    channel_name = f"message_channel_{instance_id}"
    await conn.execute(f'LISTEN "{channel_name}"')
    ...
    yield f"event: message\ndata: {json.dumps(data)}\n\n"
```

NOTIFY triggers live in Alembic migrations (e.g. `40d4252deb5b_add_messages_table.py`, `9fe045ea7ad9_fix_large_payload_notifications.py`).

#### Path B — Raw terminal WebSocket relay (live TTY mirror)

**Mechanics:**

1. `omnara terminal` → `run_agent_with_terminal_relay()` → `session_sharing.run_agent_with_relay()`.
2. Forks PTY, execs local `claude`/`amp`/`codex`.
3. Streams **raw terminal bytes** to `wss://relay.omnara.com/agent` (configurable) using framed protocol (`FRAME_TYPE_OUTPUT/INPUT/RESIZE/METADATA` in `relay_server/protocol.py`).
4. Relay server (`src/relay_server/`) fans out to viewers; web uses **xterm.js** (`TerminalLiveTerminal.tsx`); mobile uses WebView + relay client (`TerminalMobileTerminal.tsx`).

**Evidence:**

```239:281:research-repos/omnara/src/omnara/session_sharing.py
def run_agent_with_relay(...):
    """Launch the agent CLI and mirror its terminal through the relay."""
    ...
    registration = temp_client.register_agent_instance(
        agent_type=agent,
        transport="ws",
        ...
    )
```

```33:55:research-repos/omnara/apps/web/src/components/dashboard/instances/TerminalLiveTerminal.tsx
export function TerminalLiveTerminal({ instanceId, className }: TerminalLiveTerminalProps) {
  ...
  const sessions = await fetchRelaySessions(accessToken, abort.signal)
  if (!sessions.some(session => session.id === instanceId)) {
    updateStatus('session-missing')
```

**Instance UI combines both:** `InstanceDetail.tsx` renders `ChatInterface` (SSE structured messages) **and** `TerminalInstancePanel` (relay terminal).

### 1.2 Default CLI behavior (surprising doc/code drift)

- **Help/epilog** claims `omnara` starts with WebSocket relay by default.
- **Actual `main()` default branch** calls `run_agent_default()` → subprocess to `claude_wrapper_v3` (**Path A**, no relay).
- **Relay path** requires explicit `omnara terminal`.
- Epilog mentions `omnara legacy` but **no `legacy` subcommand exists** in `cli.py`.

```907:911:research-repos/omnara/src/omnara/cli.py
    elif args.command == "terminal":
        run_agent_chat(args, unknown_args)
    else:
        # Default behavior: run agent locally without relay
        run_agent_default(args, unknown_args)
```

### 1.3 MCP / agent integration (alternative to CLI wrapper)

- Unified server (`servers/app.py`): MCP + REST write path.
- MCP tools `log_step` / `ask_question` → `send_agent_message()` with `requires_user_input` flag.
- Queued user replies returned on next agent message (pull-on-send, not push-to-agent-process directly).

### 1.4 Governance, notifications, persistence

| Feature | Mechanism |
|---------|-----------|
| **Unified messages table** | `messages` with `sender_type`, `requires_user_input`, `last_read_message_id` |
| **Queued user input** | `get_queued_user_messages()` piggybacks on agent `send_message` |
| **Git diff attachment** | Wrapper sends `git_diff` with messages; SSE `git_diff_update` events |
| **Push (mobile)** | Expo push API (`servers/shared/notifications.py`); channel `agent-questions` |
| **Email/SMS** | Twilio + email via `notification_utils.py`; gated on `requires_user_input` |
| **Heartbeat** | Agent posts heartbeat; SSE `agent_heartbeat` |
| **Instance sharing** | Migration `23aa590c6a55_add_instance_sharing_and_teams.py` |
| **Remote launch** | `omnara serve` webhook server for dashboard-triggered agents |

### 1.5 PTY vs structured — answer

| Layer | PTY? | Structured? |
|-------|------|-------------|
| Local agent process | Always (wrapper or relay) | JSONL parsed in parallel |
| Remote phone UX | Optional via relay WebSocket | Primary via SSE chat |
| Permission UX | Terminal buffer parsing + structured OPTIONS | Yes |

**Not 100% structured** — real remote terminal exists, but it is a **separate subcommand and UI tab**, not the default `omnara` entrypoint in this code.

### 1.6 “Session migrates to cloud sandbox on laptop drop”

**Could not determine from this repo.**

- No sandbox migration, laptop-drop handoff, or cloud resume logic found.
- README explicitly says maintenance ended; new stack uses **Claude Agent SDK** at omnara.com (not in this tree).
- `instance_metadata` JSON column exists (`8f18d049395f_add_session_mode_and_relay_metadata_to_.py`) but migration only adds the column — no migration workflow code found.

---

## 2. lfg (`research-repos/lfg`)

### 2.1 What it is

**Self-hosted “mission control”** on the machine where code and CLIs live:

- Bun server (`lfg serve`, default `127.0.0.1:8766`)
- React/Vite **PWA** (`web/`)
- Agents in **long-lived tmux** sessions
- Designed for **Tailscale Serve** private access — **not** a hosted relay

README: *“lets you answer prompts or steer work from your phone or laptop.”*

### 2.2 Core architecture

```
Phone/browser (PWA)
    ↕ HTTP/SSE/WS over Tailscale
lfg serve (Bun)
    ├─ sessions.ts — discover processes, tail ~/.claude/.../*.jsonl (same pattern as Omnara)
    ├─ tmux.ts — spawn/attach/kill, capture pane, permission prompts
    ├─ live-ws.ts / SSE — stream normalized transcript messages
    ├─ pty.ts — openpty FFI bridge for browser terminal
    ├─ ask/store.ts — human-in-the-loop questions + long-poll
    ├─ push.ts — payload-less Web Push (VAPID)
    └─ agents/* — markdown-defined insight agents, auto schedulers
```

### 2.3 Terminal over network — **highly relevant to Lancer**

**Real PTY streaming:**

- `src/pty.ts`: Bun FFI `openpty`, raw VT byte stream, non-blocking poll.
- `serve.ts`: WebSocket on `/api/term` attaches `PtyBridge` per socket; resize control messages.
- `web/src/components/TermView.tsx`: **ghostty-web** (WASM VT engine) over WebSocket — explicitly chosen over xterm.js for Claude Code TUI fidelity.

```1:10:research-repos/lfg/web/src/components/TermView.tsx
// The Terminal tab: a faithful browser terminal — ghostty-web (Ghostty's real
// VT engine compiled to WASM) bridged over a websocket to a persistent tmux
// shell on the box.
```

**Also:** tmux-backed session view with structured transcript parsing (`sessions.ts` lines 1–3, 39–56).

### 2.4 Structured transcript path (parallel to terminal)

- Tails agent JSONL transcripts (Claude, Codex, Grok, etc.).
- Normalizes to `SessionMsg` kinds: `text`, `thinking`, `tool_use`, `tool_result`, `image`.
- Live updates via **SSE** (`/api/live/stream`, `/api/live/status`) or optional **WebSocket** (`LIVE_TRANSPORT=ws`).
- Message IDs (`uuid` per line) enable **dedup on SSE reconnect** — good pattern for mobile.

### 2.5 Mobile / remote control plane

| Capability | Implementation |
|------------|----------------|
| **Phone UI** | PWA (`manifest.webmanifest`: `display: standalone`, portrait) |
| **Remote access** | Tailscale Serve (documented); unauthenticated API by design on loopback |
| **Push notifications** | Payload-less VAPID; SW fetches latest state |
| **Voice steering** | ElevenLabs voice worker, `/api/voice/*`, ask-user skill |
| **WhatsApp** | `commands/whatsapp.ts` — Baileys sidecar, group triggers |
| **MCP tools** | `lfg mcp` — `lfg_list_sessions`, `lfg_send_session_message`, etc. |
| **Subagents** | `subagent create` spawns child sessions with parent linkage |

**No separate SSH goal:** Access is HTTP/WS over private tailnet, not SSH. Security model: **never expose publicly** (`SECURITY.md`, README).

### 2.6 Governance / approval patterns

- **`ask/store.ts`**: persisted questions (`open → answered → handled`), in-memory long-poll waiters, push on new question, answer via web or voice.
- **`sendq.ts`**: queued messages to tmux sessions.
- **`session-brain/`**: scheduled analysis, merge-guard, pattern suggestions.
- **`auto/`**: scheduled repo agents with findings + push.
- **Session status blocking**: detects model-unavailable / out-of-credits from transcript (`computeStatus` in `sessions.ts`) — “build paused” UX.

---

## 3. agent-native (`research-repos/agent-native`)

### 3.1 What it is

**Open-source framework** for apps where agent and UI share one SQL-backed action surface — not a dedicated phone control-plane product.

Core contract (`AGENTS.md`):

- **`defineAction`** = single source of truth (UI, agent, HTTP, MCP, A2A, CLI).
- **`application_state` in SQL** so agent knows navigation/selection.
- **`useDbSync()` + `/_agent-native/poll`** for real-time UI sync.
- **Harness agents** separate from `AgentEngine` (full CLIs own their loop).

### 3.2 Terminal / phone control plane relevance

**No native mobile terminal-over-network product found.**

Closest pieces:

| Package | Relevance |
|---------|-----------|
| **`packages/dispatch`** | “Workspace control plane” — approvals, vault, integrations, messaging routes |
| **`dispatch-remote-commands.ts`** | Telegram `/code` commands: `create`, `list`, `status`, `continue`, `approve`, `deny`, `stop` — relays to a **code-agent** envelope |
| **Harness / ACP** (`.agents/skills/harness-agents/SKILL.md`) | Spawns **local** child-process agents; explicitly **not** hosted/sandboxed; **“terminal methods are not advertised”** |
| **`audit-log` skill** | Automatic action-level audit trail (agent vs human) |
| **Templates (Chat, etc.)** | Durable threads + live sync — pattern reference, not remote dev machine control |

```71:79:research-repos/agent-native/.agents/skills/harness-agents/SKILL.md
Agent Native can act as an ACP client ... scoped to **local coding** ...
It is not a hosted/sandboxed transport, and it is not a chat/A2A transport.
...
terminal methods are not advertised (the agent uses its own shell).
```

**Dispatch approvals** (`packages/dispatch/src/routes/pages/approvals.tsx`): durable policy for workspace resource changes — governance UX pattern, not session steering.

### 3.3 What agent-native is good for (Lancer porting lens)

- **Action parity** (everything UI can do, agent can do).
- **Audit log** for governed changes.
- **Approval queues** with org-scoped policy.
- **Real-time sync** (poll + SSE fallback).
- **Composable mini-apps** over A2A.
- **External agent MCP** round-trip (`external-agents` skill).

**Not** a reference for E2E relay, PTY bridging, or phone-native shell UX.

---

## 4. Cross-repo patterns worth porting to Lancer

### High value

1. **Dual-surface model (Omnara, lfg)**  
   Structured transcript/chat for approvals + optional raw terminal tab. Lancer already targets both; these repos validate the split.

2. **JSONL tail as vendor adapter (Omnara, lfg)**  
   Parse `~/.claude/projects/.../<sessionId>.jsonl` instead of scraping PTY for agent turns. lfg adds robust `SessionMsg` normalization, API-error detection, dedup IDs.

3. **Postgres NOTIFY → SSE (Omnara)**  
   Low-latency push to many clients without polling the messages table. Lancer’s push-backend may already do something similar — worth comparing.

4. **Permission prompt as structured message with OPTIONS (Omnara)**  
   `[OPTIONS]…[/OPTIONS]` in message body + pending option map in wrapper. Good for governance UX without full terminal.

5. **Payload-less push + client fetch (lfg)**  
   SW wakes, fetches latest open ask/finding. Reduces crypto complexity; pairs with `ask/store` long-poll on server.

6. **Tailscale-first security (lfg)**  
   Loopback bind + private tailnet exposure — aligns with Lancer’s “no public SSH” direction (E2E relay is different transport, same trust model).

7. **ghostty-web for mobile terminal (lfg)**  
   If Lancer needs faithful Claude Code TUI in browser, WASM Ghostty > xterm.js (lfg documents why).

8. **Session health / blocked status (lfg)**  
   Transcript-derived `status: blocked` with reasons (`model_unavailable`, `out_of_credits`) — better than silent spinner.

9. **Queued user messages on agent send (Omnara)**  
   User replies batch-delivered on next agent API call — simple, works when agent is blocked in tool loop.

10. **Dispatch-style audit + approval policy (agent-native)**  
    Durable approval requests before applying workspace-wide changes — applicable to Lancer governance/audit trail, not session I/O.

### Surprising / cautionary

- **Omnara default CLI ≠ docs** — relay is `terminal` subcommand, not bare `omnara`.
- **Omnara deprecated** — patterns are proven but maintenance ended; new Omnara is a different product.
- **lfg unauthenticated API** — fine on tailnet; dangerous if mis-exposed.
- **agent-native explicitly rejects remote terminal in harness** — framework assumes local shell ownership.
- **“Cloud sandbox migration”** — marketing/feature may exist only in new Omnara; **not evidenced here**.

---

## 5. Lancer relevance matrix (your goals)

| Goal | Best reference |
|------|----------------|
| E2E relay without SSH | Omnara relay framing + registration; lfg Tailscale pattern (different transport, same placement) |
| Structured approve/steer | Omnara SSE + messages + OPTIONS; lfg ask/store + sendq |
| Raw terminal on phone | lfg `/api/term` + ghostty-web; Omnara relay + xterm/mobile WebView |
| Multi-agent orchestration | lfg subagents + session-brain; agent-native A2A/composable mini-apps |
| Notification design | Omnara Expo + SMS/email tiering; lfg payload-less push |
| Audit/governance | agent-native audit-log + Dispatch approvals; Omnara instance sharing |

---

## 6. Explicit unknowns (not guessed)

1. **Omnara new-platform “session migrates to cloud sandbox when laptop drops”** — no implementation in this clone; requires omnara.com / new bun binary source or docs.
2. **Whether new Omnara still uses JSONL tail vs SDK-native events** — not in this repo.
3. **Production scale/ops** of Omnara relay (multi-region, reconnect semantics beyond client retry) — only client/server code reviewed, not runbooks.
4. **agent-native Dispatch “code-agent” relay target** — envelope format exists; full phone UX for coding sessions not traced end-to-end in this pass.

---

**Bottom line for Lancer:** Omnara and lfg are the direct comps for phone control-plane + optional terminal. Both use **structured transcript sync** as the primary steering surface and **PTY/WebSocket** as an optional faithful terminal. agent-native is a **framework comp** for governance, actions, audit, and messaging integrations — not for terminal transport. The cloud-sandbox migration story is **not verifiable** in the cloned Omnara tree.