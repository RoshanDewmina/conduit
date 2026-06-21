# Human-gated steps — what an agent cannot do for you

These steps require the owner's Apple Developer account, signing identity, a
physical device, or a judgment call an agent shouldn't make unsupervised. An
agent can draft text, prepare commands, and verify *up to* the gate, but cannot
cross it. This list is the punch list for shipping Conduit 1.0 to TestFlight/App
Store.

Known account values (already in this repo, not secret):
- Bundle ID: `dev.conduit.mobile`
- Apple Developer Team ID: `39HM2X8GS6` (`project.yml` `DEVELOPMENT_TEAM`)
- APNs Key ID: `L8LVU9X82W`
- APNs Team ID: `39HM2X8GS6`
- Relay/push backend URL currently baked into the build: `https://35.201.3.231.sslip.io`
  (`project.yml` line 26, `CONDUIT_PUSH_BACKEND_URL`)

---

## 1. Create the App Store Connect app record

**What's needed:** an Apple Developer Program membership (paid, $99/yr) and access
to App Store Connect under the team that owns `39HM2X8GS6`. Create a new app with
bundle ID `dev.conduit.mobile`, primary language, and the metadata drafted in
`APP_STORE_CONNECT_METADATA.md` (name, subtitle, description, keywords, category,
support/privacy-policy URLs).

