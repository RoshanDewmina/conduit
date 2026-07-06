# Audit Report Template

Save to chat by default. Write to `/Users/roshansilva/Downloads/` only when the user requests a file artifact.

Suggested filename pattern: `lancer-conversation-audit-YYYY-MM-DD.md`

---

```markdown
# Lancer Cross-Platform Conversation Audit

**Generated:** YYYY-MM-DD  
**Window:** N days (start → end)  
**Repo anchor:** /path/to/repo  
**Platforms:** Claude Code, Codex, Cursor  
**Pass 1 agents:** claude / codex / cursor (list)  
**Pass 2 verifier:** (agent name / cursor-agent composer-2.5)

## Executive Summary

2–5 bullets: highest-signal outcomes — what shipped, what repeated, what's still open.

## Session Ledger Summary

| Platform | Sessions inventoried | Deep-read | Stubs skipped | Forks noted |
|---|---|---|---|---|
| Claude | | | | |
| Codex | | | | |
| Cursor | | | | |

## Findings

(Use finding-schema.md for every row. Group by category or status.)

### Verified / Shipped

### Attempted / Partial

### Planned / Discussed

### Abandoned / Superseded

### Unresolved (with reason Pass 2 still open)

## Cross-Platform Themes

- Repeated topics (≥3 sessions)
- Contradictions resolved by Pass 2
- Duplicate work / re-audited areas

## Methodology Notes

- Ledger sources and any query limitations
- Stub sessions excluded from deep-read (list IDs)
- Fork handling decisions
- Pass 2 commands run (`git log`, `gh pr list`, file paths checked)

## Appendix: Session Index

| Platform | Session ID | Title hint | Path / key | Deep-read |
|---|---|---|---|---|
```

---

## Quality Bar

A report is **not done** until:

1. Every in-scope session in the window was ledgered
2. Every non-stub session was fully read in Pass 1
3. Every finding has all required fields
4. Pass 2 re-checked status for non-`discussed` findings
5. Executive summary does not repeat stale claims that Pass 2 disproved
