# Conduit Parallel Handoff Template

Use this when assigning work to subagents or external CLIs.

## Worker Prompt Template

```text
You are working in /Users/roshansilva/Documents/command-center.

Read first:
- /Users/roshansilva/.hermes/knowledge-base/AGENTS.md
- docs/agent-contract.md
- CLAUDE.md sections relevant to this lane
- <specific plan/doc>

Task:
<one concrete objective>

Owned files:
- <files this worker may edit>

Do not edit:
- <hot/shared files outside ownership>

Constraints:
- Other agents may be editing this repo. Do not revert unrelated changes.
- Preserve module boundaries from docs/agent-contract.md.
- Use explicit argv arrays for daemon agent launches. Never sh -c interpolated prompts.
- If you discover conflicting local changes, adapt or report the conflict instead of overwriting.

Acceptance checks:
- <exact commands or MCP checks>

Final response:
- files changed
- tests/checks run
- risks or follow-up needed
```

## Safe Parallel Examples

- Daemon dispatch tests and Swift sidebar visual planning can run in parallel if they do not share files.
- Documentation/report drafting can run beside code work if it writes to a separate file.
- Board pages can be split by one output file per flow, then merged by one owner.

## Unsafe Parallel Examples

- Two workers editing `AppRoot.swift`.
- Sidebar shell and Fleet routing both rewriting `NewChatTabView.swift`.
- Release checklist updates before a verifier has run the commands.
- Codex/Kimi adapter changes without a single owner validating help output and smoke tests.

## Merge Owner Checklist

- Re-run `git status --short`.
- Review each worker's diff and make sure no unrelated changes were reverted.
- Run the verification matrix for the combined blast radius.
- Update canonical docs only when the combined behavior is verified.

