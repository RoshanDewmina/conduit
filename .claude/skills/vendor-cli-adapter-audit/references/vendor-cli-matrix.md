# Vendor CLI Adapter Matrix

This matrix is a starting point. Re-run local help and check official docs before changing adapter behavior.

## Local Baseline Verified 2026-07-18

| CLI | Binary | Version (2026-07-18) | Prior (2026-06-18) |
|---|---|---|---|
| claude | `/opt/homebrew/bin/claude` | 2.1.214 | 2.1.181 |
| codex | `/opt/homebrew/bin/codex` | codex-cli 0.135.0 | 0.135.0 (unchanged) |
| opencode | `/opt/homebrew/bin/opencode` | 1.17.18 | 1.17.7 |
| kimi | `/Users/roshansilva/.kimi-code/bin/kimi` | 0.18.0 | 0.15.0 |
| pi | **not installed** (`which pi` empty) | — | — (never audited) |

Key 2026-07-18 findings (verified against live `--help` and on-disk config, not docs):

- **Codex 0.135.0 has a real hooks system.** `~/.codex/hooks.json` uses the Claude-style
  schema (`{"hooks":{"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"…"}]}]}}`)
  and a conduit-era `pre_tool_use` hook is registered on this machine
  (`~/.codex/hooks/conduit-hook.sh`, trust record under `[hooks.state]` in
  `~/.codex/config.toml` as `"~/.codex/hooks.json:pre_tool_use:0:0"`).
  CORRECTION (same day, Phase 1 review): that trust record has `enabled = false` — the
  conduit hook is registered but NOT currently firing; Codex silently skips untrusted/disabled
  hooks (live-verified 2026-07-18 in an isolated CODEX_HOME). Trust is per-definition and per-position;
  `codex --dangerously-bypass-hook-trust` exists to skip it (do not use in production).
  The repo draft `docs/codex-hooks.json` + `docs/codex-lancer-hook.sh` match this exact shape —
  the draft is viable, but any installer must MERGE into `hooks.json` (a conduit-era hook already
  occupies index 0) and must account for the trust step, which is interactive (`/hooks` in Codex).
- **Kimi 0.18.0 also has the same Claude-style hooks system.** `~/.kimi-code/hooks.json`
  (same `PreToolUse` schema) with a working `~/.kimi-code/hooks/conduit-hook.sh`. So a Kimi
  Lancer hook is a port of the Codex/Claude hook pattern, not a from-scratch design.
- **Kimi risk:** local `~/.kimi-code/config.toml` sets `default_permission_mode = "yolo"` plus
  `[[permission.rules]]` entries — non-interactive runs auto-approve by default on this machine.
  A wired PreToolUse hook is therefore the only real per-action gate for Kimi.
- **Kimi resume flags confirmed in 0.18.0 help:** `-S, --session [id]` (omitting id opens an
  interactive picker — headless must always pass the id) and `-C, --continue` (per working
  directory). `--output-format stream-json` confirmed for `--prompt` mode. `--prompt` still
  documented incompatible with `--yolo/--auto/--plan` per earlier audits — reverify at smoke time.
- **OpenCode 1.17.18 run flags confirmed:** `-c/--continue`, `-s/--session <id>`, `--fork`
  (requires `-c` or `-s`), `--format json`, `--thinking` (show thinking blocks — relevant to
  live-status parity), `--variant <effort>`, `--attach <url>` (remote server mode), `--pure`
  (disables external plugins — never pass it, it would disable the Lancer approval plugin).
- **Codex exec resume confirmed:** `codex exec resume [SESSION_ID] [PROMPT]`, `--last`, `--all`.
- **Pi (`@earendil-works/pi-coding-agent`) is NOT installed** — must be installed before any
  Pi adapter work can be live-verified. All Pi knowledge so far is from source reading of the
  cloned repo (`research-repos/pi`), not live execution.
- `/Users/roshansilva/Downloads/ai-coding-agents-comprehensive-study.md` is useful but not ground truth.

## Version And Help Commands

```bash
which claude
claude --version
claude --help
claude -p --help 2>/dev/null || true

which codex
codex --version
codex exec --help
codex exec resume --help
codex --ask-for-approval never --sandbox workspace-write exec resume --help

which opencode
opencode --version
opencode run --help
opencode session --help 2>/dev/null || true
opencode session list --help 2>/dev/null || true

which kimi
kimi --version
kimi --help
kimi --prompt "hi" --help 2>/dev/null || true

which pi
pi --version
pi --help

which agent
agent -v
agent --help
```

## Current Lancer Code Entry Points

- Launch argv: `daemon/lancerd/dispatch.go` `agentArgv`
- Continue argv: `daemon/lancerd/dispatch.go` `continueArgv`
- Policy/budget gates: `dispatcher.dispatch` and `dispatcher.continueRun`
- RPC surface: `daemon/lancerd/server.go`
- Relay surface: `daemon/lancerd/e2e_router.go`
- Codex hook draft: `docs/codex-lancer-hook.sh`, `docs/codex-hooks.json`
- Codex policy/gating threat model: `docs/legal/SECURITY_ARCHITECTURE.md`
- OpenCode hook draft: `docs/opencode-lancer-hook.sh`, `docs/opencode-hooks.json`
- Installer/doctor coverage: `daemon/lancerd/install.go`, `daemon/lancerd/hook_install.go`, related tests

## Adapter Principles

