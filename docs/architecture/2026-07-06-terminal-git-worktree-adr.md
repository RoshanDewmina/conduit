# ADR: Terminal, Git, and worktree — competitor scan (Orca, Happier, Omnara)

Date: 2026-07-06  
Status: **Accepted for V1** — control-surface only on phone; no phone PTY IDE.

## Context

Lancer's phone role is **steer and approve**, not replace the desktop IDE (`ARCHITECTURE.md` §0.1, master plan §3). Competitors explore heavier phone execution models. This ADR records what to steal vs skip for V1.

## Competitor summary (code-verified where noted in-repo)

| Product | Phone terminal | Session model | Relay / remote | Lancer overlap |
|---------|----------------|---------------|----------------|----------------|
| **Orca** | Full terminal UX target | Persistent sessions | SSH-focused | Lancer **skips** phone PTY; already has governed approvals + relay |
| **Happier** | Tauri/desktop + mobile companion patterns | Agent sessions | Varies | **Steal**: session resume metadata; **skip**: cloning desktop shell |
| **Omnara** | Mission-control / approval framing | Multi-agent | Push notifications | **Already has**: inbox + relay loop; **steal**: glanceable risk copy patterns only |

Prior in-repo research: `docs/product/2026-07-04-codex-verification-brief.md` (superseded by master plan; facts folded here).

## Decision

### Steal (daemon-mediated, phone read-only)

1. **Git status / diff summary RPCs** on `lancerd` — phone shows summary cards in Work Thread, not `git` REPL.
2. **Worktree list + active worktree label** — read-only fleet/workspace context.
3. **Run log tail** in Work Thread — extend existing run output store / relay events (no interactive terminal).

### Skip

1. **Full Orca-style phone terminal** — violates V1 architecture; deferred to V2+.
2. **Happier-style desktop replication** — wrong form factor.
3. **Phone-side `git merge` / ship actions** — master plan Tier 2; desktop remains write path.

### Lancer already has

- E2E relay + multi-machine fleet (`RelayFleetStore`, `E2ERelayBridge`)
- Governed approval loop (`ApprovalRelay`, policy fail-closed)
- Durable chat threads (`ChatConversationRepository`)
- Push + Live Activity hooks (`NotificationsKit`, `LancerLiveActivityManager`)

## Implementation notes (V1 scope)

- Extend `lancerd` RPC surface for `gitStatus`, `gitDiffStat`, `worktreeList` — **no new phone targets until RPC lands**.
- Work Thread consumes relay events + RPC summaries; keep `CursorWorkThreadView` read-only.
- Do not reintroduce deleted `WorktreesFeature` phone UI without this ADR amendment.

## Consequences

- Phone-ready Tier-0 remains approval + dispatch + follow-up — **not** git/terminal parity.
- Competitor “terminal on phone” marketing is explicitly out of scope for first TestFlight.
