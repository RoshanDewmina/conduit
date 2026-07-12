# Edge-case fan-out sweep — consolidated findings (2026-07-12)

Two parallel read-only agents over the surfaces merged today (PRs #95–#99), plus a live
attach test of a real 5.6MB / 911-event Claude Code session. Status key: → lane = being fixed
now; backlog = triaged, not blocking.

## Being fixed now
| Sev | Finding | Where | Lane |
|---|---|---|---|
| HIGH | "Full" observed-transcript import caps at 2MB keeping the OLDEST end, silently; no truncation flag | claude_transcript_adapter.go:99 | Y1 |
| HIGH | Observed import flattens the whole session into ONE turn → phone renders one megabyte markdown blob | conversation_store.go:1317 | Y1 |
| HIGH | Attach title ignores the transcript ai-title → garbage titles, search can't find the session (live-reproduced) | conversation_rpc.go attach | Y1 |
| HIGH | ThreadDetailView renders all turns eagerly (VStack, no windowing) → seconds-long hang on long threads | ThreadDetailView.swift:33,59 | Y2 |
| HIGH | Markdown parsed synchronously, uncached, per render; unterminated fence sends the whole string through AttributedString | ChatThreadChrome.swift:11-42 | Y2 |
| MED | refreshConversation ignores hasMore — one 2000-event page per open | ConversationSyncCoordinator.swift:150 | Y2 |
| MED | assistantText assembled from first 5000 events only | ConversationSyncCoordinator.swift:434 | Y2 |
| MAJOR | List merge regresses last_activity_at with a stale host snapshot → active thread drops down the list on foreground | ConversationSyncCoordinator/mapSummary + upsertConversationMirror:403 | Y2 follow-up (orchestrator) |

## Backlog (triaged minors)
- Case-insensitive pathKey collapses case-distinct dirs on case-sensitive (Linux) hosts — revisit with multi-host support.
- No NFC/NFD Unicode normalization → accented folder names can split into two rows.
- `~user` / `~x` pass isAbsolutePath and become bogus roots/send targets (daemon rejects at dispatch; fail-closed).
- Foreground refresh stacks overlapping 8s connect-waits while disconnected (wasted work, not a stall).
- Fresh-install backfill limited to host list RPC's 50 most recent (vs 200 local); >50 histories need paging.
- All Repos badge/list both cap at recent(200) — consistent, but silently truncates beyond 200.
- 16KB per-message cap has no "truncated" indicator; observed-continue 200-line tail window can misalign dropFirst on very active sessions.

## Verified NOT bugs
Empty/whitespace cwds, trailing-slash/case dupes in added repos, tilde suffix-collision folding,
and running-badge clobber on summary merge all held up under adversarial inputs.