- Use explicit `[]string` argv and `exec.Command(argv[0], argv[1:]...)`.
- Add tests that pin argv ordering.
- Keep prompt and model handling deterministic.
- Add tests that prove continue creates a new runId and reuses original cwd/model.
- Confirm stream parser behavior against actual NDJSON/JSON output.
- Check whether status collection includes the vendor before claiming Fleet parity.

## Known Risk By Agent

### Claude Code

Expected non-interactive pattern:

```text
claude --output-format stream-json --verbose --include-partial-messages -p <prompt>
claude --output-format stream-json --verbose --include-partial-messages --continue -p <prompt>
```

Check model flag ordering with local help before changing tests.

### Codex

Expected non-interactive pattern:

```text
codex exec --json <prompt>
codex exec resume --last --json <prompt>
```

Risk:

- Headless approval can hang without a TTY.
- `--dangerously-bypass-approvals-and-sandbox` disables Codex's own sandbox.
- `LANCER_CODEX_UNSAFE=1` is an explicit opt-in, not a default.
- Hook files in `docs/` are not proof that the installed Codex runtime will call and trust the hook. Verify `/hooks` trust/setup, config path, and actual hook invocation before claiming parity.
- Some docs may reference `~/.codex/...` while owner-step notes reference `~/.config/codex/...`; verify the real installed path.

### OpenCode

Expected non-interactive pattern:

```text
opencode run --format json <prompt>
opencode run --continue --format json <prompt>
opencode run --session <session-id> --format json <prompt>
```

OpenCode is a good executor path, but permission flags and provider/model aliases should be verified from local help.

Hook files exist, but check whether the Go installer and doctor wire/verify OpenCode automatically before claiming parity.

### Kimi Code

Expected non-interactive pattern:

```text
kimi --prompt <prompt> --output-format stream-json
kimi --continue --prompt <prompt> --output-format stream-json
```

Risk:

- Docs have stated `--prompt` cannot combine with `--yolo`, `--auto`, or `--plan`.
- Non-interactive behavior may auto-approve; verify on the installed version before shipping broad file-system access.
- The local installed version may lag current docs.
- Kimi may not be included in Lancer status collection or hook installation. Inspect current code before claiming first-class parity. (Confirmed 2026-07-18: `doctor.go` `checkAgentCLIs` omits kimi; no Lancer hook exists for it.)
- Local machine defaults to `default_permission_mode = "yolo"` (2026-07-18) — a wired PreToolUse hook is the only per-action gate.

### Pi (earendil-works, bin `pi`)

Not installed as of 2026-07-18. Expected surface from source reading of `research-repos/pi`
(UNVERIFIED against a live binary — install and re-verify before wiring anything):

```text
pi -p <prompt>                 # headless text
pi --mode json <prompt>        # one JSON AgentEvent per line
pi --mode rpc                  # JSON-RPC over stdio (prompt/steer/abort/get_state/fork/…)
pi -c | --session <id|path> | --session-id <id> | --fork <id|path>   # resume family
```

Sessions: JSONL under `~/.pi/agent/sessions/--<sanitized-cwd>--/<ts>_<id>.jsonl`.
Hooks: `.pi/extensions/*.ts` with `on("tool_call")` returning `{block?, reason?}`.
`-r/--resume` is an interactive picker — never usable headless.

### Cursor Agent (CLI `agent` / `cursor-agent`)

Current as of 2026-07-19 (local `agent` 2026.07.16-899851b, logged in):

```text
agent -p --output-format stream-json --trust <prompt>
agent -p --continue --output-format stream-json --trust <prompt>
agent -p --resume <chatId> --output-format stream-json --trust <prompt>
```

Risk:

- Without `--trust` (or `-f`/`--yolo`), headless fails fast EXIT 1 with "Workspace Trust Required" — not a TTY hang.
- `--force`/`--yolo` force-allows commands unless explicitly denied; Lancer omits by default (`LANCER_CURSOR_FORCE=1` opt-in).
- Stream-json emits whole `assistant` messages + `tool_call` started/completed (no Claude `stream_event` deltas unless `--stream-partial-output`).
- No Lancer PreToolUse hook for Cursor yet — policy stays fail-closed when hooks are absent.

## Smoke Checks

Run smoke checks in a temp directory with harmless prompts and a timeout. Capture stdout format and exit code.

```bash
tmp="$(mktemp -d)"
cd "$tmp"
timeout 45s claude --output-format stream-json --verbose --include-partial-messages -p "Reply with the word ok and do not edit files."
timeout 45s codex exec --json "Reply with the word ok and do not edit files."
timeout 45s opencode run --format json "Reply with the word ok and do not edit files."
timeout 45s kimi --prompt "Reply with the word ok and do not edit files." --output-format stream-json
timeout 45s agent -p --output-format stream-json --trust "Reply with the word ok and do not edit files."
```

For continue/resume, create a first harmless session in the same temp directory, then run the continue flag. Do not use production repos for first-pass adapter experiments.

## Repo Tests And Static Checks

```bash
cd /Users/roshansilva/Documents/command-center/daemon/lancerd
go test . -run 'TestContinueArgv|TestContinueRunNewRunIDAndGate|TestE2ERouterContinue'
go test . -run 'TestAgentHookBuildsStructuredEventPerVendor|TestWireClaudeHook|TestStreamJSON'
bash -n ../../docs/codex-lancer-hook.sh
bash -n ../../docs/opencode-lancer-hook.sh
python3 -m json.tool ../../docs/codex-hooks.json >/dev/null
python3 -m json.tool ../../docs/opencode-hooks.json >/dev/null
codex exec resume --help | rg -- '--sandbox|--ask-for-approval|dangerously'
```
