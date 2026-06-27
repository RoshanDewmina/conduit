# lancer-mcp

MCP gateway that wraps tool calls through `lancerd agent-hook`, enabling Lancer's approval and policy system for Class B agents (Goose, Cline, Roo Code, Kilo).

## What it does

`lancer-mcp` is a small MCP (Model Context Protocol) server that:

1. Exposes a set of wrapped tools (`bash`, `write_file`, `read_file`, `edit_file`)
2. When the agent calls a tool, calls `lancerd agent-hook` internally
3. `lancerd` evaluates policy and optionally escalates to the phone
4. Returns the result or a denial to the agent

This lets agents that only support MCP tool connections — and have no pre-tool hook API — participate in Lancer's approval flow.

## Install

```bash
cd daemon/lancer-mcp
go build -o lancer-mcp .
```

Copy the binary somewhere on your `PATH`, e.g.:

```bash
cp lancer-mcp /usr/local/bin/
```

## Configuration

`lancer-mcp` reads a JSON config file. Default location: `~/.lancer/lancer-mcp.json`.

Override with `LANCER_MCP_CONFIG=/path/to/config.json` or pass the path as the first argument.

### Config format

```json
{
  "agent": "goose",
  "socketPath": "~/.lancer/lancerd.sock",
  "tools": [
    {
      "name": "bash",
      "description": "Execute a shell command",
      "agentHook": "hooks",
      "kind": "command",
      "risk": 2
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| `agent` | Agent identifier passed to `lancerd agent-hook --agent` |
| `socketPath` | Path to the lancerd Unix socket |
| `tools` | Array of tool mappings |
| `tools[].name` | MCP tool name the agent sees |
| `tools[].description` | Tool description shown to the agent |
| `tools[].kind` | Canonical kind passed to `--kind` (e.g. `command`, `patch`, `fileWrite`, `read`) |
| `tools[].risk` | Risk level: 0=low, 1=medium, 2=high, 3=critical |

## Agent setup

### Goose

Add to your Goose MCP config (`~/.config/goose/config.yaml` or similar):

```yaml
mcpServers:
  lancer:
    command: /usr/local/bin/lancer-mcp
    args:
      - /Users/you/.lancer/lancer-mcp.json
```

### Cline (VS Code)

Add to `.vscode/settings.json` or Cline's MCP settings:

```json
{
  "cline.mcpServers": {
    "lancer": {
      "command": "/usr/local/bin/lancer-mcp",
      "args": ["/Users/you/.lancer/lancer-mcp.json"]
    }
  }
}
```

### Roo Code

Add to Roo Code's MCP server configuration:

```json
{
  "mcpServers": {
    "lancer": {
      "command": "/usr/local/bin/lancer-mcp",
      "args": ["/Users/you/.lancer/lancer-mcp.json"]
    }
  }
}
```

### Kilo

Add to Kilo's MCP settings:

```json
{
  "mcpServers": {
    "lancer": {
      "command": "/usr/local/bin/lancer-mcp",
      "args": ["/Users/you/.lancer/lancer-mcp.json"]
    }
  }
}
```

## How it works

1. The agent connects to `lancer-mcp` via stdio (standard MCP transport)
2. On `tools/list`, `lancer-mcp` returns the tools defined in the config
3. On `tools/call`, `lancer-mcp` runs:
   ```
   lancerd agent-hook --agent <agent> --kind <kind> --command <input> --risk <risk>
   ```
4. If `lancerd` approves (exit 0), the tool output is returned
5. If `lancerd` denies (exit 1), an error is returned to the agent

Read-only tools (risk 0) fail open when `lancerd` is not running. Mutating tools (risk ≥ 1) fail closed.

## Prerequisites

- `lancerd` must be installed and running (`lancerd install` or `lancerd daemon`)
- The agent must be configured to use MCP tools
- The config file must be valid JSON with at least one tool mapping
