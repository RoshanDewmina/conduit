# Vendor free/cheap model live smoke — 2026-07-19

**Overall: PASS** (Codex + OpenCode). Cursor full live smoke deferred (PR #190); 30s doctor/status probe only.

Retry of the lane marked **MISSING** in PR #189 rollup. Smoke-only — no product code changes. Production `~/.lancer` was not paired or wiped.

| Vendor   | Result | Version        | Model used                         | Notes |
|----------|--------|----------------|------------------------------------|-------|
| Codex    | **PASS** | `codex-cli 0.144.6` | `gpt-5.4-mini` (reasoning `low`) | ChatGPT auth; cheapest listed catalog model |
| OpenCode | **PASS** | `1.17.18`      | `opencode/deepseek-v4-flash-free`  | First free model tried; exact string |
| Cursor   | **SKIP** (doctor only) | `agent 2026.07.16-899851b` / Cursor `3.12.17` | — | Logged in; full smoke waits for #190 |

No 402 / no-credits failures observed on the successful paths.

---

## Isolation

- **Did not** run `lancerd pair`
- **Did not** wipe or mutate production `~/.lancer` (confirmed still present; no pair invoked)
- Codex: isolated `CODEX_HOME=/tmp/lancer-vendor-smoke-2026-07-19/codex-home` with copied `auth.json` + minimal `config.toml` (not the production `~/.codex/config.toml`)
- OpenCode: isolated `XDG_DATA_HOME` / `XDG_CONFIG_HOME` / `XDG_STATE_HOME` under `/tmp/lancer-vendor-smoke-2026-07-19/opencode-xdg-*` with copied `auth.json`; `OPENROUTER_API_KEY` present in environment
- Workdir: `/tmp/lancer-vendor-smoke-2026-07-19/workdir` (outside the Lancer tree)

Artifacts under `logs/` in this directory.

---

## Codex

### Versions / auth

- CLI: `codex-cli 0.144.6`
- Auth mode (isolated home): ChatGPT (`auth_mode=chatgpt`; no `OPENAI_API_KEY` in auth.json)
- Catalog (`codex debug models`): `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`, `gpt-5.4-mini` (hide), `codex-auto-review` (hide)

### Attempt 1 — free/API-cheap reject (evidence, not PASS)

```text
codex exec --ephemeral --skip-git-repo-check --sandbox read-only --color never \
  -m gpt-5-nano -o …/codex-last-message.txt \
  'Reply with exactly: codex-smoke-OK' </dev/null
```

Result: **FAIL / not supported** (not billed as PASS):

```text
ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error",
"message":"The 'gpt-5-nano' model is not supported when using Codex with a ChatGPT account."}}
```

### Attempt 2 — cheapest ChatGPT-supported model — PASS

```text
export CODEX_HOME=/tmp/lancer-vendor-smoke-2026-07-19/codex-home
codex exec --ephemeral --skip-git-repo-check --sandbox read-only --color never \
  -m gpt-5.4-mini -c model_reasoning_effort=\"low\" \
  -o …/logs/codex-last-message.txt \
  'Reply with exactly: codex-smoke-OK' </dev/null
```

- Started: `2026-07-19T21:25:42Z`
- Finished: `2026-07-19T21:25:45Z`
- Session: `019f7c45-46c9-7650-9839-895fef7b25db`
- Tokens used: `7,729`
- Last message file (`logs/codex-last-message.txt`):

```text
codex-smoke-OK
```

### Log tail (`logs/codex-smoke.log`)

```text
OpenAI Codex v0.144.6
--------
workdir: /private/tmp/lancer-vendor-smoke-2026-07-19/workdir
model: gpt-5.4-mini
provider: openai
approval: never
sandbox: read-only
reasoning effort: low
reasoning summaries: none
session id: 019f7c45-46c9-7650-9839-895fef7b25db
--------
user
Reply with exactly: codex-smoke-OK
codex
codex-smoke-OK
tokens used
7,729
codex-smoke-OK
```

---

## OpenCode

### Versions / auth

- CLI: `1.17.18`
- Credentials: OpenRouter API key via env + isolated copied `~/.local/share/opencode/auth.json` → `$XDG_DATA_HOME/opencode/auth.json`

### Command — PASS on first free model

```text
export XDG_DATA_HOME=/tmp/lancer-vendor-smoke-2026-07-19/opencode-xdg-data
export XDG_CONFIG_HOME=/tmp/lancer-vendor-smoke-2026-07-19/opencode-xdg-config
export XDG_STATE_HOME=/tmp/lancer-vendor-smoke-2026-07-19/opencode-xdg-state
opencode run --print-logs --log-level WARN --format default \
  -m opencode/deepseek-v4-flash-free \
  --title vendor-free-smoke \
  'Reply with exactly: opencode-smoke-OK' </dev/null
```

- Started: `2026-07-19T21:26:00Z`
- Exit: `0`
- Stdout (`logs/opencode-last-message.txt`):

```text
opencode-smoke-OK
```

- Model marker in stderr: `> build · deepseek-v4-flash-free`
- Free fallbacks prepared but **not needed**: `opencode/mimo-v2.5-free`, `opencode/hy3-free`, `opencode/north-mini-code-free`, OpenRouter `:free` variants

### Log tail notes

Stderr is noisy with duplicate-skill WARN lines from overlapping `~/.claude/skills` and `~/.agents/skills` trees (unrelated to the model call). Successful completion marker:

```text
> build · deepseek-v4-flash-free
```

Full combined log: `logs/opencode-smoke.log`. Truncated stderr: `logs/opencode-stderr-tail.txt`.

---

## Cursor (doctor / status only — not a full live smoke)

Per brief: full Cursor live smoke waits for **PR #190** merge. Ran a ≤30s probe:

```text
agent --version   → 2026.07.16-899851b
cursor --version  → 3.12.17
agent status      → ✓ Logged in as sidewhinder2k3@gmail.com
```

Evidence: `logs/cursor-doctor.txt`.

**Not claimed:** Cursor model reply smoke / adapter E2E.

---

## Verdict

| Check | Result |
|-------|--------|
| Codex exact `codex-smoke-OK` | PASS (`gpt-5.4-mini` / low) |
| OpenCode exact `opencode-smoke-OK` | PASS (`opencode/deepseek-v4-flash-free`) |
| 402 / no-credits on successful path | None |
| Production `~/.lancer` intact / no pair | Confirmed |
| Cursor full smoke | SKIPPED (doctor-only; blocked on #190) |

**Lane status for rollup replacement of PR #189 MISSING:** Codex+OpenCode vendor free/cheap smoke = **PASS** with artifacts in this directory.
