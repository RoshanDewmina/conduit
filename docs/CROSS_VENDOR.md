# Cross-Vendor Support

Conduit is designed around a single approval protocol so multiple agent CLIs can share the same mobile review and decision loop.

## Supported Today

### Claude Code
- Hook script: `docs/conduit-hook.sh`
- Status: production path
- Structured fields forwarded to `conduitd`: `tool_name`, `tool_use_id`, `session_id`, `tool_input`
- Canonical agent source in daemon: `claudeCode`

### Codex
- Hook script: `docs/codex-conduit-hook.sh`
- Status: production path
- Structured fields forwarded to `conduitd`: `tool_name`, `tool_use_id`, `session_id`, `tool_input`
- Canonical agent source in daemon: `codex`

## Codex Parity Audit (Stage 6)

This stage re-checked Codex parity against the Claude hook contract:

- Both hooks parse the pre-tool payload from stdin JSON.
- Both hooks emit the same structured tool-use fields to `conduitd`.
- Both hooks gate actions by risk and tool category before invoking `conduitd agent-hook`.
- Both hooks fail closed (exit non-zero) when Conduit explicitly denies.

Known acceptable differences:
- Codex hook includes local `~/.conduit/codex-hook-events.jsonl` telemetry for troubleshooting.
- Tool classification lists differ slightly because Codex and Claude expose different tool names.

## Roadmap: Next Vendor Steps

### Cursor (placeholder wired)
- Daemon now reserves canonical source `cursor` in agent normalization.
- Next milestone: implement `docs/cursor-conduit-hook.sh` with the same structured field mapping and risk policy shape as Claude/Codex.

### Gemini
- Daemon normalization reserves canonical source `gemini`.
- Next milestone: define a hook adapter that emits the same `tool_name` / `tool_input` envelope to keep card rendering consistent.

## Compatibility Contract

Any future vendor integration should preserve this contract:

1. Parse hook payload from stdin JSON only.
2. Forward canonical fields (`tool_name`, `tool_use_id`, `session_id`, `tool_input`) to `conduitd`.
3. Canonicalize source identity in daemon (`claudeCode`, `codex`, `cursor`, ...).
4. Keep approval cards and rule matching vendor-agnostic in the mobile app.
