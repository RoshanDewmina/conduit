# Lancer Live-Loop E2E Test — Design (Pass 1: local governed-approvals loop)

**Date:** 2026-06-12
**Author:** Claude (with owner)
**Status:** Approved design → execution
**Scope:** Prove the *real* governed-approvals loop end-to-end on this Mac with a **real Claude Code agent**, the **lancerd** daemon, the **policy engine**, and the **iOS app** (simulator). Real APNs push (app-closed) is explicitly **out of scope** for Pass 1 — that is Pass 2 on a physical device.

---

## 1. Goal & motivation

Everything shipped so far was tested against **mock/seeded** approvals in the simulator, plus one live localhost SSH *shell* session. The actual product loop — a real agent emitting an approval, the daemon enforcing policy, the phone deciding, the agent unblocking — has **never been run end-to-end**. This test closes that gap and produces durable evidence (video + audit log).

This is the staged first half of a two-pass plan:
- **Pass 1 (this spec):** local loop on the simulator. No push-backend, no APNs.
- **Pass 2 (separate spec):** physical device + real APNs notifications (app closed) via push-backend.

## 2. Architecture under test (the real product path)

```
 iOS app (sim)  ──SSH exec──▶  lancerd serve  ──unix socket──▶  lancer-hook.sh
   Inbox card   ◀─JSON-RPC──   (policy engine,    ◀──spawned──   (Claude Code PreToolUse)
   approve/deny     stdio       audit log)                              │
        │                          ▲                                    ▼
        └──────decision───────────┘                          real `claude` session
```

Grounding (verified in source):
- `lancerd serve` is one process that listens on `~/.lancer/lancerd.sock` (hooks) **and** speaks framed JSON-RPC over stdin/stdout (phone). — `daemon/lancerd/server.go:262,294,302,324-353`
- The iOS app launches it verbatim: `bash -c '$HOME/.lancer/bin/lancerd serve'` over an SSH exec channel, then a `lancer.device.register` handshake mints a per-session relay token. — `Packages/LancerKit/Sources/SSHTransport/DaemonChannel.swift:28-50,107`
- The Claude Code PreToolUse hook (`docs/lancer-hook.sh`) auto-allows read-only tools, maps Bash→high/command, Write/Edit→medium/fileWrite, then calls `lancerd agent-hook approval …`. Exit 0 = proceed, exit 2 = stop.
- Policy engine (`daemon/lancerd/policy/`) evaluates allow/deny/ask from `~/.lancer/policy.yaml` (`policy/load.go:11`).

Tools confirmed present on this Mac: `claude` 2.1.176 (`/opt/homebrew/bin/claude`); `lancerd-darwin-arm64` runs (`version → 0.1.0`); simulator iPhone 17 Pro booted; Remote Login on; localhost SSH password in Keychain (`lancer-localhost-ssh`).

## 3. Topology & isolation decision

**Topology:** ① App-launched `lancerd serve` over SSH (exactly what `DaemonChannel.start()` does). The resident `daemon` (launchd, survives-disconnect) mode is **deferred** to Pass 1.5/2.

**Method:** ③ staged isolation — prove each leg before the full loop, so failures localize.

**Isolation (the key safety constraint):** the test harness *is* a running Claude Code session. A **global** lancer hook (`~/.claude/settings.json`) would route this session's own Bash/Edit calls through lancerd and could wedge it the moment `serve` starts. Therefore:
- Install the real artifacts at their real paths: binary `~/.lancer/bin/lancerd`, hook script `~/.claude/hooks/lancer-hook.sh`, policy `~/.lancer/policy.yaml`.
- **Wire the hook in a throwaway test workspace's project-scoped `.claude/settings.json`**, NOT the global one. Only `claude` sessions launched with that workspace as cwd get the hook. This session (cwd = repo root) is untouched.
- Both the app-launched `serve` and the test `claude` run as the same user → same `$HOME` → same socket `~/.lancer/lancerd.sock`. Leg alignment holds.

The **only** deviation from a textbook user install is *which settings file references the hook* (project vs global). Hook, daemon, policy, socket, and app flow are identical to production. Rationale: reuse existing `claude` auth and protect the harness session. A real user wires it globally; documented as the single intentional difference.

## 4. Policy fixture → the three governance outcomes

A real `~/.lancer/policy.yaml` (mirrors the `cc-policy` preset) chosen so a single agent run exercises all three behaviors:

