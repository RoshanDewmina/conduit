# SHIP_PLAN — owner single source of truth

**Created:** 2026-07-19 · **Owner:** Roshan · **Status: ACTIVE — this is the doc the owner refers to.**
When this conflicts with older plans, this wins. Detail lives in the linked docs; decisions and
gates live here. Update this file when a gate is passed or a decision changes — nowhere else first.

**Detail annexes (not superseded, referenced):**
- Phase/task detail: [`plans/2026-07-19-daily-driver-roadmap.md`](plans/2026-07-19-daily-driver-roadmap.md)
- Siri milestones: [`plans/2026-07-09-siri-ios27-all-in-roadmap.md`](plans/2026-07-09-siri-ios27-all-in-roadmap.md)
- Direction rationale: [`product/2026-07-10-lancer-daily-driver-definition.md`](product/2026-07-10-lancer-daily-driver-definition.md)
- Execution model: [`ENGINEERING_PROCESS.md`](ENGINEERING_PROCESS.md) · live state: [`plans/orchestrator-state.md`](plans/orchestrator-state.md)
- Device proof procedure: [`LIVE_LOOP_RUNBOOK.md`](LIVE_LOOP_RUNBOOK.md)

---

## 1. Locked decisions (2026-07-19 session)

1. **Positioning inverted.** Front door = *trustworthy autonomy*: "run agents unattended from your
   phone and actually trust the result." Policy/audit/emergency-stop is the substrate that makes the
   promise credible, **not** the headline. (Supersedes the "lead with policy/audit" framing in
   `ARCHITECTURE.md` §0.1 — marketing only; the build direction is unchanged.)
   Basis: disconfirmation research 2026-07-19 — multi-vendor usage confirmed (~70% of senior
   engineers run 2–4 agents); safety has never been a purchase driver in this category (Omnara/Happy
   reviews cite continuity/speed/voice, never governance); labs' native gating (Claude Auto Mode,
   Codex sandbox) is per-vendor, non-deterministic (17% FN), Bash-only — the cross-vendor
   deterministic gate + audit + fleet stop remains unserved.
2. **iOS 27 all-in confirmed** (re-confirms owner decision of 2026-07-09/15, now with ship
   consequences accepted): raise deployment target to 27.0, merge parked Siri Phase 2 work, deep
   Siri is a **core GA feature**. Consequence accepted: **no public GA before iOS 27 ships (~Sept)**;
   any pre-Sept external testers must run iOS 27 betas.
3. **Beta scope: dogfood-only until mid-Aug.** Owner daily-drives per the 5-of-7-days bar. External
   TestFlight cohort starts ~Sept alongside iOS 27 GA window.
4. **Ship scope includes both trust features:** blast-radius preflight + evidence bundles (§4 D).
   Adversarial cross-vendor review, capability leases, canary tripwires: post-GA backlog
   (`product/FEATURE_BACKLOG.md`).
5. **Standing invariant (unchanged):** no Siri/voice **Approve** — deny/stop/status/answer only.

## 2. Timeline and gates

