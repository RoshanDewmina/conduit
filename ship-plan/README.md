# Conduit — Ship Plan (refined) & Subagent Operating Guide

**Date:** 2026-05-31 · **Branch:** `feat/warp-style-agent-blocks` · **Target:** paid v1 → TestFlight beta → App Store

This folder is the **operating manual** for shipping Conduit. Each file in `workstreams/` is a **self-contained prompt** you paste into a fresh agent. When an agent reports back, paste its response to the orchestrator (me); I judge it against `VERIFICATION.md` and return PASS / PASS-WITH-NITS / FAIL + a fix list.

---

## 0. What this refinement did to the source plan

The source (`~/Downloads/conduit-ship-plan.md`) is three stacked passes written over several days. They **disagree** in places. I reconciled them against the live repo into one coherent ship-critical plan:

| Conflict in source | Resolution (locked by owner 2026-05-31) |
|---|---|
| Part I: "free v1, Stripe out of scope" vs Part II/III: "paid v1, finish Stripe" | **Paid v1.** Keep the StoreKit paywall, finish Stripe. Beta testers get sandbox/promo unlock. |
| Part II-A: consolidate on **Fly.io** vs Part III-B: deploy to **GCP Cloud Run** | **GCP Cloud Run** for the push backend. Removes the hardcoded `http://35.201.3.231` IP; auto-HTTPS; scale-to-zero; keeps `fly.toml` intact. |
| Scope | **All 17 points + post-launch** (owner-chosen). The 17 are WS-0…WS-10; post-launch items are scoped as WS-11…WS-15 (§6). |

**Validated against the live tree (true as of this pass):**
- Untracked key work is real and substantial: `SecurityKit/OpenSSHKeyParser.swift` (706 lines), `KeysFeature/KeyImportView.swift` (267 lines) — point #6 is half-built, not greenfield.
- Tracked edits sitting uncommitted: `KeysView.swift` (+20), `OnboardingView.swift` (+410), `KeyStore.swift` (+27), `SettingsView.swift` (+2).
- Repo noise to ignore: ~22 agent dotfiles (`.agents/ .claude/ .codebuddy/ … .zencoder/`), `.dmux/`, `build/`, `.DS_Store`, and a committed-by-accident Linux binary `daemon/push-backend/push-backend-linux`.
- Assets the plan assumes exist DO exist: `docs/app-store-metadata.md`, `docs/ship-gate-owner-steps.md`, `fastlane/`, `.gitignore`, `daemon/push-backend/billing.go`, `project.yml` (entitlements swap comment at L57–63).
- **The test suite uses Swift Testing (`@Test`), not XCTest** — verify with `swift test`, don't grep for `func test`. Source claims 163 (Part I) / project record says 203; treat the **live `swift test` count** as ground truth and never let it drop.
- ⚠️ **The source plan's Part I audit is STALE in places.** It says `AutoReconnectEngine` is "declared and never wired" — but commit `dafa6ba` ("…reliability…") + the project record (B4, 2026-05-30, 203 tests) say reconnect/keepalive/history-restore/error-mapping shipped; and `858b688` ("COLORFGBG theme hint, approval-card header, PixelBox glow, a11y guards") already touches WS-2/WS-9/WS-11 territory. WS-1, WS-2, WS-9 are framed as **verify-then-close-gaps.** General rule for every subagent: **verify each "X is missing/not wired" claim against the live code before acting** — the draft predates several committed batches.

**Source defects fixed here:** duplicate/incoherent numbering; the "free v1" stale assumption; no per-prompt reporting contract; no clean definition-of-done. All addressed below + in each prompt.

---

## 1. The 17-point map → workstreams

Every one of the owner's 17 points is covered by exactly one ship-critical workstream:

