# Conduit "Bridge" Platform — Future Roadmap

> **Type:** strategic roadmap / vision (not a TDD implementation plan). The near-term UI migration has its own
> doc (`docs/audit/CONDUIT_OVERVIEW_BOARD_MIGRATION_PLAN.md`); the iOS implementation plan is written after the
> design board is re-approved. This roadmap captures *where the product is going* and *what unlocks it*.

**Date:** 2026-06-13
**Source:** synthesis of this conversation + `docs/CONDUIT_PROJECT_DOSSIER.md` + codebase grounding.

---

## 1. Vision

`conduitd` — "the bridge" — is the product, not a phone accessory. It sits in a rare position: at the agent's
**tool-call chokepoint** (hooks), **on the developer's machine** (filesystem, processes, provider auth), it
**persists across disconnects**, and it has a **two-way channel** to the phone (and, in future, a CLI and other
clients). Today that channel is ~80% one job ("agent asks → you approve"). The roadmap turns the bridge into a
**vendor- and model-agnostic governance & control plane** with the phone and a CLI as peer clients.

**One-line positioning:**
> *The mobile command center for open-source coding agents and self-hosted models — the agents and the privacy
> stance no first-party app (Anthropic / OpenAI) and no current competitor (Omnara = Claude + Codex only) can serve.*

## 2. Beachhead & moat

