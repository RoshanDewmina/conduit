# Agent Tools Integration Matrix

> Integration research for a vendor-agnostic **conduitd adapter SPI**.
> conduitd (Go) sits at each coding agent's tool-call approval chokepoint and forwards
> approval requests to the Conduit iOS app. This document inventories the popular AI
> coding agents, probes their **approval surface** (the single most important seam),
> their **local-model** support, and their **status/usage state**, then rates how hard
> each is to wire into conduitd given the existing opencode/codex/claude adapters.
>
> Captured: 2026-06-13 · macOS arm64 (Darwin 27.0.0) · all installs by explicit user authorization.

## How conduitd integrates (the two seams every adapter must satisfy)

Grounded in the existing adapters (`daemon/conduitd/`):

1. **Approval seam** — a vendor **pre-tool hook** runs and shells out to
   `conduitd agent-hook` (see `hook.go:runAgentHook`). The hook passes
   `--agent --kind --command --cwd --risk` plus structured `--tool-name --tool-use-id
   --session-id --tool-input`. conduitd builds an `ApprovalEvent`
   (`approval.go:17`), forwards it over the unix socket to the resident `serve`
   process, blocks until the phone decides, and maps the decision to an **exit code**:
   - `exit 0` = approved → tool proceeds
   - `exit non-zero` = denied/timeout → tool blocked
   - Fail-safety (verified live, daemon down): read-only kinds fail **open** with
     `CONDUIT_HOOK_READONLY_FAIL_OPEN=1` (exit 0); mutating/critical fail **closed**
     (exit 1) — `hook.go:hookShouldHold`.
   - Canonical agent IDs are normalized in `agent_registry.go:normalizeAgentSource`
     (`claudeCode`/`codex`/`cursor`/`gemini`/`opencode`).

   The reference vendor hook is **already installed on this machine** at
   `~/.codex/hooks/conduit-hook.sh` (wired via `~/.codex/hooks.json` `PreToolUse`).
   It: parses the pre-tool JSON on stdin → classifies tool→`kind`/`risk` →
   **auto-approves read-only tools/MCP** locally → otherwise calls
   `conduitd agent-hook --agent codex …` → maps exit code. Repo templates live in
   `docs/conduit-hook.sh` (Claude), `docs/codex-conduit-hook.sh`,
   `docs/opencode-conduit-hook.sh` + their `*-hooks.json`.

2. **Status seam** — a `collectXStatus(home)` reader (`agent_status_*.go`) mines the
   vendor's config dir for `loggedIn` / `model` / `usageUSD` / `sessionCount`,
   returning an `AgentVendorStatus` (`agent_status.go:14`). Wired into the fan-out at
   `agent_status.go:33` (`collectAgentStatus`).

**Therefore an adapter = `{a hook that calls `conduitd agent-hook`} + {a `collectXStatus`
reader}`.** The hook is the load-bearing half; the status reader is best-effort.

---

## Summary matrix