| Outcome | Trigger (agent does…) | Policy effect | Observable result |
|---|---|---|---|
| **auto-allow** | a read-only tool (`Read`/`Grep`/`LS`) | hook self-exits 0 (never reaches policy) **or** `allow` rule | agent proceeds; audit logs `allow` |
| **auto-deny** | dangerous match (e.g. `curl … \| sh`, `rm -rf` on protected path) | `deny` | hook exit 2 → **Claude Code stops**; audit logs `deny` |
| **escalate (ask)** | ambiguous `Write`/`Bash` | `ask` | `agent.approval.pending` → **Inbox card in app** → approve → agent proceeds |

Exact rule set finalized against `policy/types.go` + `policy/evaluate.go` during execution (kinds: `command`, `fileWrite`, `patch`; effects: `allow`/`deny`/`ask`; matchers: tool, prefix, risk band).

## 5. Execution plan (ordered)

1. **Pre-flight:** confirm `claude`, lancerd binary, Remote Login, booted sim, Keychain password. Snapshot the current global `~/.claude/settings.json` (so we can prove it was untouched).
2. **Install (real paths):** copy lancerd → `~/.lancer/bin/lancerd`; copy hook → `~/.claude/hooks/lancer-hook.sh` (`chmod 700`); write `~/.lancer/policy.yaml` fixture.
3. **Test workspace:** create `/tmp/lancer-e2e-workspace/` (a throwaway git repo) with `.claude/settings.json` wiring the PreToolUse hook **scoped to this project only**.
4. **Leg (a) — plumbing smoke (③):** with `serve` running, fire a synthetic `lancerd agent-hook approval --kind fileWrite --command "…"` and confirm the event delivers and a decision returns. (De-risks the socket/serve path with no agent.)
5. **Leg (b) — policy unit:** drive `allow`/`deny`/`ask` events through lancerd directly and confirm correct effects + audit entries (Go tests already cover this; spot-check live).
6. **Connect the app:** build/install/launch the app in the sim; open the `127.0.0.1` host → app launches `serve` + handshakes. (Start `simctl io recordVideo`.)
7. **Leg (c) — full real loop:** run `claude -p "<task>"` in the test workspace on a task that triggers (i) a read → allow, (ii) a dangerous command → deny (agent visibly stops), (iii) a file write → ask. Approve the ask card in the app; confirm the agent continues.
8. **Activity feed:** open the Activity tab; confirm the "while you were away" feed tails the audit log (allow/deny entries visible).
9. **Capture & report:** stop recording; collect screenshots + the lancerd audit log; write the test-run report.
10. **Teardown:** stop `serve`, remove the test workspace, confirm global `~/.claude/settings.json` byte-identical to the step-1 snapshot.

## 6. Success criteria

- ✓ App launches `lancerd serve` over SSH and completes `lancer.device.register`.
- ✓ **allow:** read-only tool auto-proceeds; audit logs `allow`.
- ✓ **deny:** dangerous command halts the **real** agent (hook exit 2); audit logs `deny`.
- ✓ **ask:** ambiguous action delivers an **in-app Inbox card**; approving it unblocks the real agent.
- ✓ Activity tab shows the autonomous decisions from the audit log.
- ✓ Global `~/.claude/settings.json` provably unchanged (harness isolation held).

## 7. Failure modes & mitigations

- **Self-gating the harness** → project-scoped hook (§3); verify global settings unchanged (§5.10).
- **Socket ownership conflict** (two `serve` instances) → exactly one `serve`, app-launched; don't also run resident `daemon`.
- **`serve` lifetime = SSH session** → keep the app's session open for the whole run; note this as the reason resident mode exists (Pass 2).
- **Sim networking** → iOS simulator shares the host network, so `127.0.0.1` from the sim reaches this Mac's sshd (the existing harness already relies on this).
- **Hook needs `python3`** (the parser in `lancer-hook.sh`) → confirm `python3` present in pre-flight.
- **Agent auth** → reuse the owner's existing `claude` login (test runs as same user).

## 8. Scope honesty (stated in the report)

"Notifications" in Pass 1 = the **in-app Inbox card** while the app is open and connected over SSH. **Real APNs push (app closed) is Pass 2** on a physical device — the simulator cannot receive real APNs (only `simctl push` simulated payloads). The report will not overclaim.

## 9. Artifacts

- Screen recording of the **ask** round-trip (`simctl io recordVideo`).
- Before/after screenshots (deny-stop, ask-card, post-approve, Activity feed).
- `docs/test-runs/2026-06-12-live-loop-pass1.md` — report with the lancerd audit log pasted as evidence and an honest pass/fail per §6.

## 10. Out of scope (Pass 2, separate spec)

Physical-device build, real APNs (.p8 / push-backend), app-closed notification delivery, notification action buttons, the resident `daemon`/launchd survive-disconnect + queue-while-away behavior, and the backend decision-relay (`pushBackendURL`) path.
