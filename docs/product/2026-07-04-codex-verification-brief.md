# Verification Brief — Double-Check Before We Build

Prepared: 2026-07-04
For: Codex, as an independent second pass before any implementation work starts on the findings
below
Status: verification request, not a design doc — nothing here should be implemented yet

> **Superseded 2026-07-05** by `docs/product/2026-07-05-lancer-feature-master-plan.md` — kept for
> historical record only; its items are resolved in that doc's correctness-gap table.

## What this is

Across several Claude Code + Codex sessions on 2026-07-04, we produced two consolidation documents
covering the entire Lancer product:

1. `docs/_archive/away-mode-2026-07/2026-07-04-away-mode-master-consolidation.md` — Away Mode (mission start → proof →
   decide → return to desk), competitor research, iOS 27/WWDC 2026 platform grounding.
2. `docs/product/2026-07-04-lancer-whole-app-consolidation.md` — the rest of the app: Governance &
   Policy, Fleet & Machines, Terminal & SSH, Settings/Trust Center/Security, LancerMac, Watch app,
   Cross-device sync, Billing & packaging, and the remaining "mobile-primary cockpit" pillars.

Supporting docs, same date (Away Mode trio archived 2026-07-06 under `docs/_archive/away-mode-2026-07/`):
`2026-07-04-second-opinion-away-mode-v1.md`, `2026-07-04-v1-paid-away-workflow-spec.md`,
`2026-07-04-lancer-mobile-primary-pivot-feature-inventory.md`,
`docs/_archive/away-mode-2026-07/2026-07-04-away-mode-feature-brainstorm.md`.

Both consolidation docs were built from parallel background research agents reading real code,
cloned competitor repos, and live web search — not from memory or assumption. But that method can
still produce mistakes: stale line numbers, a file that's changed since it was read, a claim that
sounded right but wasn't checked against the actual current `master`, a citation that doesn't say
what it's cited for. **Before we plan or build anything from these docs, verify the claims below
independently** — re-read the actual files, re-run the actual greps, don't just trust the prose.