| Tool | Installed version | Approval / permission surface | Local models? | Status/usage reader | Adapter effort |
|---|---|---|---|---|---|
| **Claude Code** | `2.1.177` (already installed — runtime) | `PreToolUse` hook, `settings.json` → `hooks.PreToolUse[].hooks[].command`; JSON on stdin; exit code / JSON `decision` | Yes (via Bedrock/Vertex/proxy `ANTHROPIC_BASE_URL`; not first-class Ollama) | **Live** — `agent_status_claude.go` (`~/.claude/.credentials.json`, `settings.json` model, `statusline.jsonl` cost) | **Trivial** (shipped) |
| **Codex** (OpenAI) | `codex-cli 0.139.0` (already installed) | `PreToolUse` hook, `~/.codex/hooks.json` → `hooks.PreToolUse`; JSON on stdin; exit code. Hook **trust** required (`/hooks` or `--dangerously-bypass-hook-trust`) | Via `--oss`/OSS providers + `[model_providers]` in `config.toml` (OpenAI-compatible `base_url`) | **Live** — `agent_status_codex.go` (`~/.codex/auth.json`, `usage.json`) | **Trivial** (shipped; hook already installed here) |
| **opencode** | `1.17.3` (already installed) | `PreToolUse` hook, `~/.config/opencode/hooks/…` per `opencode-hooks.json`; Claude-shape JSON on stdin (`session_id,cwd,tool_name,tool_input`); exit code. Also a **plugin** API + **permission** config | **Yes, first-class** — provider blocks in `opencode.json` (LM Studio/OpenRouter on this box) | **Live but path-stale** (see Findings) — `agent_status_opencode.go` reads `~/.local/share/opencode/config.json`; real config is `~/.config/opencode/opencode.json` | **Trivial** (shipped) — but fix status path |
| **goose** (Block) | `1.37.0` (installed today, brew formula `block-goose`) | **No external pre-tool hook.** Approval is internal: `GOOSE_MODE` in `~/.config/goose/config.yaml` (`auto`/`approve`/`chat`/`smart_approve`); `smart_approve` uses an LLM `PermissionJudge`. Only seam: wrap goose as an **MCP client** and gate at an MCP server, or use ACP | **Yes, first-class** — `goose local-models` (GGUF/HF), Ollama/OpenAI-compatible providers via `goose configure` → `config.yaml` | None yet (would read `~/.config/goose/config.yaml`, `~/.local/share/goose/sessions/sessions.db`) | **Hard** — no external approval chokepoint; needs MCP-proxy or upstream hook PR |
| **aider** | `0.86.2` (installed today, `uv tool install`) | **Interactive prompt only.** `--yes-always` blanket-approves; shell commands are *suggested* (`--suggest-shell-commands`) then y/n confirmed — no programmatic pre-exec callback, no hook | **Yes** — `--model ollama/…`, `--openai-api-base` (LM Studio/OpenRouter), env `OLLAMA_API_BASE` | None (state in `.aider.*` per-repo; `~/.aider*` is sparse) | **Hard** — would need a wrapper PTY or a fork; no native gate |
| **Cline** (VS Code ext) | n/a (extension; SDK `@cline/core`) | Per-category **Auto-Approve** toggles (read/edit/safe-cmd/all-cmd/browser/MCP); model marks each cmd `requires_approval`. **No external approval routing.** SDK `Agent.run()` emits events but the docs expose no approval callback | Yes (Ollama/LM Studio/OpenRouter in provider settings) | VS Code `globalState` (opaque); no file reader | **Hard** — closed approval loop; only path is an SDK fork or an MCP-gated subset |
| **gemini-cli** (Google) | `0.46.0` (already installed; **reportedly retiring 2026-06-18**) | **`BeforeTool` hook** (settings.json `hooks`), Claude-compatible: `gemini hooks migrate` converts Claude `PreToolUse`→`BeforeTool`. stdin JSON `HookInput`; output JSON `decision: block\|deny\|approve\|allow\|ask` + `reason`. Also `--approval-mode` + Policy Engine | Yes (`gemini` + custom/compatible endpoints; OpenAI-compat providers) | Partial-feasible — `~/.gemini/oauth_creds.json`, `settings.json` model, `google_accounts.json` | **Moderate** — hook exists & is Claude-shaped, but output is **JSON decision** not exit-code; needs a tiny shim + retirement risk |

Other notables scanned (no deep install): **Cursor CLI / cursor-agent** — placeholder `cursor` already reserved in `normalizeAgentSource`; Cursor Agent has a CLI but approval is its own UI; effort moderate. **Continue** — `continue` on PATH is the zsh builtin (false positive), not the Continue CLI; Continue is IDE-centric, no external hook. **Sourcegraph Amp / RooCode / Kilo Code / Zed agent** — none installed; all IDE/extension-embedded with internal approval UIs (RooCode/Kilo are Cline forks → same per-category auto-approve model, same "Hard" rating).

---

## Per-tool findings

### Claude Code — *runtime; documented only, not reinstalled*
1. **Install** — already present: `/opt/homebrew/bin/claude`, `claude --version` → `2.1.177 (Claude Code)`. Not touched.
2. **Approval surface** — `PreToolUse` hook in `~/.claude/settings.json` →
   `hooks.PreToolUse[].hooks[] = {type:"command", command:"bash ~/.claude/hooks/conduit-hook.sh"}`
   (template: `docs/claude-settings-hook.json`). Payload JSON on stdin
   (`tool_name,tool_input,tool_use_id,session_id,cwd,permission_mode`). Hook signals via
   exit code (and supports JSON `decision`). Conduit hook installed at
   `~/.claude/hooks/conduit-hook.sh`.
3. **Local models** — via gateway base-url (Bedrock/Vertex/proxy); no first-class Ollama.
4. **Status reader** — **live**: `agent_status_claude.go` reads `~/.claude/.credentials.json`
   (loggedIn), `settings.json` `model`, `~/.claude/statusline.jsonl` (cost), counts
   `~/.claude/projects/**/*.jsonl` sessions.
