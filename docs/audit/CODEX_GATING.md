# Codex Gating Analysis — Lancer PreToolUse Hook Coverage

## Executive Summary

**Risk: HIGH.** Currently, Lancer's PreToolUse gating hook covers **only Claude Code**.
Dispatched codex agent runs have NO approval gating through Lancer. Adding the
`--dangerously-bypass-approvals-and-sandbox` flag to codex's `exec` command (to
resolve the hanging issue) would result in **UNGATED, UNCONSTRAINED tool execution**
on a dispatched codex agent.

## Hook Coverage Analysis

### What the hook installs

`hook_install.go:16` — the Claude PreToolUse command:
```go
const claudeHookCommand = "bash ~/.claude/hooks/lancer-hook.sh"
```

This is installed to `~/.claude/settings.json` under `hooks.PreToolUse`.

### What it does NOT install

- **Codex:** There is NO installer for a codex PreToolUse hook in `hook_install.go`.
  The `install_codex_hook()` function in `install.sh` (line 143-158) drops the hook
  script to `~/.codex/hooks/lancer-hook.sh` but:
  1. It only runs when the user passes `--hooks codex` or `--hooks both` — not the default.
  2. It copies the script file but does NOT wire it into codex's equivalent of
     `settings.json`. Codex may not even support a PreToolUse hook mechanism.
  3. The codex hook script itself (`docs/codex-lancer-hook.sh`) would need to exist.

- **OpenCode:** There is a TODO at `hook_install.go:42-44` noting this is not yet
  implemented: "wire the OpenCode PreToolUse hook ... once OpenCode settings-merge is in scope."

### Current `agentArgv` for codex

`dispatch.go:41-46`:
```go
case "codex":
    argv := []string{"codex", "exec"}
    if model != "" {
        argv = append(argv, "--model", model)
    }
    return append(argv, prompt), true
```

This constructs `codex exec <prompt>`, which opens an interactive approval session
in codex's own sandbox/approval system. On a headless relay dispatch (no TTY), this
**hangs indefinitely** because codex waits for a human-in-the-loop approval that
will never come.

## The Security Tradeoff

Adding `--dangerously-bypass-approvals-and-sandbox` would fix the hang, but:

- **With Claude Code:** Lancer's PreToolUse hook intercepts every tool call (Bash,
  Write, Patch, etc.) and requests approval on the phone. The agent cannot execute
  any mutating action without the user tapping "Approve" on their iOS device.

- **With codex (currently):** There IS no Lancer PreToolUse hook for codex. Even if
  the hook script existed, codex may not call it. Adding the bypass flag means codex
  runs **completely unconstrained** — it can read, write, execute, and delete any file
  the daemon's user has access to, without any approval.

## Recommendation

Keep codex behind a feature flag gated by an environment variable defaulting to OFF:

```go
case "codex":
    argv := []string{"codex", "exec"}
    if model != "" {
        argv = append(argv, "--model", model)
    }
    if os.Getenv("LANCER_CODEX_UNSAFE") == "1" {
        argv = append(argv, "--dangerously-bypass-approvals-and-sandbox")
    }
    return append(argv, prompt), true
```

This means:
- **Default (UNSET):** codex hangs on dispatch (same as today) — safe but broken.
- **Explicit opt-in:** user sets `LANCER_CODEX_UNSAFE=1` → codex runs ungated.

The hang is the safer failure mode. Users who understand the risk and have
alternative gating (file system permissions, read-only mounts, etc.) can opt in.

## Future State

Before codex can be shipped as a first-class agent alongside Claude Code:

1. **Codex PreToolUse hook parity:** Either codex supports a similar PreToolUse hook
   mechanism, or Lancer must intercept codex tool calls at a different layer (e.g.,
   wrapping the `codex` binary with a shim that implements the gating).

2. **installer coverage:** `lancerd install` must wire the codex hook identically
   to how it wires the Claude hook — script + settings merge.

3. **Verification:** `lancerd doctor` must check both Claude AND codex hook wiring.