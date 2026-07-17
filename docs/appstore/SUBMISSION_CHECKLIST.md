# Submission checklist — TestFlight build → App Review

**Purpose:** ordered punch list from "have a build" to "submitted for
review," marking what an agent can prepare vs. what only the owner can do
(Apple ID sign-in, payment, the actual Submit button, physical-device taps).
Complements `docs/distribution/HUMAN_GATED_STEPS.md` (which this doc
narrows to the App Store submission slice specifically) and
`docs/PUBLISH_READINESS_CHECKLIST.md` (the broader engineering gate list).

**Current state (per `docs/STATUS_LEDGER.md`, 2026-07-17):** a TestFlight
build has already been uploaded (`ARCHITECTURE.md` §0.1 "TestFlight
uploaded"). This checklist assumes the next build going out is either a
fresh TestFlight build or the first App Store submission candidate — verify
against the owner's current intent before treating any step below as
"already done."

**Automated / already exists in this repo:**

- No fastlane, `xcodebuild archive` wrapper, or `altool`/`notarytool`
  upload script exists under `scripts/` as of this session (checked:
  `scripts/build.sh` is a convenience wrapper for `swift build`/`xcodegen` +
  simulator `xcodebuild build` only — no `-exportArchive`, no `altool`, no
  `notarytool` invocation anywhere in `scripts/`). The prior TestFlight
  upload (per project memory) was a manual CLI archive→export→altool chain
  run by hand, not a committed, re-runnable script. **If a repeatable
  archive/upload script is wanted, that is new work, not something this
  pack found already automated — flag to the owner rather than assume it
  exists.**
- `scripts/release-lancerd.sh` automates the **daemon** (`lancerd`) binary
  release/distribution — unrelated to the iOS app archive, do not confuse
  the two.

---

## Phase 1 — Build prerequisites (mostly agent-preparable)

| # | Step | Who | Notes |
|---|---|---|---|
| 1.1 | Confirm `project.yml` production build settings | Agent can verify, owner confirms intent | `LANCER_PUSH_BACKEND_URL` currently `https://conduit-push.fly.dev` (project.yml:25) — confirm this, not an older `sslip.io` value some docs still reference (`docs/distribution/HUMAN_GATED_STEPS.md` cites a stale `35.201.3.231.sslip.io`), is the actual production relay at archive time. |
| 1.2 | Decide Supabase standard-account values | Owner | `LANCER_SUPABASE_URL`/`LANCER_SUPABASE_PUBLISHABLE_KEY` ship empty by default (project.yml:88-89); owner decides whether standard-account sign-in should be live in this build. Affects the privacy label (see `PRIVACY_NUTRITION_LABEL.md` note 1). |
| 1.3 | Decide Sentry DSN | Owner | Currently empty/disabled (`Lancer/LancerApp.swift:26`). Leaving it off keeps the privacy label simple (no crash-data collection); wiring a real DSN changes that row — decide before archiving, not after. |
| 1.4 | CloudKit Production schema promotion | Agent prepares runbook, owner executes in Dashboard | See `docs/appstore/CLOUDKIT_SCHEMA_PROMOTION.md` — must happen before/at the same time as the first Production-signed build ships, or cross-device sync silently breaks for new users. |
| 1.5 | Confirm `ITSAppUsesNonExemptEncryption: false` still correct | Agent can verify | Re-check no new non-exempt crypto primitive was added since `docs/appstore/REVIEWER_NOTES.md` §5 was written. |
| 1.6 | Stale/dead permission strings | Agent flags, owner decides | `NSCameraUsageDescription` describes a QR-scan pairing flow that doesn't exist in code anymore (`PRIVACY_NUTRITION_LABEL.md` note 2) — either wire a real camera use or drop the string before archiving. |

## Phase 2 — App Store Connect app record (owner-only: requires Apple ID + paid account)

| # | Step | Who | Notes |
|---|---|---|---|
| 2.1 | Confirm/create the app record for `dev.lancer.mobile` | **Owner only** | Requires Apple Developer Program membership sign-in. If already created (TestFlight build exists), just confirm metadata fields are current, not stale from an earlier draft. |
| 2.2 | Paste in listing metadata | Owner (agent drafted it) | Use `docs/appstore/LISTING_COPY.md` — name, subtitle, promotional text, description, keywords, category, age rating, what's-new text. |
| 2.3 | Supply Support URL + Privacy Policy URL | **Owner only** | Both required by ASC before submission; neither has a confirmed live URL in this repo (`LISTING_COPY.md` flags both as owner-gated placeholders). |
| 2.4 | Create the IAP `dev.lancer.mobile.pro` | **Owner only** | Non-Consumable, $14.99 (verify live price tier), per `LISTING_COPY.md`'s IAP section. Check it doesn't already exist from an earlier session before creating a duplicate. |
| 2.5 | Fill App Privacy questionnaire | Owner (agent drafted answers) | Use `docs/appstore/PRIVACY_NUTRITION_LABEL.md` row-by-row. |
| 2.6 | Fill export-compliance / encryption questionnaire | Owner (agent drafted answer) | `ITSAppUsesNonExemptEncryption: false` — rationale in `REVIEWER_NOTES.md` §5. |
| 2.7 | Paste App Review notes + attach reviewer evidence | Owner (agent drafted text) | Use `docs/appstore/REVIEWER_NOTES.md` §1. **Owner must first decide** which reviewer-access mitigation to use — screen recording vs. a live demo host vs. citing precedent (`REVIEWER_NOTES.md` §2) — an agent cannot stand up a credentialed demo host or record a screen capture unsupervised. |

## Phase 3 — Build, sign, archive (owner-only: signing identity)

| # | Step | Who | Notes |
|---|---|---|---|
| 3.1 | Produce a signed Release archive | **Owner only** | `CODE_SIGN_STYLE: Automatic` / `DEVELOPMENT_TEAM: 39HM2X8GS6` are already configured (`project.yml:126-127`), but Xcode needs the owner's signing identity locally or a CI cert. No committed archive/export script exists (see header note) — this is either a manual Xcode Organizer archive→Distribute App flow, or new tooling work if the owner wants it scripted. |
| 3.2 | Validate + upload the archive | **Owner only** | Via Xcode Organizer or Transporter — requires the same Apple ID session. |
| 3.3 | Wait for Apple binary processing | N/A (Apple's infra) | Typically minutes to ~1h; no agent/owner action during the wait. |

## Phase 4 — Internal testing

| # | Step | Who | Notes |
|---|---|---|---|
| 4.1 | Add the processed build to an internal TestFlight group | **Owner only** | ASC TestFlight tab. |
| 4.2 | Fill "What to Test" | Owner (agent can draft from `docs/distribution/TESTER_QUICKSTART.md` if still current — re-verify it against the current pairing/relay flow first, it may share the same staleness as the other `docs/legal`/`docs/distribution` drafts) | |
| 4.3 | Internal testers install + smoke-test | Owner + internal team | Internal testing has no Apple Beta Review gate — fastest feedback loop before wider release. |
| 4.4 | Re-run the governed-approval live loop on this exact build | **Owner only, physical device** | Per `docs/LIVE_LOOP_RUNBOOK.md` and the P0 gate in `docs/STATUS_LEDGER.md` ("Tier 0 / 5c re-proof on current tip... Pending"). Do not treat an older build's PASS as evidence for a new archive — re-proof per build, per the repo's own "distrust another agent's/tool's self-report" rule. |

## Phase 5 — External testing (optional, before full App Review)

| # | Step | Who | Notes |
|---|---|---|---|
| 5.1 | Add an external testing group + submit for Apple Beta App Review | **Owner only** | First-time Beta Review adds 24-48h — budget before promising a date to testers. |
| 5.2 | Send TestFlight invite | **Owner only** | Public link or named tester emails. |

## Phase 6 — App Review submission

| # | Step | Who | Notes |
|---|---|---|---|
| 6.1 | Capture screenshots for required device size classes | **Owner only, prefer physical device** | Especially the lock-screen approval push screenshot — cannot be faked from a simulator (simulators can't receive real APNs; `docs/distribution/HUMAN_GATED_STEPS.md` step 5). iPad screenshots likely required too given `UISupportedInterfaceOrientations~ipad` in `project.yml:68-72`. |
| 6.2 | Attach IAP metadata/screenshot for `dev.lancer.mobile.pro` | **Owner only** | Required alongside the first build that references the IAP. |
| 6.3 | Final read-through: description/keywords/what's-new match the actual archived build | Agent can do a last cross-check pass against `ARCHITECTURE.md` §0.1 | Catches the SFTP/port-forwarding overclaim class of bug flagged in `LISTING_COPY.md`. |
| 6.4 | Select the build, attach review notes + video/demo-host details | **Owner only** | Assemble everything from Phase 2. |
| 6.5 | **Press Submit for Review** | **Owner only** | This is the one step that is unambiguously and permanently owner-only — no agent should ever be the one to press this. |
| 6.6 | Monitor App Review status; respond to any rejection | Owner (agent can help draft a rejection response once the actual rejection reason is known) | Do not pre-draft speculative rejection responses — wait for the real reason. |

---

## What this checklist deliberately does not cover

- The broader engineering readiness gates (physical-device C2 proof,
  two-device CloudKit QA, JWT HS256 hardening, etc.) — those live in
  `docs/PUBLISH_READINESS_CHECKLIST.md` and `docs/STATUS_LEDGER.md`'s "Tier
  0 / device evidence" and "Open P0/P1" tables. This doc assumes those are
  tracked separately and is scoped to the App Store Connect submission
  mechanics specifically.
- Domain/marketing-site decisions (`*.conduit.dev` vs. `lancer.dev`) — open
  and owner-gated per `LISTING_COPY.md`; blocks the Marketing URL field
  only, not the rest of submission.

## Sources read this session

- `docs/STATUS_LEDGER.md` (TestFlight-uploaded state, open P0/P1 table)
- `docs/distribution/HUMAN_GATED_STEPS.md` (prior human-gated punch list, partially stale — sslip.io relay URL)
- `docs/PUBLISH_READINESS_CHECKLIST.md` item D2
- `scripts/build.sh`, `scripts/release-lancerd.sh` (searched `scripts/` for archive/altool/notarytool tooling — none found for the iOS app)
- `project.yml` lines 25, 68-72, 88-89, 96, 126-127
- `Lancer/LancerApp.swift`
