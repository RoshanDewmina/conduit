# Local Agent Session Stores

Use this reference when a user asks to learn from prior Claude Code, Codex, OpenCode, or Kimi Code conversations.

## Fast Index

```bash
/Users/roshansilva/.codex/skills/agent-session-history-reader/scripts/list-agent-sessions.sh 7 /Users/roshansilva/Documents/command-center
```

The script is read-only. It prints recent candidate sessions and paths. Open only the relevant candidates.

## Claude Code

Path pattern:

```text
~/.claude/projects/<escaped-cwd>/*.jsonl
```

For `/Users/roshansilva/Documents/command-center`, the project directory is typically:

```text
~/.claude/projects/-Users-roshansilva-Documents-command-center
```

Useful commands:

```bash
rg -n "sessionId|summary|lancer|opencode|codex|kimi|resume|handoff" ~/.claude/projects/-Users-roshansilva-Documents-command-center
ls -lt ~/.claude/projects/-Users-roshansilva-Documents-command-center/*.jsonl | head
```

Gotchas:

- File names are UUIDs; title/summary may be inside JSONL lines.
- CWD encoding replaces both `/` and `.` with `-`.
- `message.content` can be either a string or an array.
- Side directories such as `<uuid>/subagents/` and `<uuid>/tool-results/` can matter for delegated work.
- `~/.claude/history.jsonl` is prompt history, not the canonical transcript.
- Some lines are tool calls or tool output, not user-visible messages.
- Prefer session IDs and exact paths when citing evidence.

## Codex

Path patterns:

```text
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
~/.codex/session_index.jsonl
~/.codex/memories/rollout_summaries/*.md
```

Useful commands:

```bash
tail -n 20 ~/.codex/session_index.jsonl | jq -c '{id, thread_name, updated_at}'
rg -n "\"cwd\":\"/Users/roshansilva/Documents/command-center\"|session_meta|turn_context|response_item" ~/.codex/sessions
rg -n "session resume|Lancer|OpenCode|Kimi|handoff|parallel" ~/.codex/session_index.jsonl ~/.codex/memories/MEMORY.md ~/.codex/memories/rollout_summaries
```

Gotchas:

- `session_index.jsonl` may only have `id`, `thread_name`, and `updated_at`; resolve an ID to a rollout with `rg -l --fixed-strings "\"id\":\"$id\"" ~/.codex/sessions`.
- `session_meta.payload.id` is the session ID inside rollout files.
- `event_msg` is status chatter; `response_item` contains actual messages/tool calls.
- Some rollout payloads can be encrypted or app-specific; inspect payload type counts before reading content.
- Memory summaries are useful routing indexes, not a substitute for current repo verification.

## OpenCode

Primary store:

```text
~/.local/share/opencode/opencode.db
```

Use SQLite read-only:

```bash
opencode session list --format json | jq -c '.[] | {id,title,directory,updated,created}'
sqlite3 "file:$HOME/.local/share/opencode/opencode.db?mode=ro" ".tables"
sqlite3 "file:$HOME/.local/share/opencode/opencode.db?mode=ro" "select id,title,time_created,time_updated from session order by time_updated desc limit 20;"
```

Gotchas:

- The database can be large. Query indexes and summaries first.
- The reliable source is the SQLite database; older `storage/` JSON trees are supporting artifacts, not the primary transcript store.
- Session and message schemas may change; inspect `pragma table_info(session);` and `pragma table_info(message);`.
- `message.data` and `part.data` can be JSON blobs.
- Do not open the DB read-write or run cleanup commands.

## Kimi Code

Path patterns:

```text
~/.kimi-code/sessions/wd_<workspace>_<hash>/session_*/state.json
~/.kimi-code/session_index.jsonl
```

Useful commands:

```bash
jq -cr --arg cwd "$PWD" 'select(.workDir==$cwd) | {sessionId,workDir,sessionDir}' ~/.kimi-code/session_index.jsonl
find ~/.kimi-code/sessions -name state.json -mtime -7 -print
rg -n "\"title\"|\"sessionId\"|lancer|opencode|claude|codex" ~/.kimi-code/sessions ~/.kimi-code/session_index.jsonl
```

Gotchas:

- Workspace directories are prefixed with `wd_`.
- `session_index.jsonl` contains `sessionId`, `workDir`, and `sessionDir`.
- `state.json` is the fastest title/status entrypoint.
- Per-session logs such as `logs/kimi-code.log` are plain text and can be sensitive.
- Session folders can contain large raw message payloads; open selectively.