5. **Adapter effort** — **Trivial**; this is the canonical shipped path.

### Codex (OpenAI Codex CLI) — *already installed; hook already live*
1. **Install** — already present: `~/.hermes/node/bin/codex`, `codex --version` → `codex-cli 0.139.0`.
2. **Approval surface** — `~/.codex/hooks.json` declares
   `hooks.PreToolUse[{matcher:"Bash|apply_patch|Edit|Write|mcp__.*", hooks:[{type:"command",
   command:"bash ~/.codex/hooks/conduit-hook.sh", timeout:150}]}]`. **The Conduit hook is
   already installed and wired** (`~/.codex/hooks/conduit-hook.sh`) — it calls
   `conduitd agent-hook --agent codex --kind … --command … --cwd … --risk …` and maps
   exit code (rejected → `exit 2`). Note `config.toml` has `approval_policy = "never"` +
   `sandbox_mode = "danger-full-access"` — Codex's own gate is off, so the Conduit hook is
   the *only* approval chokepoint here. Hook **trust** is enforced (`config.toml`
   `[hooks.state]`); bypass via `--dangerously-bypass-hook-trust`.
3. **Local models** — OSS/OpenAI-compatible providers via `[model_providers]` `base_url` in
   `config.toml`; `--oss` flag.
4. **Status reader** — **live**: `agent_status_codex.go` reads `~/.codex/auth.json`
   (loggedIn), `usage.json` (`today_usd`/`cost_usd`), counts `~/.codex/sessions/**/*.jsonl`.
5. **Adapter effort** — **Trivial** (shipped + already deployed on this machine).

### opencode — *already installed*
1. **Install** — already present: `/opt/homebrew/bin/opencode` → `1.17.3`.
2. **Approval surface** — Claude-compatible `PreToolUse` hooks (`docs/opencode-hooks.json`
   matcher `Bash|bash|apply_patch|Edit|Write|edit|write|patch`; hook at
   `~/.config/opencode/hooks/conduit-hook.sh`). Payload mapping captured by
   `opencode_hook.go:approvalEventFromOpencodeFixture` (`session_id,cwd,hook_event_name,
   tool_name,tool_use_id,tool_input`). opencode also exposes a **plugin** API
   (`opencode plugin`) and a **permission** config block, and an **ACP** server.
3. **Local models** — **first-class.** This box's `~/.config/opencode/opencode.json`:
   `model: "openrouter/openai/gpt-oss-20b:free"`, `small_model: "lmstudio/google/gemma-4-e4b"`,
   with a custom `provider.lmstudio` block (`baseURL: http://127.0.0.1:1234/v1`) — proof of
   LM Studio + OpenRouter wiring.
4. **Status reader** — **live but path-stale**: `agent_status_opencode.go` reads
   `~/.local/share/opencode/{config.json,usage.json}`, but the real config on 1.17.3 is
   `~/.config/opencode/opencode.json` and runtime state is `~/.local/share/opencode/opencode.db`
   (SQLite). So the reader currently reports `loggedIn:false` / no model here. **Bug to fix.**
5. **Adapter effort** — **Trivial** (shipped); patch the status path.

### goose (Block) — *installed today*
1. **Install** — `bash <(curl -fsSL .../block/goose/releases/download/stable/download_cli.sh)`
   with `CONFIGURE=false` → `/Users/roshansilva/.local/bin/goose`, `goose --version` → `1.37.0`.
   (brew alternative: `brew install --cask block-goose` for the desktop app.)
2. **Approval surface** — **no external pre-tool hook.** Approval is **internal** to the
   agent: `GOOSE_MODE` in `~/.config/goose/config.yaml` ∈ {`auto`, `approve`, `chat`,
   `smart_approve`}. `smart_approve` runs an in-process LLM `PermissionJudge` /
   `PermissionInspector` to auto-allow read-only and prompt on state-changing ops. There is
   **no documented callback for a third party to gate a call before exec.** The realistic
   conduitd seams: (a) run goose's tools through an **MCP server** that conduitd controls and
   gate there, or (b) drive goose via its **ACP** server (`goose acp`) and intercept at the
   ACP layer, or (c) upstream a hook PR. `goose plugin install <git-url>` exists but plugins
   extend tools, not the approval gate.
3. **Local models** — **first-class.** `goose local-models {search,download,list}` pulls GGUF
   from HuggingFace; Ollama/OpenAI-compatible providers configured via `goose configure` →
   `~/.config/goose/config.yaml` (`GOOSE_PROVIDER`/`GOOSE_MODEL`).
