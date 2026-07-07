# Competitor study: Omnara + lfg (2026-07-06)

Sources: `.study/competitors/omnara` (archived OSS), `.study/competitors/lfg`, `research/_raw/omnara.md`.  
Mapped to `docs/product/FEATURE_BACKLOG.md`.

---

## 1. Omnara

### Architecture (archived OSS, Feb 2026)

Three-tier: **CLI wrapper** → **cloud API** (Supabase + FastAPI) → **Expo mobile / web**. Daemon holds outbound WebSocket to relay with framed PTY I/O. Messages + git diffs in Postgres; push via Expo Push API.

**Pivot:** Repo archived — wrapping Claude Code CLI became unmaintainable. Rebuilt closed-source on Claude Agent SDK. **Lesson:** vendor-CLI adapters drift; Lancer's `lancerd` dispatch + governed hooks are the right layer.

### Mobile UX patterns

- Chat-first instance view (activity feed, not raw terminal)
- Structured question UI — one-tap numbered options
- Human-input queue — amber "needs input" cards; "All Clear" empty state
- Live git diff in thread context
- Push deep-link → instance on `new_question`

### Approval flow

Not governed. Agent asks → cloud stores → push → user taps → CLI resumes. MCP permission cache in-memory — **no policy, audit, or biometric gate**.

**Documented failures:** app freeze on CC confirmation popup (#276); no stop button (#272); voice breaks on lock (#270).

### Borrow / avoid

| Borrow | Avoid |
|--------|-------|
| Structured option cards | Plaintext cloud relay |
| Instance-level attention queue | Chat-parsed approvals |
| Push scoped to questions | Cloud sandbox as V1 |
| Diff stat near thread | Voice-first for Tier 0 |

---

## 2. lfg (BennyKok)

### What it is

Private control plane: Bun server + React PWA; agents in **tmux**; loopback + Tailscale Serve. Claude, Codex, OpenCode, etc. Closer to Lancer's "your box, your creds" than Omnara's cloud relay.

### Relevant patterns

**AskCenter** — questions persist JSONL; long-poll waiters; badge + floating card + full queue page share one poll.

**Prompt detection** — reads structured `AskUserQuestion` tool_use from transcript tail (not tmux scrape). Maps to Lancer block-terminal / structured events.

**Live transport** — WebSocket streams transcript, busy state, pending prompts; SSE fallback.

**Mobile PWA** — payload-less VAPID push; SW wakes and fetches `/api/push/pending`.

**SessionDiffView** — diff stat bar → lazy split/unified viewer.

### Borrow / avoid

| Borrow | Avoid |
|--------|-------|
| Ask queue UX (badge + banner + page) | Unauthenticated loopback API |
| Transcript-structured prompts | tmux send-keys as primary path |
| Send-confirm-retry dispatch | Phone xterm as primary surface |
| Diff stat above composer | Tailscale-only remote access |

---

## 3. Mapped to FEATURE_BACKLOG

### Tier 0

| Borrow | Backlog item |
|--------|----------------|
| Structured options + governed `decide()` | Approval → `decide()` |
| Push wakes blocked agent | Physical device loop |
| Transcript-structured > scrape | Follow-up / continue |
| Send-confirm-retry | Composer → dispatch |

### Tier 1

| Borrow | Backlog item |
|--------|----------------|
| Approval banner above composer | Planned P0 (lfg AskCenter) |
| Connection health ladder | Planned P0 (Orca + Omnara anti-patterns) |
| Ask nav badge | Workspaces → thread list |
| Diff stat bar | PR detail + inline diff |

### V1 (after Tier 0)

Question Cards, Question Ladder, Visual Diff Review, Stop and Snapshot, payload-less push reconcile.

### Reject (backlog §7)

Hosted cloud execution, terminal-as-primary-V1, Omnara plaintext relay.