**What an agent already prepared:** the full metadata draft (name, subtitle,
description, keywords, category recommendation, what's-new text) in
`APP_STORE_CONNECT_METADATA.md`. Two blockers flagged there as VERIFY: no Privacy
Policy URL exists yet, and no Support URL is confirmed live — both are **required**
fields in App Store Connect, so this step cannot fully complete until the owner
either stands up those pages or supplies interim URLs (e.g. a GitHub Issues link).

**Owner action:** log into App Store Connect, create the app record, paste in the
reviewed metadata, supply real Privacy Policy / Support URLs.

---

## 2. Create the in-app purchase `dev.conduit.mobile.pro`

**What's needed:** App Store Connect → the app record (must exist first, see #1)
→ In-App Purchases → New → Non-Consumable.

**Known values to enter (from `Conduit/Conduit.storekit`, a local test config —
confirm these are also the intended *live* values, don't just copy blindly):**
- Product ID: `dev.conduit.mobile.pro`
- Reference name: Conduit Pro
- Type: Non-Consumable (one-time purchase, not a subscription)
- Display name: Conduit Pro
- Description: "Full access to all Conduit features: AI agent approval inbox,
  SFTP file browser, port-forwarding preview, CloudKit sync, and unlimited SSH
  hosts."
- Price: drafted as $14.99 in the local StoreKit config — **VERIFY** this is the
  intended live price tier; the local `.storekit` file is for Xcode StoreKit
  testing only and is not authoritative for the real App Store price.

**Owner action:** create the IAP record in ASC, set the real price tier, submit
the IAP's required localization/screenshot for review alongside the first app
build that references it.

---

## 3. Upload the APNs authentication key

**What's needed:** the `.p8` APNs Auth Key file. Per
`docs/LIVE_LOOP_RUNBOOK.md` §5a, the source file lives outside this repo at
`~/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8` — it must **never be committed**
to the repo. Key ID `L8LVU9X82W`, Team ID `39HM2X8GS6` are already known.

**Owner action:**
- Confirm (or create, if it's expired/missing) the APNs Auth Key in the Apple
  Developer portal under Certificates, Identifiers & Profiles → Keys.
- Deploy it to the running push-backend instance as `APNS_KEY_PATH` (see
  `daemon/push-backend/SELF_HOST.md` env var table) — this is a backend deploy
  step, not an App Store Connect step, but it's equally human-gated since it
  requires handling the private key file directly.
- Confirm the *running* backend instance actually has `APNS_KEY_ID`,
  `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, and `APNS_KEY_PATH` set — `/health` returning
  200 does **not** prove this (push config is read lazily at first send, per the
  runbook).

---

## 4. Produce a signed Release archive of the app target

**What's needed:** the owner's Apple signing identity (Automatic signing is
configured in `project.yml` via `CODE_SIGN_STYLE: Automatic` /
`DEVELOPMENT_TEAM: 39HM2X8GS6`, but Xcode still needs the owner logged into the
right Apple ID/team locally, or a CI signing certificate + provisioning profile).

**Before archiving, confirm `project.yml` build settings point at the live
backend** — `CONDUIT_PUSH_BACKEND_URL` (line 26) must be the production relay URL,
not a placeholder or a localhost/dev value. The repo currently has this set to
`https://35.201.3.231.sslip.io`; confirm that's still the intended production
relay at archive time, since the runbook describes this as a Cloud Run / self-host
deployment that could move.

Also confirm before archiving:
- `CONDUIT_SUPABASE_URL` / `CONDUIT_SUPABASE_PUBLISHABLE_KEY` are injected via
  local/CI build settings if standard account sign-in should work in the shipped
  build (the repo intentionally ships these empty).
- `CONDUIT_ICLOUD_ENABLED` and the entitlements file match (iCloud/CloudKit
  requires the paid Developer Program capability to be enabled first — see the
  comment block in `project.yml` above the `Conduit` target's entitlements).
- Sentry DSN (`Conduit/ConduitApp.swift`) — currently empty/disabled. Decide
  before archiving whether to leave crash reporting off for 1.0 or wire a real
  DSN (changes the privacy label — see `PRIVACY_ANSWERS.md` item 6).

**Owner action:** in Xcode (or via `xcodebuild archive` / Xcode Cloud), select the
`Conduit` scheme's `archive` action (already configured for `Release` in
`project.yml`), produce the `.xcarchive`, validate, and upload to App Store
Connect — or hand to Transporter.

---

## 5. Capture real-device screenshots

**What's needed:** the App Store listing requires screenshots for at least one
required device size class (typically 6.7" / 6.9" iPhone, plus iPad if the app
supports it — Conduit's `UISupportedInterfaceOrientations~ipad` in `project.yml`
suggests iPad support is intentional, so iPad screenshots are likely required
too).

Simulator screenshots are acceptable to Apple for most flows, but for this app
specifically, prefer **real-device** captures for anything touching:
- The live approval Inbox card with a real (or convincingly real-looking) action.
- The SSH terminal-in-chat view, ideally against a real host.
- Any push-notification / lock-screen approval screenshot — this is the one
  screenshot that **cannot** be faked from a simulator (simulators can't receive
  real APNs; see `LIVE_LOOP_RUNBOOK.md` Phase 5c).

**Owner action:** run the app on a physical device (or accept simulator captures
for the non-push screens), capture the required size classes, crop/frame as
desired, and upload to the ASC media section for the version being submitted.

---

## 6. Send the TestFlight invite

**What's needed:** a processed build in App Store Connect (post-archive, post
Apple binary processing) and the tester's email or a public TestFlight link.

**Owner action:** in App Store Connect → TestFlight, add the build to an internal
or external testing group, fill in "What to Test" (can reuse the tester
quick-start content from `TESTER_QUICKSTART.md` in this same directory), and send
the invite. External testing additionally requires a first-time Apple Beta App
Review, which can take 24–48h — budget for that before promising a tester a date.

---

## 7. Run the one physical-device live-loop proof

**What's needed:** a real iPhone, a signed dev/TestFlight build with the Push
entitlement and `aps-environment` set, and the host-side daemon running.

**This is the single most important unverified product promise** — see
`docs/LIVE_LOOP_RUNBOOK.md` Phase 5c ("APNs while app is closed — physical device
only"). Per the runbook: simulators cannot receive production APNs, so this proof
cannot be faked or approximated. The exact procedure, in order:
1. Launch Conduit once on the device, accept notifications (registers APNs token).
2. Background or fully close the app.
3. From the host, trigger an `ask`-classified action.
4. Confirm a lock-screen/Dynamic Island notification arrives with Approve/Reject
   actions.
5. Tap **Approve** on the lock screen (app still backgrounded/closed) and confirm
   the host agent unblocks and `audit.log` shows the decision.

The runbook explicitly flags: "treat any failure here as P0," and "do NOT mark
physical-device APNs (checklist C2) green from a simulator." An agent can prepare
everything up to this point (backend config, registration code, the policy that
forces an `ask`) but the device tap, by definition, requires a human holding a
physical iPhone.

**Owner action:** perform the five steps above on a real device, capture a screen
recording per the runbook's instruction, and update
`docs/PUBLISH_READINESS_CHECKLIST.md` (C2) only after this specific proof passes
— not from a simulator run.

---

## Summary — what was and wasn't done by drafting these docs

Everything in this `docs/distribution/` directory is **text only** — metadata
drafts, a privacy inventory, a tester guide, and this checklist. No build was
run, nothing was deployed or published, and no existing project file was
modified. Steps 1–7 above remain entirely on the owner; an agent re-reading this
checklist later can verify *that the docs exist and are accurate*, but cannot
complete any of steps 1–7 itself.