4. **Status reader** — none yet. Feasible: parse `~/.config/goose/config.yaml`
   (`GOOSE_PROVIDER`/`GOOSE_MODEL`), session count from
   `~/.local/share/goose/sessions/sessions.db`.
5. **Adapter effort** — **Hard.** No external approval chokepoint; requires an MCP-proxy
   shim or an upstream hook contribution. Status reader is easy by comparison.

### aider — *installed today*
1. **Install** — pipx failed (built `scipy` from sdist; no Fortran toolchain). Reinstalled via
   `uv tool install --python 3.12 aider-chat` (prebuilt wheels) → `~/.local/bin/aider`,
   `aider --version` → `aider 0.86.2`.
2. **Approval surface** — **interactive prompt only.** No hook/plugin/callback. `--yes-always`
   blanket-approves every prompt; shell commands are only *suggested*
   (`--suggest-shell-commands`/`--no-suggest-shell-commands`) and then confirmed y/n in the
   REPL. There is no pre-exec interception point a daemon can attach to.
3. **Local models** — yes: `--model ollama/<m>` (env `OLLAMA_API_BASE`),
   `--openai-api-base` for LM Studio / OpenRouter, `--model openrouter/<m>`.
4. **Status reader** — none; per-repo state in `.aider.*`, no central logged-in/usage file.
5. **Adapter effort** — **Hard.** Would need a PTY wrapper that screen-scrapes the confirm
   prompt, or a fork. Poor fit.

### Cline (VS Code extension) — *documented; no CLI to install*
1. **Install** — VS Code Marketplace extension (no standalone CLI). SDK published as
   `@cline/core` / `@cline/agents` / `@cline/llms` (`Agent.run()` + event subscription).
2. **Approval surface** — per-category **Auto-Approve** toggles: *Read project files / Read
   all files / Edit project files / Edit all files / Execute safe commands / Execute all
   commands / Use the browser / Use MCP servers*. Approval is evaluated per tool call; the
   model tags each command with a `requires_approval` flag. **No external routing** of
   approvals is exposed; the SDK docs surface events but no approval callback. Settings live
   in VS Code `globalState` (opaque).
3. **Local models** — yes (Ollama/LM Studio/OpenRouter in provider settings).
4. **Status reader** — none practical (VS Code global storage, not a flat file).
5. **Adapter effort** — **Hard.** Closed approval loop. Only realistic conduitd hook is to
   restrict Cline to **MCP-server tools** and gate at the MCP server, or fork the SDK.

### gemini-cli (Google) — *already installed; retiring ~2026-06-18*
1. **Install** — already present: `~/.hermes/node/bin/gemini` → `0.46.0`. Not touched.
2. **Approval surface** — **`BeforeTool` hook** (the genuine standout). `gemini hooks migrate`
   converts Claude `PreToolUse`→`BeforeTool` (also `PostToolUse`→`AfterTool`,
   `UserPromptSubmit`→`BeforeAgent`, …) and tool names `Bash`→`run_shell_command`,
   `Edit`→`replace`, `Write`→`write_file` (`packages/cli/src/commands/hooks/migrate.ts`).
   Hook reads `HookInput` JSON on stdin; returns `HookOutput` JSON with
   `decision: 'block'|'deny'|'approve'|'allow'|'ask'` + `reason`
   (`packages/core/src/hooks/types.ts`; `isBlockingDecision()` = `block||deny`). Also
   `--approval-mode {default,auto_edit,yolo,plan}`, `-y/--yolo`, and a Policy Engine.
3. **Local models** — yes via OpenAI-compatible/custom endpoints; OAuth-personal here.
4. **Status reader** — feasible: `~/.gemini/oauth_creds.json` (loggedIn),
   `~/.gemini/settings.json`/`state.json` (model), `google_accounts.json`.
5. **Adapter effort** — **Moderate.** The hook exists and is Claude-shaped, so the Conduit
   hook script ports almost directly — **but** Gemini wants a **JSON decision object** on
   stdout, not just an exit code, so a thin wrapper must translate conduitd's exit code into
   `{"decision":"approve"}` / `{"decision":"deny","reason":…}`. Tempered by the reported
   2026-06-18 retirement (verify before investing).

---

## Adapter SPI recommendation

Across all tools, exactly **two shapes** of approval surface exist:

- **(A) External pre-tool hook** that runs a command, hands it JSON on stdin, and reads a
  verdict — Claude Code, Codex, opencode, **Gemini**. This is conduitd's home turf.
