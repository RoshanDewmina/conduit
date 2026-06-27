# Lancer — Launch Scope & Deferral Ledger

> The single source of truth for **what ships at v1 launch**, **what is deferred (and to which roadmap
> tier)**, and **what is cut entirely**. Reconciles `BACKEND_COVERAGE.md`, `docs/_archive/audit/FEATURE_COVERAGE.md`, the
> migration board, and the bridge-platform roadmap. Date: 2026-06-13.
>
> **Status keys:** `✅ ship` (in v1) · `🔶 ship-gated` (v1 but behind paid cloud entitlement) ·
> `🟡 defer` (planned, post-v1, with tier) · `✂️ cut` (removed from the product).
>
> Roadmap tiers (from `docs/superpowers/plans/2026-06-13-lancer-bridge-platform-roadmap.md`):
> **T0** foundations · **T1** usage intelligence · **T2** two-way control · **T3** awareness · **T4** trust & scale.

---

## A. KEEP FOR LAUNCH (v1)

### A1 · Core approval loop (the product)
| Feature | Surface | Status | Notes |
|---|---|---|---|
| Pending approvals (inbox queue) | Inbox tab | ✅ ship | `agent.approval.pending` + APNs |
| Approve / Deny | Card + sheet | ✅ ship | `agent.approval.response` |
| Allow always → standing rule | Card → confirm sheet | ✅ ship | writes a scoped policy rule; revocable in Policy |
| Edit & run | Edit screen | ✅ ship | re-checks edited command against policy |
| Decision sheet (blast radius, why-this-asks, rule cite) | Sheet | ✅ ship | full detail view |
| Critical → Face ID gate | Sheet | ✅ ship | biometric required to approve critical |
| Activity / while-you-were-away | Activity tab | ✅ ship | `agent.audit.tail` |
| On-device audit log | Settings → Security | ✅ ship | every decision recorded locally |

### A2 · Fleet & run-control
| Feature | Surface | Status | Notes |
|---|---|---|---|
| Cross-vendor agent list + status | Fleet tab | ✅ ship | `agent.status` |
| Cross-vendor spend (today, per vendor) | Fleet hero | ✅ ship | the "killer glance" |
| Model + privacy badge (local/cloud) | Fleet rows | ✅ ship | local-model = "stays on host" |
| Agent run detail (live output tail) | Run detail | ✅ ship | new screen; tap a Fleet row |
| **Run-control: Stop (kill)** | Run detail | ✅ ship | `agent.cancel` exists today |
| **Run-control: Pause / Resume** | Run detail | ✅ ship | **new RPCs this cycle** (see run-control plan) |
| **Run-control: Set budget (mid-run cap)** | Run detail | ✅ ship | **new RPC this cycle** |

### A3 · Connectivity & onboarding
| Feature | Surface | Status | Notes |
|---|---|---|---|
| Pairing-first onboarding (hero → pair → caution → first-run) | Onboarding | ✅ ship | **UX ships v1; see dependency note** |
| Bridge install (one command) | Onboarding step | ✅ ship | `curl … | sh` |
| Choose caution (cautious/balanced/bypass) | Onboarding step | ✅ ship | seeds default policy |
| First-run inbox (checklist + local demo card) | Inbox | ✅ ship | demo runs nothing |
| Advanced: add host over SSH | Add host | ✅ ship | SSH retained as power-user path |
| TOFU host-key trust prompt | Sheet over Add host | ✅ ship | verify fingerprint before trust |
| **SSH keys management (real data)** | Connect → SSH keys | ✅ ship | **kept** (SSH stays); fake host counts removed |
| Live block session / terminal | Power-user | ✅ ship | Warp-style blocks; reached from Settings |