| Window | Focus | Gate to pass |
|---|---|---|
| **Now → ~Jul 26** | Stabilize: merge PR stack ✅, re-pair phone ✅, fix daemon bug | G1: master green, phone paired ✅, `gh pr list` empty of open residue (#176/#126/#117) |
| **~Jul 26 → mid-Aug** | Tier 0 re-proof · iOS 27 raise · trust features · Siri deep work · daily dogfood | G2 (mid-Aug): Tier 0 device-proven; owner drove real work through Lancer 5 of last 7 days |
| **Mid-Aug** | **Go/no-go review** against G2 | Go → launch prep; No-go → diagnose or invoke §6 |
| **Mid-Aug → Sept** | Launch prep + external cohort recruit (5–10, iOS 27 beta users OK) | G3: App Review pass, StoreKit sandbox proof, remote-host E2E |
| **Sept (iOS 27 GA)** | **Ship GA.** Deep Siri is the launch headline | G4: live on App Store |
| **Sept → Oct** | External retention measurement | G5: see §6 — this decides the project |

## 3. Workstream A–B — stabilize, then prove (blocks everything)

- **A1.** ~~Merge the `integration/2026-07-15-night` stack (#120–#137)~~ **DONE 2026-07-19**
  (#120–#125, #127, #128, #132, #136, #137 merged; #129–#135 closed; master tip `7b888f78` = PR
  #175). Residue: triage #176 (APNs/Live-Activity device-proof rescue — `dispatch.go` touch ⇒
  Sonnet/Fable full-diff review required), #126 (docs/skills), #117 (Fly proof docs), and land
  the 07-19 roadmap/wireframes docs.
- **A2.** ~~Re-pair the owner's phone~~ **DONE 2026-07-19** — pair live: code `676174`,
  `confirmedAt 2026-07-19T14:26:47Z` in `~/.lancer/relay-pairing.json`; daemon log
  `connected to relay as daemon` 12:54:29 + `postRunStartPush … HTTP 204`.
- **A3.** Fix the daemon `status=failed exitCode=1, zero output` bug (open since 2026-07-07).
- **B1. Tier 0 re-proof on physical device** per `LIVE_LOOP_RUNBOOK.md`: pair → dispatch → approval
  (app closed, lock screen) → follow-up. Evidence bundle committed this time — the 07-15 "10/10 sim
  proof" was claimed without committed evidence; do not repeat that.
- **B2. Emergency Stop atomic daemon-side primitive** (open P0). Client-orchestrated stop is not a
  stop. Daemon-side kill that survives relay loss, proven on device.

**Exit bar:** G1 + G2 evidence links pasted into §7 below.

## 4. Workstream C–D — the GA feature set

**C. iOS 27 + deep Siri** (detail: Siri roadmap Milestones 0+; parked branch `cursor/siri-phase2-fixes-9257`, PRs #16/#24):
- C1. Milestone 0: raise target to 27.0 (`project.yml`, `Package.swift` `.iOS(.v27)`, regenerate;
  don't silently bump watchOS/macOS). Build green on Xcode beta.
- C2. Merge/rebase parked Siri Phase 2 (RelevantEntities, App Shortcuts relevance, run-start intent).
- C3. Drive the Siri done-bar utterance table in the Siri roadmap to green **on device** — status,
  agents-running, deny, stop, answer-agent-question. Each utterance = one checklist row with
  evidence. Siri is "working" when the table is green, not before.
- C4. Gate 0 (doc cleanup pass) from the Siri roadmap: run it before implement sessions.

**D. Trust features (both in scope per decision 4):**
- D1. **Blast-radius preflight** (`lancerd`): before an approval card is pushed, dry-expand the
  argv (tilde/glob/var expansion — the exact class of the public `rm -rf ~/` incidents), walk the
  affected path set, and attach `{files: N, dirs: M, notable paths, irreversible: bool}` to the
  approval payload; render on the approval card and Live Activity. Extends the existing
  blast-radius field. Go-side walk + one iOS card change.
- D2. **Evidence bundles**: a run claiming "done" attaches proof — test/build exit status + tail,
  git diffstat, optional screenshot artifact — rendered as a phone card via the existing
  `ChatArtifactCard` path. Daemon collects at run end; no new UI surface, one new card type.

**Sequencing inside the window:** B before C before D. A Siri demo on an unproven loop is a demo,
not a product. If mid-Aug approaches and D2 is at risk, D2 slips to Sept — D1 does not slip.

## 5. Workstream E — launch prep (mid-Aug →)

App Store metadata + screenshots (owner-only) · StoreKit sandbox proof · remote-host E2E ·
DNS/site · external cohort recruit (5–10 people comfortable on iOS 27 betas; source: X/Discord
communities around Claude Code/Codex) · privacy/security page from
`legal/SECURITY_ARCHITECTURE.md`.

## 6. Kill / continue criteria (agreed 2026-07-19 — decide on evidence, not mood)

- **Mid-Aug (G2):** if the owner *himself* isn't choosing Lancer 5 of 7 days, externals will not.
  No-go ⇒ one diagnostic-fix cycle (max 2 weeks), then re-review. Two consecutive no-gos ⇒ scope
  cut or park.
- **Oct (G5):** external cohort live ≥4 weeks. **Continue** = a meaningful subset (≥3 of 10) use it
  week after week unprompted for unattended runs. **Kill** = nobody returns a second week. In
  between ⇒ interview every user, decide from that.
- Whatever the outcome: ship first. "Parked after shipping + real user data" is a win over limbo;
  "parked while polishing" is the one losing path.

## 7. Gate evidence log (append links here as gates pass)

- G1: —
- G2: —
- G3: —
- G4: —
- G5: —

## 8. Risk register (standing answers required)

| Risk | Watch / answer |
|---|---|
| Anthropic Auto Mode classifier improves → wedge erodes free | Quarterly re-check (native gating coverage vs Lancer). Positioning line: deterministic gate vs 17%-FN classifier — keep current |
| Vendor CLI argv drift (killed Omnara v1) | `vendor-cli-adapter-audit` skill before trusting any adapter; re-run at each vendor major release |
| iOS 27 API churn during betas | Siri work targets the utterance table, not API maximalism; re-verify each Xcode beta |
| Solo-builder integration risk | Fable orchestrates, cheaper models type (ENGINEERING_PROCESS); evidence-before-done, no exceptions |
| Proof-integrity relapses (mock-content incident, uncommitted 10/10 proof) | Every gate in §7 requires a committed evidence link. A claim without a link is not passed |
| Retention signal delayed to Sept–Oct by decisions 2–3 | Accepted 2026-07-19 with eyes open; mitigate by recruiting the external cohort *early* (mid-Aug) so measurement starts at GA |
