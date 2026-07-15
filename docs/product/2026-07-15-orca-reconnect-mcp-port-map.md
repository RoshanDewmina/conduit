# Orca port map — reconnect reliability + per-turn MCP (2026-07-15)

Source: `research-repos/orca` (MIT, © 2026 Lovecast Inc. — attribution required on any ported
pattern). Mined as a second opinion for (1) the recurring reconnect→first-send bug class and
(2) the `--strict-mcp-config` latency fix's full-tools toggle. Orca is NOT turn-based — agents
are long-lived TUI CLIs in PTYs; the phone writes keystrokes. Several Lancer problems don't
exist there structurally; recommendations below account for that.

## Q1 — reconnect / first-send reliability

What Orca has that Lancer's clientTurnId-dedupe lacks (all in
`mobile/src/transport/rpc-client.ts` unless noted):

| # | Pattern | Orca evidence | Verdict |
|---|---------|---------------|---------|
| 1 | **Send-after-connected gating** — every send `await waitForConnected()`; messages issued mid-reconnect are held and flushed on connect, never fired at a dead socket | `rpc-client.ts:1017-1056`, `276-306` | **ADOPT** — complements host-side clientTurnId dedupe; attacks hang/drop from the send side |
| 2 | **Send-time desync self-heal** — state says connected but socket not OPEN → force reconnect instead of silent drop | `rpc-client.ts:975-998` | **ADOPT** — most direct guard against our exact symptom |
| 3 | **Foreground probe + backoff reset** — on app-active/network-change: liveness probe if connected (8s half-open detection), immediate reconnect + attempt reset if reconnecting | `rpc-client.ts:1164-1194`, `connection-revival-triggers.ts:9-50` | **ADOPT** — map to `scenePhase == .active` |
| 4 | **Session epoch/generation guard** — resume verifies expected identity against host-side session; stale resume rejected, never silently bound to wrong session | `src/relay/pty-handler.ts:712-729` | **ADAPT** — add epoch to resume handshake; clientTurnId correlates appends, not sessions. Note: relay session-key epoch nonce is already an open P2 (2026-07-04 hardening) |
| 5 | Half-open detection: 20s activity probe w/ inboundSequence, connect/handshake timeouts | `rpc-client.ts:814-852`, `361-417` | ADAPT if reconnect bugs persist |
| 6 | Auth-rejection tolerance: budget of 3 before latching auth-failed (transient resume race) | `rpc-client.ts:116-124`, `733-773` | ADAPT — same race class as our first-send bug |

Orca does NOT have: message idempotency keys, receive-side dedupe, persistent outbox, or a
user-facing connection Retry button (recovery is fully automatic; failed RPCs reject and the
user re-types). Host-side replay-of-truth (100KB PTY buffer, `pty-handler.ts:685-751`) is their
substitute. Implication: our Retry button is UX debt Orca avoids via #1-#3 — if the 10-cycle
proof passes, #1-#3 remain the right post-proof hardening to make Retry near-unreachable.

## Q2 — MCP / tool loading per turn

Orca always loads everything by delegating to the native CLI's own config
(`src/shared/tui-agent-config.ts:67-77`, `tui-agent-startup.ts:33-53`) — zero
`--strict-mcp-config`/`--mcp-config`/tool-profile usage anywhere. It can afford this ONLY
because the CLI is resident: MCP cost is paid once per tab, not per turn. No counter-pattern to
our per-turn dispatch fix exists there. Verdict: **our strict-by-default + per-dispatch
full-tools toggle stands.**

One ADAPT for the toggle UI: `src/shared/mcp-config.ts` (candidates `:36-64`, summary
`:186-220`, env masking `:201`) — parse configured MCP servers, classify enabled/disabled/
invalid, mask secrets, render the inventory. Port the summary schema + file-candidate
resolution (Go/Swift reimplementation, attribution comment), so the toggle can show "which
servers a full-tools dispatch loads." Optional, not gating Stream 4.