| 17-pt | Owner ask | Workstream |
|------|-----------|-----------|
| 12,13,14,15 | reconnect, keepalive, block-history restore, error mapping | **WS-1 Reliability (LEAD)** |
| 1,3,2,5 | terminal empty space, long-output overwrite, Claude theme hint | **WS-2 Terminal fidelity** |
| 6 | SSH key import UI + passphrase | **WS-3 Key import** |
| 9 | finish Stripe checkout/portal/webhook | **WS-4 Billing** |
| 7,8 | cloud consolidation, push backend prod HTTPS | **WS-5 Backend → Cloud Run** |
| 10 | marketing site (needed for the Stripe redirect + privacy URL) | **WS-6 Marketing MVP** |
| 11,16,17 | Sentry DSN, App Store metadata, entitlements swap | **WS-7 Observability & release** |
| — | secret/Keychain/TOFU audit of the finished key code | **WS-8 Security review** |
| 4 | session-row PixelBox tuning + font/header standardization + a11y | **WS-9 UI & a11y** |
| — | manual QA script on sim + real device/host | **WS-10 QA execution** |
| — | clean tree before parallel work | **WS-0 Repo hygiene** |
| post | Inbox approval-card redesign (confirmed device bug) | **WS-11 Approval card** |
| post | interactive, replayable onboarding + tutorials | **WS-12 Onboarding** |
| post | navigation / safe-area polish | **WS-13 Nav polish** |
| post | real bidirectional iCloud sync | **WS-14 iCloud sync** |
| post | competitive feature spikes | **WS-15 Feature spikes** |

---

## 2. Wave plan (dependencies)

```
Wave 1 (serial):   WS-0 repo hygiene  ← everyone branches off the clean tree
Wave 2 (parallel): WS-1 reliability(LEAD)  WS-2 terminal  WS-3 key-import
                   WS-4 billing  WS-5 backend  WS-6 marketing  WS-9 UI/a11y
Wave 3 (serial):   WS-8 security (after WS-3)  ·  WS-7 release (after WS-1/2/3/4/5 merge)
Wave 4 (gate):     WS-10 QA on real device/host  ← final beta gate
```
Owner-only steps (Apple Dev portal, Stripe dashboard, Sentry project, DNS) are listed inside WS-4/5/6/7 and can run in the browser in parallel with coding.

---

## 3. Global Definition of Done (every workstream)

- [ ] `cd Packages/ConduitKit && swift build` green — zero errors, **no new warnings**.
- [ ] `cd Packages/ConduitKit && swift test` green; new behavior has tests; count not reduced.
- [ ] Scope respected — only files in the brief touched; **never `git add -A`**, stage source only.
- [ ] Invariants intact: TOFU prompt in prod paths · single unified PTY · `.submitted`-only TUI escalation · Keychain-only secrets.
- [ ] UI changes: gallery/live screenshot in **light AND dark** (see `CLAUDE.md` → Visual verification).
- [ ] Filled-in **Report Template** (bottom of each prompt) returned so it can be judged.
- [ ] No secret (key, passphrase, password) logged, printed, or written in plaintext.

## 4. How to run a subagent (your loop)
1. Open the workstream file → paste it into a fresh agent. Tell it to branch off `feat/warp-style-agent-blocks`.
2. Agent works, returns the filled Report Template (+ diffs/screenshots).
3. Paste that back to me → I independently reproduce build/test/grep and return a verdict + fix list.
4. Iterate to PASS, then merge. Merge order follows the wave plan.

## 5. Read-before-you-touch (per area)
- Terminal/blocks: `docs/block-terminal-implementation.md`, `docs/agent-contract.md` §5, `CLAUDE.md` "Block terminal".
- App Store: `docs/app-store-metadata.md`, `docs/ship-gate-owner-steps.md`.
- Server/deploy: `docs/SERVER.md`. Architecture: `ARCHITECTURE.md`.

## 6. Post-launch workstreams (now scoped as prompts — owner chose "all 17 + post-launch")
Run after the WS-0…WS-10 beta gate clears. Each is a full prompt in `workstreams/`:
- **WS-11** — Inbox approval-card redesign (`DSApprovalCard` host-label-floats bug; confirmed on device). **Near-ship — pull earlier if time allows.**
- **WS-12** — Interactive, replayable onboarding + tutorials (the +410 uncommitted `OnboardingView` edits may already advance this — verify first).
- **WS-13** — Navigation / safe-area polish (tab bar + composer insets on notch / home-indicator devices).
- **WS-14** — Real bidirectional iCloud sync (currently push-only; keep the Sync UI hidden until this lands — see WS-9).
- **WS-15** — Competitive feature spikes (shortcut/extra-key bar, image-into-prompt, typed approval actions + autonomy presets, APNs push-on-approval). Each behind a flag.

Still genuinely out of scope (not prompted): Secure Enclave-resident keys, SSHFP/known_hosts auto-verification, iPad header parity, full multi-cloud provisioners (Lightsail/Orbstack — WS-5 just gates the dead stubs), marketing site beyond the MVP.
