# Sim live-loop gate — fix/p1-live-stream (2026-07-11)

Daemon: local lancerd (tip build), relay code 883425, sim iPhone 17 Pro.
Driven via DEBUG seams (HID dead on this sim): LANCER_RELAY_PAIR_CODE,
LANCER_DESTINATION=liveThread, LANCER_LIVETHREAD_PROMPT/_CWD/_FOLLOWUP.

| Check | Result | Evidence |
|---|---|---|
| Pair sim ↔ daemon | PASS | lancerd.stderr.log "paired with phone (code: 883425)" |
| Send → reply | PASS | followup-roundtrip.jpg (PONG run earlier same session) |
| **Streaming mid-run** | PASS | streaming-midrun-t18s.jpg taken ~19:47:10Z during run 19:46:55→19:47:25Z (ledger conversation_turns timings) |
| Follow-up via production sendFollowUp | PASS | followup-roundtrip.jpg (FOLLOWUP-OK) |
| **Full transcript after follow-up** | PASS (bug found by this gate, fixed e7111118) | full-transcript-two-turns.jpg |
| False-timeout removal | Unit-tested (LivePollPolicy 8/8); no long-run live proof this session | — |

Known cosmetic: markdown heading newlines collapse in streamed text ("SystemsBeginnings:") — polish item.

## Addendum — fix/relay-stable-identity + keepalive daemon (2026-07-11 evening)

Stack: daemon rebuilt from master post-#80 (read-deadline keepalive), fresh code 547438.
| Check | Result | Evidence |
|---|---|---|
| Initial pair (stable identity key) | PASS | lancerd.stderr.log "paired with phone (code: 547438)" ×1 |
| **Relaunch WITHOUT pair code → auto-restore reconnect** | PASS | daemon log ×2; backend log "phone connected with code 547438 (paired)" — pin matched the persisted Keychain identity |
| Stale-daemon reproduction (old binary) | Captured pre-deploy: backend reaped session while daemon logged connected — exact #80 root cause observed live | backend "expired unconfirmed" 21:02Z vs daemon "connected" 20:35Z |
