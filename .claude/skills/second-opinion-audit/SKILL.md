---
name: second-opinion-audit
description: Use when the owner asks you to read a conversation, report, or handoff from another AI tool (Claude Code, Codex, Cursor, OpenCode, Kimi) and independently verify its claims — not summarize it. Distrust self-reported status by default; check live repo state before confirming "done", "fixed", "merged", or "verified".
---

# Second Opinion Audit

## Core rule

**Distrust the other tool's self-reported status by default.** A transcript or report saying
"done", "fixed", "verified", or "merged" is a **claim**, not a fact, until you check it against
live repo state, current CLI output, and (when relevant) open PRs or later sessions. Your job is
not to restate the other tool's narrative in different words — it is to independently verify each
load-bearing assertion and report what is actually true now.

This skill pairs with `agent-session-history-reader` (finding the source conversation) and
`lancer-verification-gate` (running the right build/test gate when code claims need execution
proof). Use this skill when the deliverable is a verdict on someone else's claims; use the others
when you need to locate sessions or prove a change compiles.

## When to use

Invoke when the owner asks you to:

- Read a conversation or report from a **different** AI tool and give a second opinion
- Verify whether another agent's claims are still accurate
- Audit a handoff, audit doc, or "here's what we shipped" summary before acting on it
- Check whether "unresolved" items from an older session are still open

Do **not** use this skill when the owner only wants a summary with no verification, or when you
are doing original implementation work (use `lancer-context-onboarding` + `lancer-verification-gate`
instead).

## Citation format

For every load-bearing assertion you evaluate, cite it in this form so each claim is independently
checkable:

```text
[N] path/to/file:line -> claim being checked
```

Rules:

- One citation per checkable claim. Bundle related sub-claims only when they share one file:line.
- Use repo-relative paths and real line numbers from the current tree (or the cited commit if
  auditing historical state).
- Quote the other tool's exact wording for status words ("merged", "fixed", "verified") — do not
  soften or upgrade their language when restating.

## Verdict taxonomy

Assign exactly one verdict per load-bearing claim:

| Verdict | Meaning |
|---|---|
| **confirmed** | Checked against live repo state (and commands below); the claim holds as stated. |
| **stale** | Was plausible when written but is wrong now — superseded by later commits, merged PRs, reverted work, or changed code. |
| **needs-nuance** | Directionally right but missing important context, scope limits, or caveats that change how someone should act on it. |

For any claim marked **confirmed** at **high severity** (ship decisions, security, "merged to
master", "loop closed", "P0 resolved"), add an explicit **"what would make me wrong"** check: one
or two concrete falsifiers you did not find but that would overturn the verdict if true.

## Verification checklist

Run these checks yourself. Quote real command output — do not paraphrase.

### "Implemented" / "fixed" / "done" (code claims)

1. Locate the cited files at the cited lines (`rg`, read file, or `git show <rev>:path`).
2. Confirm the described behavior exists in the **current** tree (or state the commit/branch you
   audited if not on `master`).
3. When behavior matters, run the gate from `lancer-verification-gate` and paste pass/fail output.

### "Merged" / "shipped" / "on master" (integration claims)

For each cited commit hash or branch name:

```bash
git merge-base --is-ancestor <commit-or-branch> master && echo ANCESTOR || echo NOT_ANCESTOR
git log -1 --oneline <commit>          # proves the hash exists and what it is
git show -s --format=%s <commit>       # subject line evidence
gh pr list --head <branch> --state all # open/merged/draft PR reality
gh pr view <number> --json state,mergedAt,baseRefName  # when a PR number is cited
```

Interpretation:

- `NOT_ANCESTOR` means **not merged to master** — downgrade "merged" to "exists on a branch" unless
  a different base branch was explicitly scoped and verified.
- **DRAFT** PRs are not shipped. "Implemented and tested on a feature branch" ≠ "merged".
- If the other tool cites cherry-picks or a stack, check **each** hash independently.

### "Verified" / "tests pass" (evidence claims)

- Require the actual command and full relevant output snippet, not a summary line from the transcript.
- If you cannot reproduce the same command in this environment, verdict **needs-nuance** and say what
  was checked instead.

### "Unresolved" / "still open" / "blocked" (gap claims)

Before forwarding a gap as still open:

1. Search later commits: `git log --oneline --since=<report-date> -- path/to/area`
2. Search later sessions ( `agent-session-history-reader` ) for the same topic keywords.
3. Search merged PRs: `gh pr list --state merged --search "keyword" --limit 20`

If a later session or commit resolved it, verdict **stale** and point to the resolving evidence.

## Report structure

Deliver findings in this order:

1. **Scope** — what you read, which repo/branch, audit date.
2. **Executive verdict** — 2–4 sentences on what the other tool got right vs wrong.
3. **Claim table** — numbered `[N]` citations with verdict + one-line rationale each.
4. **Command evidence** — verbatim snippets for merge/PR/log checks (trim only noise).
5. **Residual risks** — items still open after your audit, with what would close them.
6. **What would make me wrong** — for high-severity confirmed claims only.

## Worked example (2026-07-06)

**Other tool's claim (Cursor report):** Siri Phase 2 was "merged from a single Cursor session,"
citing three commit hashes as proof of completion.

**Second-opinion procedure:**

```text
[1] (transcript) -> claim: Siri Phase 2 merged from a single Cursor session (commits abc123, def456, ghi789)
```

```bash
git merge-base --is-ancestor abc123 master && echo ANCESTOR || echo NOT_ANCESTOR
# NOT_ANCESTOR

git merge-base --is-ancestor def456 master && echo ANCESTOR || echo NOT_ANCESTOR
# NOT_ANCESTOR

git merge-base --is-ancestor ghi789 master && echo ANCESTOR || echo NOT_ANCESTOR
# NOT_ANCESTOR

gh pr list --search "siri" --state all --limit 10
# Shows related PRs still in DRAFT state
```

**Verdicts:**

| # | Verdict | Rationale |
|---|---|---|
| [1] | **stale** (status word) / **needs-nuance** (work exists) | Commits exist on a feature branch and work may be implemented and tested, but none are ancestors of `master` and related PRs were still DRAFT — so "merged" is false. Fair correction: *implemented and tested on an unmerged feature branch*. |

**What would make me wrong:** If "merged" referred to a different default branch (not `master`) or
an integration branch that was intentionally not `master` — would need `git branch -a --contains
<hash>` and explicit base-branch scope from the owner.

## Anti-patterns

- Summarizing the other tool's report without running independent checks.
- Replacing their "merged" with your own "merged" because the commits exist locally.
- Reporting unresolved gaps without checking for later fixes.
- Mixing verdict labels ("mostly confirmed", "probably stale") — use the taxonomy above.
- Citing generated reports or conversation text as evidence without a repo/CLI check.
