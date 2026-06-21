# Vendor CLI Adapter Matrix

This matrix is a starting point. Re-run local help and check official docs before changing adapter behavior.

## Local Baseline Verified 2026-06-18

- Claude Code local version was newer than the generated report claimed: `claude --version` returned `2.1.181 (Claude Code)` while the report said `2.1.179`.
- Codex local version: `codex-cli 0.135.0`.
- OpenCode local version: `1.17.7`.
- Kimi local version: `0.15.0`, while public changelog entries already showed newer 0.17.x releases.
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
```

## Current Conduit Code Entry Points

- Launch argv: `daemon/conduitd/dispatch.go` `agentArgv`
- Continue argv: `daemon/conduitd/dispatch.go` `continueArgv`
- Policy/budget gates: `dispatcher.dispatch` and `dispatcher.continueRun`
- RPC surface: `daemon/conduitd/server.go`
- Relay surface: `daemon/conduitd/e2e_router.go`
- Codex hook draft: `docs/codex-conduit-hook.sh`, `docs/codex-hooks.json`
- Codex risk note: `docs/audit/CODEX_GATING.md`
- OpenCode hook draft: `docs/opencode-conduit-hook.sh`, `docs/opencode-hooks.json`
- Installer/doctor coverage: `daemon/conduitd/install.go`, `daemon/conduitd/hook_install.go`, related tests

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
- `CONDUIT_CODEX_UNSAFE=1` is an explicit opt-in, not a default.
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
- Kimi may not be included in Conduit status collection or hook installation. Inspect current code before claiming first-class parity.

## Smoke Checks

Run smoke checks in a temp directory with harmless prompts and a timeout. Capture stdout format and exit code.

```bash
tmp="$(mktemp -d)"
cd "$tmp"
timeout 45s claude --output-format stream-json --verbose --include-partial-messages -p "Reply with the word ok and do not edit files."
timeout 45s codex exec --json "Reply with the word ok and do not edit files."
timeout 45s opencode run --format json "Reply with the word ok and do not edit files."
timeout 45s kimi --prompt "Reply with the word ok and do not edit files." --output-format stream-json
```

For continue/resume, create a first harmless session in the same temp directory, then run the continue flag. Do not use production repos for first-pass adapter experiments.

## Repo Tests And Static Checks

```bash
cd /Users/roshansilva/Documents/command-center/daemon/conduitd
go test . -run 'TestContinueArgv|TestContinueRunNewRunIDAndGate|TestE2ERouterContinue'
go test . -run 'TestAgentHookBuildsStructuredEventPerVendor|TestWireClaudeHook|TestStreamJSON'
bash -n ../../docs/codex-conduit-hook.sh
bash -n ../../docs/opencode-conduit-hook.sh
python3 -m json.tool ../../docs/codex-hooks.json >/dev/null
python3 -m json.tool ../../docs/opencode-hooks.json >/dev/null
codex exec resume --help | rg -- '--sandbox|--ask-for-approval|dangerously'
```
