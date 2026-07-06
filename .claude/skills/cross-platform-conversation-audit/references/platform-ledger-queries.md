# Platform Ledger Queries

Build the **session ledger** before Pass 1 deep reads. Every in-scope session in the date window gets a row. Use the repo anchor (default `/Users/roshansilva/Documents/command-center`) and include worktrees when `cwd` matches.

For baseline path patterns and OpenCode/Kimi stores, see `agent-session-history-reader/references/session-stores.md`.

## Claude Code

**Store:** top-level JSONL only (not subdirectories):

```text
~/.claude/projects/<escaped-cwd>/*.jsonl
```

CWD encoding: `/` and `.` → `-`. Example:

```text
~/.claude/projects/-Users-roshansilva-Documents-command-center/
```

**Worktrees:** each worktree has its own escaped project dir (e.g. `-Users-roshansilva--cursor-worktrees-command-center-skill-cross-platform-audit`). Query every project dir whose path contains the repo name or list all recent dirs and filter by `cwd` inside JSONL.

### Inventory commands

```bash
REPO="/Users/roshansilva/Documents/command-center"
ESCAPED="${REPO//\//-}"
ESCAPED="${ESCAPED//./-}"
CUTOFF=$(date -v-${DAYS:-7}d +%s)

# Primary repo + recent sibling project dirs
for d in ~/.claude/projects/-Users-roshansilva-*command-center*; do
  [ -d "$d" ] || continue
  for f in "$d"/*.jsonl; do
    [ -f "$f" ] || continue
    MTIME=$(stat -f %m "$f")
    [ "$MTIME" -ge "$CUTOFF" ] || continue
  LINES=$(wc -l < "$f" | tr -d ' ')
  echo "$MTIME $LINES $f"
  done
done | sort -rn
```

### Scope filter

Inside each candidate file, confirm project scope from early lines:

```bash
jq -r 'select(.cwd != null) | .cwd' session.jsonl 2>/dev/null | head -1
# or rg for "cwd" in first 50 lines
```

Include session when `cwd` is the repo root, a worktree under it, or the user explicitly widened scope.

### Stub detection

Flag as **stub** (inventory only, skip deep-read) when:

- File has fewer than ~5 substantive lines, **or**
- No `role":"user"` message with real task content in the first 200 lines, **or**
- Only metadata / compaction / system preamble

Still list stub UUIDs in the ledger so repeated empty sessions are visible.

### Side directories

`<uuid>/subagents/` and `<uuid>/tool-results/` are **not** top-level ledger rows. After identifying a parent UUID, check subagent dirs when the parent delegates work — cite parent session ID in findings.

---

## Codex

**Metadata:** `~/.codex/state_5.sqlite` → `threads` table  
**Transcripts:** rollout JSONL under `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (path also in `threads.rollout_path`)

### Thread ledger (SQLite read-only)

```bash
sqlite3 "file:$HOME/.codex/state_5.sqlite?mode=ro" "
SELECT id, title, cwd, created_at, updated_at, rollout_path, first_user_message
FROM threads
WHERE cwd LIKE '%command-center%'
  AND datetime(created_at) >= datetime('now', '-${DAYS:-7} days')
ORDER BY created_at DESC;"
```

Fallback index when `threads` is sparse:

```bash
tail -n 100 ~/.codex/session_index.jsonl | jq -c '{id, thread_name, updated_at}'
```

Resolve `id` → rollout:

```bash
rg -l --fixed-strings "\"id\":\"$THREAD_ID\"" ~/.codex/sessions
```

### Fork detection

In rollout JSONL, read `session_meta` early:

```bash
jq -c 'select(.type=="session_meta") | .payload | {id, cwd, forked_from_id}' rollout.jsonl | head -1
```

- `forked_from_id` present → explicit fork; read parent only if needed for context, not as duplicate finding source
- No `forked_from_id` → standalone thread

### Message extraction

Prefer `response_item` payloads for user/assistant content. Skip `event_msg` status chatter unless debugging session lifecycle.

---

## Cursor

Cursor stores composer metadata globally and workspace association per folder.

### Global composer store

```text
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
```

Table: `cursorDiskKV`

Relevant key patterns:

- `composerData:<composerId>` — composer metadata (title, status, timestamps, `forkedFromComposerId`, etc.)
- `bubbleId:<composerId>-<bubbleId>` — individual messages / bubbles

### Workspace scoping

Per-workspace DB:

```text
~/Library/Application Support/Cursor/User/workspaceStorage/<hash>/state.vscdb
```

Cross-reference: workspace `state.vscdb` maps folders to workspace hash; filter composers whose `cwd` / workspace path matches the repo anchor.

### Inventory queries (SQLite read-only)

```bash
GLOBAL="$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

sqlite3 "file:${GLOBAL}?mode=ro" "
SELECT key, length(value) as bytes
FROM cursorDiskKV
WHERE key LIKE 'composerData:%'
ORDER BY key DESC
LIMIT 200;"
```

Parse `value` JSON for each `composerData:*` row:

```bash
sqlite3 "file:${GLOBAL}?mode=ro" "
SELECT substr(key, 14) as composer_id, value
FROM cursorDiskKV
WHERE key LIKE 'composerData:%';" \
| while IFS='|' read -r id json; do
  echo "$json" | jq -c --arg id "$id" '{
    composer_id: $id,
    name: .name,
    createdAt: .createdAt,
    lastUpdatedAt: .lastUpdatedAt,
    forkedFromComposerId: .forkedFromComposerId,
    workspaceFolder: .workspaceFolder
  }' 2>/dev/null
done
```

Filter to repo anchor and date window using `createdAt` / `lastUpdatedAt` (epoch ms).

### Bubble / message enumeration

For each in-scope `composer_id`:

```bash
sqlite3 "file:${GLOBAL}?mode=ro" "
SELECT key FROM cursorDiskKV
WHERE key LIKE 'bubbleId:${COMPOSER_ID}-%'
ORDER BY key;"
```

Read bubble payloads for verbatim evidence quotes in Pass 1.

### Fork / subagent gotchas

- Some composers set `forkedFromComposerId` and **replay parent history** in the UI — bubbles may duplicate parent content
- Some subagent / Task dispatches are **standalone** composers with no fork field — full transcript is local only
- **Never assume** which case applies; check `forkedFromComposerId` and compare first-user-message timestamps against parent

Agent transcripts (when present):

```text
~/.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>.jsonl
```

Use as supplemental evidence; global `state.vscdb` remains canonical for composer metadata.

---

## Ledger Row Template

| Field | Example |
|---|---|
| platform | `claude` / `codex` / `cursor` |
| session_id | UUID or composer ID |
| path_or_key | `~/.claude/projects/.../abc.jsonl` or `composerData:...` |
| title_hint | First user message or thread name |
| created / mtime | ISO timestamp |
| cwd | Absolute path |
| est_messages | Line count or bubble count |
| stub | `yes` / `no` |
| fork_parent | Parent ID or empty |
| deep_read | `yes` / `skip-stub` |