- **(B) Closed/internal approval** (in-agent mode, model-tagged `requires_approval`, or
  interactive prompt) with no external attach point — goose, aider, Cline, RooCode, Kilo.
  The only universal bridge for class B is **MCP**: run the agent's tools through an MCP
  server conduitd owns and gate there.

So the minimal SPI is:

```
ConduitAdapter:
  # 1. APPROVAL (required) — exactly one transport:
  approval:
    transport: "hook" | "mcp"           # class A → hook;  class B → mcp
    # hook: vendor config writes a PreToolUse/BeforeTool entry that execs
    #       `conduitd agent-hook` (the existing CLI IS the SPI).
    emit:   conduitd agent-hook
              --agent <canonicalID>      # normalizeAgentSource()
              --kind  <command|patch|fileWrite|fileDelete|network|browser>
              --command <...> --cwd <...> --risk <low|medium|high|critical>
              --tool-name --tool-use-id --session-id --tool-input   # structured, optional
    decode: 0 => approve ;  non-zero => deny      # plus optional JSON-decision shim (Gemini)

  # 2. STATUS (optional, best-effort) — one function:
  status: collect<Vendor>Status(home) -> AgentVendorStatus
            { loggedIn, model, sessionCount, usageUSD, usagePeriod }
          # reads the vendor's config/creds/usage files under $HOME
```

Concretely, **`conduitd agent-hook` already *is* the SPI** for class A — adding a vendor is:
(1) a `<vendor>-conduit-hook.sh` that classifies tool→`kind`/`risk` and calls `agent-hook`
(copy `docs/codex-conduit-hook.sh`), (2) a `<vendor>-hooks.json` install fragment, (3) a
canonical ID in `normalizeAgentSource`, and (4) an optional `collect<Vendor>Status`. The only
new primitive worth adding is an **output-format flag on `agent-hook`** (e.g.
`--emit json-decision`) so the same binary can satisfy Gemini's `HookOutput` JSON contract
without a per-vendor wrapper. For class B, ship a single **conduit-mcp gateway** (one MCP
server that wraps the dangerous tools and calls `agent-hook` internally) — that one component
covers goose, Cline, RooCode, and Kilo at once.

**Priorities:** Gemini (moderate, hook already Claude-shaped — but check retirement first);
Cursor (placeholder reserved, class A-ish); then the class-B MCP gateway to unlock
goose/Cline/Roo/Kilo together. aider is the weakest fit (no external gate at all).

---

## Install log appendix (reproducible / reversible)

Already present (NOT installed/modified): `claude 2.1.177`, `codex 0.139.0`,
`opencode 1.17.3`, `gemini 0.46.0`, `cursor 3.7.36`, `bun 1.3.9`, `pipx`, `go`, `brew`.

Installed today:

```bash
# goose 1.37.0  — official CLI script (no interactive configure)
cd /tmp
curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh -o goose_install.sh
CONFIGURE=false bash goose_install.sh
#   → /Users/roshansilva/.local/bin/goose   (243 MB self-contained binary)
# reverse:  rm /Users/roshansilva/.local/bin/goose  &&  rm -rf ~/.config/goose ~/.local/share/goose ~/.local/state/goose

# aider 0.86.2  — pipx FAILED (scipy sdist needs Fortran); use uv tool with py3.12 wheels
pipx uninstall aider-chat            # clean the half-failed pipx venv
uv tool install --python 3.12 aider-chat
#   → /Users/roshansilva/.local/bin/aider
# reverse:  uv tool uninstall aider-chat
```

Not installed (by design): **ollama** (absent; local-model story already covered by
goose `local-models` + opencode LM Studio/OpenRouter + aider `--openai-api-base`).
**Cline / Continue / Amp / RooCode / Kilo / Zed** — IDE/extension-embedded, no CLI to
install. (`continue` on PATH is the zsh shell builtin, a false positive.)

Verification performed (no secrets printed):
- Read live reference hook `~/.codex/hooks/conduit-hook.sh` + `~/.codex/hooks.json`.
- Built conduitd (`go build` in `daemon/conduitd`) and exercised `agent-hook`:
  read-only + `CONDUIT_HOOK_READONLY_FAIL_OPEN=1` → exit 0 (proceed); mutating high-risk with
  daemon down → exit 1 (fail-closed). A live `~/.conduit/conduitd.sock` is present.
- Confirmed Gemini hook contract from source (`migrate.ts` event/tool mapping; `types.ts`
  `HookDecision`/`HookOutput`).
