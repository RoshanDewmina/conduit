# Finding Schema

Every audit finding — whether extracted in Pass 1 or adjusted in Pass 2 — must include **all** fields below.

## Required Fields

| Field | Description |
|---|---|
| **finding** | One-sentence claim (decision, task, bug, plan, question) |
| **category** | e.g. `architecture`, `bug`, `feature`, `process`, `docs`, `skill`, `verification`, `deferred` |
| **severity** | `critical` / `high` / `medium` / `low` / `info` — impact if still wrong or unresolved |
| **platform** | `claude` / `codex` / `cursor` / `multi` |
| **date + session ID** | e.g. `2026-07-04, claude:550e8400-e29b-41d4-a716-446655440000` |
| **evidence** | Verbatim quote from transcript (short; use `...` only mid-quote). Include `path:line` or DB key when possible |
| **status** | See status enum below — **must** reflect later sessions **and** live repo checks |
| **confidence** | `high` / `medium` / `low` — how sure you are after Pass 2 |
| **related / duplicate findings** | IDs or short labels of same topic across sessions/platforms; `—` if none |

## Status Enum

Determine status by reading **forward in time** (later sessions) and checking **live repo state**. Do not default to `unresolved`.

| Status | Meaning |
|---|---|
| `discussed` | Talked about; no plan or commitment |
| `planned` | Agreed approach but no implementation started |
| `attempted` | Code/docs changed but not finished or not verified |
| `implemented` | Change landed in repo (commit or clear file evidence) |
| `tested` | Tests run per transcript or CI reference |
| `verified` | Pass 2 confirmed in live repo (git log, file read, gate command) |
| `abandoned` | Explicitly dropped or superseded |
| `unresolved` | Still open **after** checking later sessions and repo — use sparingly |

### Status decision order

1. **Live repo (Pass 2):** `git log`, file exists/content, `gh pr` state, test commands
2. **Later sessions:** same topic closed, shipped, or explicitly abandoned
3. **Same session:** commitment level in later messages
4. Only then `unresolved`

## Example Row

```markdown
### F-012 — Opencode execution path retired from CLAUDE.md

| Field | Value |
|---|---|
| category | process |
| severity | medium |
| platform | claude |
| date + session | 2026-07-06, claude:a1b2c3d4-... |
| evidence | "Owner's standing directive (2026-07-06): the opencode/deepseek execution path is retired entirely." (`CLAUDE.md` edit in session; quote from user message at line 42) |
| status | verified |
| confidence | high |
| related | F-003, F-008 (same directive mentioned in Codex thread c9f8...) |
```

## Categories of Duplication

When reconciling across platforms, tag relationships:

- **duplicate** — same claim repeated verbatim; verify once
- **reinforced** — multiple sessions agree; increases confidence
- **contradiction** — sessions disagree; Pass 2 picks winner from repo
- **supersedes** — later finding replaces earlier plan
