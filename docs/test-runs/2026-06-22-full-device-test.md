# Full device test — 2026-06-22

> Live end-to-end test of Lancer on **Roshan's iPhone** (iOS 27.0, device
> `557A7877-…`). Collaborative: **you** tap/observe on the phone; **I** build/install and verify
> backend state (daemon logs, relay, push, APNs). Mark each ✅/❌ as we go.

**Preflight (verified before start):** daemon running (`~/.lancer/lancerd.sock`, pid 50241) ·
push backend `conduit-push-…run.app/health` → 200 (APNs key mounted, rev 00008-wkw) ·
app `LANCER_PUSH_BACKEND_URL` points at conduit-push · device build SUCCEEDED + signed.

---

## Phase 1 — Onboarding + first connect
- [ ] 1.1 Fresh launch: welcome screen renders, copy + branding correct, light/dark.
- [ ] 1.2 Notifications permission prompt appears; tap **Allow** → APNs token registers (I verify the backend received a token for this sessionId).
- [ ] 1.3 Connection / pairing step: generate a pairing code, host `lancerd` connects with it (I verify the daemon attaches to the relay).
- [ ] 1.4 First-run completes → lands on the New Chat / Command Home shell. No dead buttons; back buttons present on each onboarding page.
- [ ] 1.5 Re-launch does NOT show onboarding again (first-run persisted).

## Phase 2 — Compose + dispatch a run
- [ ] 2.1 New Chat composer: **Machine** picker lists the paired machine; **Agent** picker offers only installed agents (Claude/Codex/OpenCode/Kimi).
- [ ] 2.2 Project path picker: pick/type a gated workspace; custom path persists (newest-first).
- [ ] 2.3 Send a plain prompt → run dispatches over the relay; chat transition happens; tokens stream back.
- [ ] 2.4 Tool / terminal cards render for tool calls; `@`-file mention + `/` command autocomplete work.

## Phase 3 — Governed approval loop (app in foreground)
- [ ] 3.1 Trigger an `ask` (e.g. `claude 'write "push" to ./p.txt'` in the gated workspace) → an approval card appears in the **Inbox**.
- [ ] 3.2 The card shows the **approval summary** one-liner (e.g. "Edits 1 file" / "Runs `…`") + risk badge.
- [ ] 3.3 **Approve** → agent unblocks and continues (I verify via daemon log).
- [ ] 3.4 **Deny** on a second ask → agent stops.
- [ ] 3.5 **Edit & run** edits the command before approving.
- [ ] 3.6 **Allow always** on a critical action requires **Face ID** (BiometricGate) first.

## Phase 4 — Live push, app CLOSED (THE #1 gate — C2, never yet passed)
- [ ] 4.1 Fully background/close the app.
- [ ] 4.2 Trigger an `ask` from the host.
- [ ] 4.3 **Lock-screen / Dynamic Island notification fires** with Approve/Reject actions (I verify APNs send in backend logs).
- [ ] 4.4 Tap **Approve** on the lock screen → agent unblocks **without foregrounding the app**.
- [ ] 4.5 Capture a screen recording as proof. ⏸ This closes readiness checklist **C2**.

## Phase 5 — Continue / resume + terminal
- [ ] 5.1 Send a **follow-up** turn on the active run → new turn appends, gates re-run.
- [ ] 5.2 Resume a past conversation from **History** → state restores.
- [ ] 5.3 Open the **remote terminal** → PTY connects, blocks render, input works.

## Phase 6 — Fleet, sessions, drift
- [ ] 6.1 Fleet/Home shows the paired machine + host health.
- [ ] 6.2 **Cross-provider session observability**: sessions running on the Mac (Claude/Codex/OpenCode/Kimi) appear on the phone.
- [ ] 6.3 **Setup-drift** card surfaces (or "clean") for a scanned repo.

## Phase 7 — Settings, Trust Center, security
- [ ] 7.1 Settings groups: Connection / Notifications / Security & Trust / Advanced / Account all reachable.
- [ ] 7.2 **Security & Trust**: PAIRINGS & REVOCATION lists the paired device; **revoke** works.
- [ ] 7.3 Face ID / app-lock gate on launch (if enabled).
- [ ] 7.4 **Emergency Stop / Pause all** halts local agents.

## Phase 8 — Resilience + accessibility
- [ ] 8.1 Background → network switch (Wi-Fi↔cellular) → approval still delivers (relay reconnect).
- [ ] 8.2 Daemon restart mid-session → app reconnects, no stuck "thinking".
- [ ] 8.3 Empty/loading/error states render on each surface.
- [ ] 8.4 Dynamic Type (large) + VoiceOver pass on the core flows; light + dark.

---

## Results log
- **✅ 1.1–1.4 Onboarding + pairing** — pairing succeeded (code 357721, `e2e: paired with phone`), landed in chat. (1.0 finding below still open.)
- **🛠 2.x (FIXED) — every fresh dispatch hung → phone showed "Run failed · exit 1".** Root cause: `realLauncher` (dispatch.go) waited on the stdout/stderr pipes (`streams.Wait()`) **before** reaping the agent. Claude Code spawns MCP server subprocesses (`apple-docs-mcp`, …) that **detach via setsid** (escaping the agent's process group) and keep the pipe write-ends open after the agent exits, so the pipes never EOF → `streams.Wait()` blocked forever → `cmd.Wait()` was never reached → terminal status never emitted → run stuck "running" → phone timed out. (`--continue` runs that skip the giant init worked earlier, masking it; 10 orphaned `apple-docs-mcp` procs confirmed the leak.) **Fix:** reap the process first (`cmd.Wait()`), emit terminal status immediately, then best-effort kill the process group + close pipes. Verified via daemon DBG log: `cmd.Wait returned code=0 → terminal emitted` (~5s). Daemon rebuilt + `go test ./...` green + redeployed.
- **❌ 1.0 (FINDING) — onboarding has no "install & run the bridge on your computer" step before "Pair the bridge".**
- **❌ (FINDING) — failed-run error copy is misleading:** a failed *agent run* shows the generic SSH-style "An unexpected error occurred. Check the address and credentials" (`DSTypedErrorCard .other`). Should distinguish a run failure from a connection failure. A new user with no `lancerd` running reaches the pairing page with nothing to pair to. Fix: add a preceding step (install command `curl … | sh` or `lancerd install`, confirm it's running) ahead of the pairing page in the iOS onboarding flow.