> **Dependency note (pairing-first):** the zero-config pairing UX is the launch *target*, but the
> **live bidirectional E2E relay** it rides on is a **T0 foundation that is only partly built** today
> (outbound approval POST + APNs exist; the live duplex channel does not). v1 ships pairing-first as
> the front door **with SSH as the guaranteed fallback**; if the relay isn't production-solid by
> launch, onboarding degrades gracefully to SSH-advanced and pairing becomes the first fast-follow.
> This is the one launch risk to watch (relay reliability is the #1 competitor complaint).

### A4 · Files & diffs
| Feature | Surface | Status | Notes |
|---|---|---|---|
| Diff viewer (approve a write) | Diff screen | ✅ ship | partial-hunk apply is Pro |
| **Full-file viewer (bottom drawer)** | Drawer on tap-a-file | ✅ ship | **new**; surfaces the orphaned SFTP preview |

### A5 · Governance
| Feature | Surface | Status | Notes |
|---|---|---|---|
| Policy presets + rule list | Policy | ✅ ship | cautious/balanced/bypass + effect chips |
| Raw `policy.yaml` editor + reload-on-bridge | Policy → advanced | ✅ ship | `agent.policy.set` / `reload` |
| Notifications: severity filters | Settings → Notifications | ✅ ship | critical locked-on |
| Notifications: quiet hours (critical breaks through) | Settings → Notifications | ✅ ship | |

### A6 · Settings, security, providers
| Feature | Surface | Status | Notes |
|---|---|---|---|
| Provider keys (Anthropic, OpenAI, OpenRouter, local) | Settings → Provider keys | ✅ ship | keys go direct to provider; local needs none |
| Face ID app-lock | Settings → Security | ✅ ship | open + approve-critical |
| Redact secrets in output | Settings → Security | ✅ ship | toggle |
| Trust & Privacy panel | Settings → Trust | ✅ ship | what stays on host vs crosses wire |
| Appearance (light/dark) | Settings | ✅ ship | |

### A7 · Vendors / agents at launch (Class A — external pre-tool hook)
| Vendor | Status | Notes (from `AGENT_TOOLS_INTEGRATION_MATRIX.md`) |
|---|---|---|
| Claude Code | ✅ ship | reference adapter (PreToolUse hook) |
| Codex | ✅ ship | Lancer hook already live (`~/.codex/hooks/`) |
| opencode (+ local models) | ✅ ship | permission hook; **fix status-reader path bug first** (see §D) |

### A8 · Monetization
| Feature | Surface | Status | Notes |
|---|---|---|---|
| Billing & usage (spend + quota remaining) | Billing | ✅ ship | `/billing/quota`; doubles as T1 preview |
| Lancer Pro paywall | Paywall sheet | 🔶 ship-gated | Stripe `/billing/checkout` |
| Manage subscription / restore | Billing | 🔶 ship-gated | Stripe portal |
| Dispatch (start a task from phone) | Dispatch | ✅ ship | wired to real `agent.dispatch` RPC |

---

## B. DEFER / LATER (planned, post-v1)

| Feature | Tier | Why deferred |
|---|---|---|
| **Live bidirectional E2E relay** (duplex, blind ciphertext pipe) | T0 | Biggest single foundation; v1 leans on SSH + APNs. Unblocks true zero-config pairing on any network. |
| **Adapter SPI formalization** + `lancer-mcp` gateway | T0 | Documented, community-extensible interface; the MCP gateway is the **one component that unlocks the entire Class-B agent set** (goose, Cline, Roo, Kilo) at once. |
| **Account registry** (multi-account per vendor) | T0 | Prereq for account-switch + cross-account failover. |
| **`lancer` user CLI** (the bridge as a standalone program) | T0 | "A program on its own" — usage checks, control, status from the terminal. |
| Gemini CLI adapter | T0 (Class A) | Has a `BeforeTool` hook + `hooks migrate`; needs a thin JSON-decision shim. **Reportedly retiring ~2026-06-18 — verify before investing.** |
| goose / Cline / RooCode / Kilo adapters | T0 | Class B (closed approval loop); only reachable via the `lancer-mcp` gateway above. |
| Usage intelligence: burn-rate projection, limit alerts, **auto-failover** across accounts | T1 | Builds on account registry + quota readers. Flagship post-v1 feature. |
| **Run-control: Nudge** (one-line instruction to a working agent) | T2 | Deferred from the v1 run-control slice. |
| **Run-control: Switch model / account mid-run** | T2 | Needs account registry (T0). |
| Observability (host CPU/mem/disk, long-run watch) | T3 | Incremental daemon→phone pushes. |
| Git / PR events (branch, push, PR, CI) | T3 | |
| Digests ("while you were away", weekly cost) | T3 | |
| Secrets brokering (daemon holds keys; agent never sees raw) | T4 | Deeper moat / enterprise. |
| Multi-host fleet routing (cheapest/least-loaded host) | T4 | |
| Scheduling UI (composer/trigger/edit) | T4 | RPCs exist (`agent.schedule.*`), composer archived on pivot. |
| Local guardrails (secret-scan / egress-monitor on agent output) | T4 | |
| Self-hosted relay (enterprise container) | T4 | The OSS-trust connectivity tier. |
| Hosted Cloud agents: create / run / logs | T4 | 🔶 built-but-gated; kept secondary per moat stance. |
| Run-artifact browser (list / download / delete) | T4 | ❌ no frontend yet; needs secure download/preview pipeline. |
| Org-member invite (email/role flow) | T4 | ❌ no frontend yet; only relevant once team billing ships. |
| Team org (shared policy, team inbox) | T4 | 🔶 partially built; Pro feature. |
| Watch app · Live Activity · Lock-screen widget | post-v1 | Code-covered; needs physical-device APNs verification (owner-only). |
| CloudKit sync | post-v1 | Info.plist-gated; production CloudKit is owner-only. |

---

## C. CUT ENTIRELY (removed from product)

| Thing | Why |
|---|---|
| Library hub | Dissolved for simplicity — keys → Settings/Connect, snippets → session. |
| Session surface switcher / app-inside-session (`SessionShellView`, Preview tabs) | Dead code + a wrong Pro-gate; never a verified path. |
| Mock SSH "N hosts" counts | Fake data in a security app — replaced with real fingerprint + last-used host (page kept, data fixed). |

---

## D. Bugs to fix before launch (surfaced during this audit)

1. ~~**`risk(2)` returns brand blue** — risk collides with the CTA color.~~ **FIXED 2026-06-14.**
   Was pervasive: 7 files mapped risk-2 to the brand/accent family (`Tokens.risk`, `AgentIsland`,
   `DSChip` RiskBadge, `ChatComponents.riskTone`, `ManagementAtoms` dot/chip tone, `ProComponents`
   tone helpers, `Primitives.DSStatusDotTone`). Added an independent monotonic ramp (green → amber →
   `riskOrange #E2662C` → red) + a dedicated `DSChipTone.orange`/`DSStatusDotTone.orange`. Verified
   in-sim (light+dark): inbox HIGH/DESTRUCTIVE cards + the component catalog now read orange, never
   blue; brand blue is CTA-only (R5.1/R5.2).
2. **`agent_status_opencode.go` reads the wrong config path** — looks at
   `~/.local/share/opencode/config.json`, but opencode 1.17.3 uses `~/.config/opencode/opencode.json`
   (+ a SQLite `opencode.db` for runtime state), so opencode reports logged-out. One-line path fix
   (found by the agent-tools probe).
3. **Eight ad-hoc gradient footers** clipped scroll content — fixed on the board via `.cc-foot`; the
   iOS port must use the equivalent single footer component.

---

## E. Launch gate (must all be true to ship v1)

- [ ] Core loop (A1) verified end-to-end on a real device with real APNs.
- [ ] Run-control v1 (stop/pause/budget) lands and is reversible/safe.
- [x] Risk-ramp decoupling (D1) done; no brand blue outside CTAs (verified in-sim light+dark 2026-06-14).
- [ ] opencode status-reader path fixed (D2); Class-A vendor parity test green.
- [ ] Connectivity decision settled: relay production-solid **or** SSH-first fallback wired with
      pairing as fast-follow.
- [ ] Every shipped screen passes the §8 consistency checklist.