Already found and corrected once this way: this session itself repeated a stale claim ("biometric
gate removed for V1") for most of a day before a fresh code read caught that it had been reinstated
via commit `695d2440`, merged the same day. Assume there are more like this until proven otherwise.

## How to work through this

For each item below: state CONFIRMED / CONTRADICTED / STALE (was true, isn't anymore) / COULDN'T
VERIFY, with the specific file:line or command output as evidence. Don't rubber-stamp — if a claim
turns out to be exaggerated, imprecise, or simply wrong, say so plainly. Do not implement fixes for
anything found here; that's the next phase.

---

## Tier 0 — strategic second opinion (independent, not a rubber stamp)

The two consolidation docs already contain a positioning argument: the "mobile control plane for
coding agents" category is commoditized (Omnara, Codex-in-ChatGPT-mobile, Cursor iOS, GitHub Agent
HQ all ship some version of remote approvals + diff/screenshot review), so "proof" and "remote
control" are parity, not differentiation — and the one thing that's real, shipping code and absent
from every one of the 6 competitors checked (Omnara, OpenCode, Vibe Kanban, Happy, Happier, Orca) is
the governance stack: a real rule-based policy engine, a hash-chained audit log, and (once fixed)
risk-tiered biometric approval.

**That argument was constructed by Claude Code across this session. It has not been independently
re-derived by anyone else.** Before treating it as settled:

- **A. Re-run the competitive comparison yourself.** Using the same 6 cloned repos (or fresher clones
  if you prefer), independently check: does any of them have anything resembling a policy engine +
  hash-chained audit + emergency-stop combination? Don't start from "confirm the claim that none of
  them do" — go look with fresh eyes and report what you actually find, including if you land on a
  different read of the same code.
- **B. Stress-test the "governance is the moat" conclusion.** Is a policy/audit/approval layer
  actually the thing that gets someone to install a daemon and pay for it, versus a nice-to-have
  feature any of these competitors could bolt on in a few weeks if they decided to? Is there a reason
  none of them has built it yet (technical difficulty, or just no one's asked for it)?
- **C. Sanity-check the overall direction**, not just the competitive facts: given everything in the
  two consolidation docs, does "Away Mode with proof" plus a governance layer read as a coherent,
  buildable V1 — or does it read as several unfinished threads bolted together (Away Mode, Governance
  Home, LancerMac, Watch, cross-device sync, three separate billing mechanisms) that need to be
  narrowed further before anyone builds anything? Say so plainly if it's the latter.

**D. The one thing no code review can answer: is there genuine customer need for this at all.**
`docs/validation-cycle-v1.md` was written on 2026-06-24 specifically to test this — a 10-15 person
design-partner interview script with an explicit kill question ("Omnara already does this for free,
why wouldn't you just use that?"). As of the 2026-07-03 competitive audit, **there is no evidence
those interviews have ever been run.** Separately, the Away Mode pricing/validation gate (10
contacted / 5 repeat-use / 3 paying / 1 team customer by 2026-07-21, see memory
`project_away_mode_validation_gate_2026-07-04`) also has no evidence of being run. Confirm whether
either has happened since; if not, say so directly rather than treating the competitive analysis as
a substitute for it. No amount of "we are more differentiated than Omnara on paper" answers whether
anyone will actually pay — that requires the interviews, not more research.

---

## Tier 1 — high-stakes claims (would change build priorities if wrong)

1. **Biometric gate reinstatement.** Confirm commit `695d2440` ("Merge fable/approval-security-hardening:
   BiometricGate + App Attest device binding") is on `master`, and that
   `Packages/LancerKit/Sources/SecurityKit/ApprovalDecisionAuth.swift` actually gates high/critical/
   unknown-risk approval decisions as described (`requiresUnlock(risk:)`, wired into
   `InboxViewModel`/`LiveInboxViewModel.decide`, notification routing, `ApprovalRelay.enqueue`).
   Confirm `ARCHITECTURE.md` §0.1/§10.2 still assert the old "removed" claim (i.e., confirm they are
   in fact stale, not already fixed by someone else since).

2. **The reinstated gate's degrade-open hole.** Confirm `Packages/LancerKit/Sources/SecurityKit/
   BiometricGate.swift` still returns success (not a throw) when `canEvaluatePolicy` fails for a
   reason other than "biometry not enrolled" — i.e., no device passcode configured at all. If this
   is real, it's the single highest-priority security fix in the whole consolidation; if it's
   already been fixed, this whole priority ranking needs to move.

3. **Emergency stop is not atomic.** Confirm there is still no single daemon-side RPC that cancels
   every non-terminal run in one pass — that `performEmergencyStop()` (iOS) and `MenuBarContentView`'s
   disabled Pause-All/Emergency-Stop buttons (LancerMac) are both waiting on a daemon primitive that
   doesn't exist yet. Grep `daemon/lancerd/*.go` for anything resembling `emergencyStop`/`pauseAll`
   and confirm the negative.

4. **Watch app not embedded in the iOS app target.** Confirm `project.yml:138-143` still excludes
   `LancerWatch`/`LancerWatchWidget` from the iOS app target, and that this means the Watch app
   genuinely does not reach any user via the current TestFlight build (not just "unwired," actually
   excluded from the binary).

5. **JWT is still HS256-only.** Confirm `daemon/push-backend/auth.go` (~lines 46-60) still has no
   JWKS fetch, no RS256/ES256 path — verify this hasn't been addressed since 2026-07-02.

6. **Audit chain has no external anchor.** Confirm `daemon/lancerd/audit.go`'s `Verify()` only
   recomputes internal hash-chain consistency, with nothing anchoring the chain's tip hash outside
   the file itself (no push to push-backend/iCloud/Keychain of just the tip hash).

7. **Daemon single pairing-slot ceiling.** Confirm `~/.lancer/relay-pairing.json` (or its current
   equivalent) still holds exactly one pairing, and that every new pairing entry point overwrites it —
   check whether the `docs/KNOWN_ISSUES.md` P1 entry for this is still open or has since been fixed.

8. **Dormant StoreKit paywall.** Confirm `showingPaywall` (in `AppRoot.swift`) is still never set
   `true` anywhere in `Packages/LancerKit/Sources`, and that `isPro`'s only other consumer really is
   just a cosmetic Settings badge — i.e., the "Lancer Pro" one-time purchase genuinely gates zero
   features today.

9. **iOS 27 vs 26 deployment-target discrepancy.** Confirm `ARCHITECTURE.md` §2 still states
   "iOS 27.0+ / iPadOS 27.0+... tested on the iOS 27 simulator" while `project.yml` still sets
   `IPHONEOS_DEPLOYMENT_TARGET` to `"26.0"` in the 3 locations cited. This recurred across nearly
   every area of the whole-app pass — worth resolving centrally rather than continuing to flag it
   piecemeal.

10. **The locked navigation shape.** Confirm `ARCHITECTURE.md` §4.1 still states the sidebar has
    exactly 5 destinations (Home / New Chat / Needs Attention / Machines / Settings) and explicitly
    says not to reintroduce a tab bar — this is the basis for flagging "Developer App Drawer" (a
    14-mini-app drawer concept) as directly conflicting with a locked architecture decision. If §4.1
    has changed, that conflict finding may no longer hold.

11. **Non-goals list still current.** Confirm `ARCHITECTURE.md` §1.1 still lists "no local iOS code
    editor" and "no local language servers/build tools" as explicit non-goals — this is the basis for
    marking "Micro Editor" as CONFLICTS_WITH_NONGOAL rather than a viable roadmap item.

## Tier 2 — competitor-repo claims (spot-check a sample, don't need to re-verify every line)

These came from reading 6 freshly cloned repos at `research_repos/{omnara,opencode,vibe-kanban,
happy,happier,orca}/` (gitignored, not part of Lancer's own codebase — still present on disk if you
want to re-open them directly rather than re-clone).

12. **Omnara has no true E2EE** — plaintext `Text` column in `src/shared/database/models.py:276`,
    zero encryption-primitive hits repo-wide. Spot-check this file directly.
13. **Omnara has no Live Activity/Dynamic Island equivalent** — `apps/mobile` is a managed Expo app
    with no `ios/` prebuild folder and no ActivityKit code anywhere. Confirm the managed-Expo
    structure directly.
14. **Happy's E2E encryption is real** (tweetnacl.secretbox + AES-256-GCM in
    `packages/happy-cli/src/api/encryption.ts`) but it has **zero governance/policy/audit layer** —
    spot-check `docs/permission-resolution.md` in that repo for the "just picks Claude Code's own
    permission mode" framing.
15. **Vibe Kanban has the data-model prerequisite for multi-attempt comparison but has shipped no
    side-by-side comparison UI** — spot-check `crates/db/src/models/{task,workspace}.rs` and grep its
    `packages/web-core` for any comparison-related component.
16. **Happier ships session public-share links** (a real, shipped gap vs. Lancer) —
    spot-check `apps/ui/sources/components/sessions/sharing/{SessionShareDialog,PublicLinkDialog}.tsx`.
17. **Happier's desktop app is a full Tauri-wrapped clone of its mobile/web client** (including an
    embedded terminal), not a thin companion like LancerMac — spot-check
    `apps/ui/src-tauri/tauri.conf.json` and the README's "Key Features" section.
18. **OpenCode's plugin API matches what Lancer's `opencode_plugin_install.go` already assumes** —
    confirm `tool.execute.before` is still a real, current hook in
    `packages/plugin/src/index.ts` and that Lancer's own integration still matches it (no upstream
    API drift since this was checked).

## Tier 3 — doc hygiene (lower stakes, but worth fixing before it propagates further)

19. `docs/competitive-intelligence/data/competitors.jsonl` has an entry for "happy" but none for
    "happier" (a materially more advanced, separately-maintained fork) — confirm this gap still
    exists and, if so, flag for whoever owns that dataset to add a row.
20. The 2026-07-02 competitive baseline doc
    (`docs/competitive-intelligence/reports/current-product-baseline.md`) asserts the same stale
    "biometric gate removed" claim as `ARCHITECTURE.md` — confirm and flag for correction.
21. `docs/product/2026-07-04-lancer-mobile-primary-pivot-feature-inventory.md` lists "Micro Editor"
    and the broad "Automations for Code" in its "Next Layer" roadmap bucket without flagging that
    both were separately, explicitly rejected elsewhere (non-goals + the Away Mode cut log) — confirm
    this internal contradiction is still present on the page and flag it for a doc-hygiene pass.

---

## What to send back

For Tier 0: an independent narrative verdict on direction and differentiation (agree/disagree with
the existing argument, and why), plus a direct answer on whether the two validation gates (D) have
actually been run. For Tiers 1-3: a verdict per item (CONFIRMED / CONTRADICTED / STALE / COULDN'T
VERIFY), grouped by tier, with evidence. If Tier 0 disagrees with the existing direction, or Tier 1
turns up anything CONTRADICTED or STALE, call that out at the top of the response — those are the
ones that change what we build first, or whether we build at all yet.
