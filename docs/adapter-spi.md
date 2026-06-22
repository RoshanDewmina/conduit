# Lancer Adapter SPI

Lancer supports two integration patterns for AI coding agents. Class A is preferred; Class B is for agents that lack a pre-tool hook API.

---

## Class A — External Pre-Tool Hook (recommended)

The agent has a permission or tool-approval callback. Lancer intercepts it via a hook script that shells out to `lancerd agent-hook`.

### Contract

1. Agent fires a pre-tool event (`PreToolUse`, `BeforeTool`, etc.)
2. Hook script runs `lancerd agent-hook --agent <agentID> --kind <kind> --command <command>`
3. `lancerd` evaluates policy, escalates to the phone if needed
4. Hook returns exit 0 (approved) or exit 1 (denied)
5. Agent proceeds or blocks

### Exit code convention

| Exit | Meaning |
|------|---------|
| 0    | Approved — tool call may proceed |
| 1    | Denied or error — tool call must be blocked |

### Adding a Class A adapter

1. **Define the agent in `agent_registry.go`** — add a case to `normalizeAgentSource()` mapping the agent's name/canonical ID to the internal agent key (e.g. `"goose"`, `"cline"`).
2. **Write a hook script** — a shell script that the agent calls before each tool execution. The script invokes `lancerd agent-hook` with the correct flags.
3. **Register agent events** — map the agent's pre-tool event payload to the canonical `--kind` values:
   - `command` — shell commands, `bash` tool
   - `patch` — file edits, `apply_patch`, `edit_file`, `multi_edit`
   - `fileWrite` — `write_file`, `create_file`
   - `fileDelete` — file deletions
   - `read` — `read_file`, `grep` (read-only, fail-open when daemon is down)
   - `network` — outbound HTTP requests
   - `credential` — key/token access
4. **(Optional) Add a status reader** — create `agent_status_<agent>.go` to report login state, model, and session count from the agent's local data.

### Canonical `--kind` values

These are the canonical kind strings recognized by the policy engine. Hook scripts should normalize agent-specific tool names to one of these before calling `lancerd agent-hook`:

| Canonical kind | Typical agent tools |
|----------------|---------------------|
| `command`      | `bash`, `shell`, `execute_command` |
| `patch`        | `apply_patch`, `edit_file`, `multi_edit`, `str_replace_editor` |
| `fileWrite`    | `write_file`, `create_file` |
| `fileDelete`   | `delete_file`, `remove_file` |
| `read`         | `read_file`, `view`, `grep` |
| `network`      | `fetch`, `http_request` |
| `credential`   | `keychain_read`, `get_secret` |

### `--risk` values

| Risk | Meaning |
|------|---------|
| `low` (default) | Read-only or low-impact operations |
| `medium` | File mutations in the project tree |
| `high` | Shell commands, network calls, credential access |
| `critical` | Never auto-approved; always requires phone confirmation |

---

## Class B — MCP Gateway (for agents without hook access)

The agent connects to Lancer as an MCP (Model Context Protocol) server. `lancer-mcp` wraps dangerous tools and calls `agent-hook` internally for policy evaluation.

### Contract

1. Agent connects to `lancer-mcp` as an MCP server via stdio
2. `lancer-mcp` exposes wrapped tools (`bash`, `write_file`, `edit_file`, etc.)
3. When the agent calls a wrapped tool, `lancer-mcp` calls `lancerd agent-hook`
4. `lancerd` evaluates policy, escalates to the phone if needed
5. `lancer-mcp` returns the result or a denial error

### When to use Class B

Use Class B when the agent:
- Has no pre-tool hook or permission callback
- Only supports MCP tool connections (Goose, Cline, Roo Code, Kilo)
- Cannot run arbitrary shell scripts before tool execution

### Adding a Class B adapter

1. **Define tool mappings** in `daemon/lancer-mcp/config.json`:
   ```json
   {
     "name": "bash",
     "description": "Execute a shell command",
     "agentHook": "hooks",
     "kind": "command",
     "risk": 2
   }
   ```
2. **Map tool names** — the `name` field is what the agent sees as the MCP tool. `kind` is what gets passed to `lancerd agent-hook --kind`.
3. **Set risk levels** — use 0 for read-only tools, 1 for minor mutations, 2 for commands/major edits, 3 for critical operations.
4. **Configure the agent** — point the agent's MCP server config at the `lancer-mcp` binary (see `daemon/lancer-mcp/README.md` for agent-specific examples).

---

## Comparison

| | Class A (Hook) | Class B (MCP Gateway) |
|---|---|---|
| Agent support | Claude Code, Codex, OpenCode, Cursor | Goose, Cline, Roo Code, Kilo |
| Requires hook API | Yes | No |
| Implementation | Shell script per agent | Single `lancer-mcp` binary |
| Tool interception | Agent-native | MCP protocol proxy |
| Latency | Low (direct exit code) | Moderate (stdio round-trip) |

---

## Reference: `lancerd agent-hook` flags

```
lancerd agent-hook \
  --agent <agentID> \
  --kind <canonicalKind> \
  --command <commandOrPath> \
  --cwd <workingDirectory> \
  --risk <low|medium|high|critical> \
  --tool-name <agentToolName> \
  --tool-use-id <id> \
  --session-id <sessionID> \
  --tool-input <jsonInput> \
  --timeout <duration>
```

| Flag | Required | Description |
|------|----------|-------------|
| `--agent` | Yes | Agent identifier (e.g. `goose`, `cline`, `claudeCode`) |
| `--kind` | Yes | Canonical tool kind (see table above) |
| `--command` | Yes | The command string or file path being executed |
| `--cwd` | No | Working directory (defaults to process cwd) |
| `--risk` | No | Risk level: `low`, `medium`, `high`, `critical` |
| `--tool-name` | No | Agent-specific tool name |
| `--tool-use-id` | No | Unique ID for this tool invocation |
| `--session-id` | No | Agent session identifier |
| `--tool-input` | No | Raw JSON tool input payload |
| `--timeout` | No | Max wait for decision (default: 120s) |