**Target user (sharpened):** developers running **OSS agents** (opencode, Goose, Cline, Aider) with
**self-hosted / local models** (Ollama, vLLM, llama.cpp, LM Studio). They are security-conscious *by definition*
(that's why they self-host), they are **structurally unserved** — first-party apps are single-vendor + cloud-model;
Omnara is Claude+Codex + cloud — and they have **zero** mobile option today.

**Differentiator stack (four-deep, uncopyable by incumbents):**
`vendor-agnostic × model-agnostic (incl. local) × thin E2E relay × mobile-first governance.`

**Moat statement:** *Your code stays on your host. Your model stays on your host. Only the approval card metadata
crosses the wire — end-to-end encrypted, so even our relay can't read it.*

| | Code leaves host? | Model in cloud? | Relay can read payload? | Vendors |
|---|---|---|---|---|
| Omnara | yes (session stream) | yes | yes | Claude, Codex |
| Anthropic Remote Control | yes (Anthropic infra) | yes | yes | Claude only |
| **Conduit (target)** | **no** | **no (can be local)** | **no (E2E)** | **any (adapter SPI)** |

## 3. Connectivity & trust model — the cornerstone

The networking pain ("must I be on the same Wi-Fi / set up Tailscale?") is a property of the **SSH** model
(phone connects *inbound* to the host; behind NAT you need a public IP / port-forward / overlay). The fix is an
**outbound E2E thin relay**: daemon and phone *both* dial out to a rendezvous; neither accepts inbound. Works on
any network, behind NAT, on cellular — **no Tailscale**.

- **What transits:** approval card metadata (command, risk, paths) + your decision + control commands.
- **What never transits:** code, diffs, terminal output, the model.
- **Encryption:** daemon ↔ phone derive keys at pairing (`PairingCrypto`); the relay forwards ciphertext it
  cannot decrypt — a blind pipe.

**Three connectivity tiers (great default + escape hatches, never a required barrier):**
1. **Default — Conduit-hosted E2E relay:** zero config, any network. (Mass adoption.)
2. **Self-hosted relay:** enterprise runs the relay container; nothing touches Conduit infra. (Regulated/air-gapped; OSS trust.)
3. **Direct / LAN / BYO-overlay:** when phone+host are mutually reachable (same network or existing Tailscale), skip the relay entirely. Optional.

This single piece pays off **four** times: kills the Tailscale barrier · enables **pairing-first onboarding** ·
removes the **SSH redundancy** (SSH → power-user only, for remote-host bootstrap + live terminal) · unlocks every
capability below. Foundation already exists in part: `conduitd` POSTs approvals outbound to `push-backend → APNs`,
and the phone POSTs decisions to the backend relay (`ApprovalRelay.swift`). The deferred work is the **live
bidirectional E2E channel**.

## 4. OSS-first, vendor- & model-agnostic governance

**Integration point for every agent is the same:** its permission / tool-approval callback. Conduit already has a
**vendor-agnostic `ApprovalEvent` contract** (`hook_parity_test.go` asserts identical events across claude / codex /
opencode) and already ships an **opencode** hook (`opencode_hook.go`) + status reader (`agent_status_opencode.go`).
So this is leaning into an existing strength, not a from-scratch bet — and it's already **one vendor ahead of Omnara**.

**Adapter SPI (promote to near-foundation):** formalize the contract into a documented, community-extensible
interface — `{ permission-hook | plugin | MCP | callback }` + a `status reader` (loggedIn / model / usage) per
vendor. A new agent = one small adapter. Open-sourcing `conduitd` makes the community the integration team (the
dossier's distribution flywheel).

**Support matrix:**

| Agent | Hook surface | Local models | Plan |
|---|---|---|---|
| **opencode** (172k★) | permission system + JS/TS plugins | ✅ Ollama/vLLM/llama.cpp/LM Studio | **Flagship — harden existing** |
| **Goose** (Block, 48k★) | permissions + native MCP | ✅ | **Add (MCP adapter)** |
| Claude Code | hooks (PreToolUse) | ❌ | Keep |
| Codex (90k★) | approval / notify | ❌ | Keep |
| Cline (63k★) | VS Code extension API | ✅ | Watch (IDE-embedded) |
| Aider (46k★) | weak (edits directly) | ✅ | Low (project slowing) |
| Gemini CLI (105k★) | — | ❌ | **Drop — retiring 2026-06-18** |

**Model-aware privacy surface:** the daemon already reads the active model — extend it to flag **"local model
(Ollama) — nothing leaves this host"** vs **"cloud model"**, making the privacy guarantee *visible*. Only a
vendor/model-agnostic tool can show this.

## 5. Capability catalog & prioritization

| Tier | Theme | Notes |
|---|---|---|
| **0 · Foundations** | (a) **E2E bidirectional relay** · (b) **account registry + per-vendor quota/auth readers** · (c) **daemon control protocol + `conduit` user CLI** · (d) **Adapter SPI** | Unlocks everything + onboarding + OSS positioning. The CLI is "a program on its own." |
| **1 · Flagship** | **Usage & quota intelligence** — multi-account, cross-vendor single pane, quota-remaining (Claude 5h/weekly, Codex, API credit, OpenRouter balance), burn-rate projection, limit alerts; **stretch: auto-failover** across accounts on rate-limit | Your seed; dossier's most-requested feature; best two-way showcase. |
| **2 · Two-way control** | **Run-control** — pause / resume / kill / nudge a run, switch model/account mid-run, set budget | Activates the underused phone→daemon direction. |
| **3 · Proactive awareness** | **Observability** (host CPU/mem/disk, long-run watch) · **Git/PR events** (branch/push/PR/CI) · **Digests** ("while you were away", weekly cost) | Incremental daemon→phone pushes. |
| **4 · Trust & scale** | **Secrets brokering** (daemon holds keys; agent never sees raw; phone authorizes) · **Multi-host fleet** (route to cheapest/least-loaded host) · **Scheduling** (partly built) · **Local guardrails** (secret-scan / egress-monitor agent output) | Deeper moat / enterprise; some partly built. |

## 6. What this changes about v1 (near-term, feeds the UI migration)

- **Onboarding → pairing-first:** install bridge → it dials out → pair phone (code/QR) → choose caution. **SSH
  demoted to "advanced / connect a remote host."**
- **Trust & Privacy panel** reflects the thin E2E relay + "code & model stay on host."
- **Fleet** shows vendor (incl. **opencode**) + model + a **local/cloud privacy badge**.
- Library already dissolved; square corners already enforced.

## 7. Cross-cutting risks & dependencies

- **Relay reliability** is the #1 product differentiator (dossier §10) — it must be rock-solid; flaky notifications
  are the single most-repeated competitor complaint.
- **E2E key management / pairing** must be simple yet secure (`PairingCrypto` exists; needs the onboarding UX).
- **Quota readers are fragile** — they parse each provider's local state; treat as best-effort, fail soft, never
  block the agent on a usage-read error.
- **Strategic tension (dossier §9):** the hosted **cloud-execution** build (credits/Stripe/multi-cloud) competes on
  the crowded low-WTP consumer side, *against* the self-host moat. Roadmap stance: **lead with the private bridge +
  OSS/local-model story; keep cloud execution gated/secondary**, not foregrounded.

## 8. Sequencing summary

`Tier 0 foundations (relay + adapter SPI + account registry + CLI)` → `Tier 1 usage/quota intelligence` →
`Tier 2 run-control` → `Tier 3 awareness` → `Tier 4 trust & scale`. The relay + adapter SPI are the two pieces that
make everything else mostly readers, push events, and command handlers on top.

---

## 9. Decision log & integration findings (2026-06-13)

**Launch scope** is now itemized in `docs/audit/LAUNCH_SCOPE_LEDGER.md` (every feature: ship / gated /
defer-with-tier / cut). Read it alongside this roadmap.

### 9.1 Pull T2 run-control forward (decided)
We are shipping a **run-control vertical slice in v1** rather than waiting for full T0 foundations.
Rationale: the kill primitive (`agent.cancel`) already exists and the daemon already has a
request/response RPC channel + decision-poll loop, so adding **pause/resume** and **set-budget** RPCs
is incremental and delivers the visible two-way value now. The heavy T0 piece (E2E relay) is **not**
required — run-control works over today's daemon channel. **v1 scope = kill + pause/resume + set-budget.**
Deferred to a later T2 pass: **nudge** and **mid-run model/account switch** (the latter needs the T0
account registry). Implementation plan: `docs/superpowers/plans/2026-06-13-conduit-run-control.md`.

### 9.2 Adapter findings — the approval surface splits in two (from the agent-tools probe)
Full evidence: `docs/audit/AGENT_TOOLS_INTEGRATION_MATRIX.md` (tools installed + probed locally).

- **Class A — external pre-tool hook (conduitd already owns this seam):** Claude Code, Codex,
  opencode, **and Gemini**. Adding a Class-A vendor = copy the hook script + a `hooks.json` fragment +
  a `normalizeAgentSource` ID + an optional status reader. conduitd's **`agent-hook` CLI *is* the SPI**
  for this class (fail-open read-only / fail-closed mutating semantics verified live).
- **Class B — closed/internal approval, no attach point:** goose, aider, Cline, RooCode, Kilo. The
  **only** bridge for the whole set is a single **`conduit-mcp` gateway** that wraps dangerous tools as
  MCP and calls `agent-hook` internally — **one component unlocks goose + Cline + Roo + Kilo together.**
- **Gemini** is a moderate, high-value Class-A target (`BeforeTool` hook + `gemini hooks migrate`
  converts Claude `PreToolUse`→`BeforeTool`), but it wants a JSON `decision` object on stdout, not just
  an exit code. Recommendation: add an **`--emit json-decision`** flag to `agent-hook` so the same
  binary satisfies Gemini with no per-vendor wrapper. **Caveat: Gemini CLI reportedly retiring
  ~2026-06-18 — verify before investing.**
- **aider** is a poor fit (interactive-only; `--yes-always` is all-or-nothing, no programmatic gate).
- **Bug to fix:** `agent_status_opencode.go` reads `~/.local/share/opencode/config.json`, but real
  opencode 1.17.3 config lives at `~/.config/opencode/opencode.json` (runtime state in a SQLite
  `opencode.db`) — so the status reader reports logged-out. One-line path fix.

### 9.3 SSH retained (corrected)
SSH is **kept** as the advanced/power-user connectivity path (remote-host bootstrap + live terminal),
so SSH-key management stays in the app — moved out of the dissolved Library into Connect, with **real**
fingerprint + last-used data (the mock host counts are gone). Pairing-first is the default front door;
SSH is the guaranteed fallback while the E2E relay matures.
