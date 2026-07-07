# Feature Checklist vs. Wireframe Artifacts — Audit Findings

**Method:** Read the master checklist (105+ items) in full, then grepped/read the 10 published `artifacts/*.html` files panel by panel.

## 1. Headline finding: 7 checklist items marked "wireframed" were never actually drawn — anywhere

Checklist rows **44, 46, 47, 63, 64, 65, 66** (all in §2/§3, all attributed to board section `fast-follow`) are marked **`wireframed`**, but `artifacts/07-fast-follows.html` faithfully reproduces only 7 panels (A–G: verify picker → agree → disagree → run comparison → regression watchlist → time-travel/fork/Clips → Siri/widgets/Watch/Handoff). None of the 7 items below live in any of those panels:

- **#44 Policy Diff Review** (governance changes reviewed like a code diff, second-approver)
- **#46 Cross-host policy-consistency check**
- **#47 On-device audit digest** (Foundation Models summarizing audit.log)
- **#63 Account Switcher / multi-account hot-swap per vendor**
- **#64 Vendor Performance comparison** (revert-rate by vendor)
- **#65 Continuous Cross-Vendor Audit** (unbroken hash chain across a vendor switch)
- **#66 Compliance Export** (signed report for a compliance buyer)

This isn't an artifact-authoring miss — the fast-follows artifact only drew those 7 panels. The checklist's own status column is wrong for these 7 rows; they need an actual design pass, not just a correction to the doc.

## 2. Confirmed, legitimate cuts/gaps (correctly absent — not a problem)

All of these were explicitly marked `gap` or `cut` in the checklist, and grep confirms zero presence in any artifact, matching the intended state:
- #21 Slide-to-Compare diff viewer, #22 Auto-Highlight Diff Frame, #25 Searchable Proof Transcripts (all three: superseded-artifact-only per checklist, confirmed absent from all 10 files)
- #54 Multi-Agent Showdown (checklist correctly still calls it a gap)
- #56 Frustration Signal Missions (absent everywhere)
- The six explicit V1 cuts in §6c (Live Activity Risk Meter, Haptic Risk Language, Live Shadow Second Opinion, Break-Point-Aware Nudges, Live Camera Bug Repro, Big Agent Router) — none appear
- #104 Micro Editor, #105 Developer App Drawer — absent, confirmed closed
- #75 Terminal/SSH escape hatch — correctly kept off primary nav; both `artifacts/05-work-thread.html` and `artifacts/03-workspaces.html` explicitly flag `onOpenTerminal`/`SessionView` as "must stay off every V1 route," which is good documentation of the deliberate exclusion
- #78 Cross-device sync (CloudKit), #43 Policy engine presets/simulate, #45 Drift detector — all `named-only`, correctly not drawn as standalone screens

## 3. Under-represented (present, but thinner than the checklist item implies)

- **#2 Mobile attachments** (photo/screenshot/video/voice note) — every composer instance across all 10 artifacts shows only a generic "+" pill icon; no artifact ever expands it into an actual attachment-type picker. The only related content is an iOS-API citation about `Attachment(UIImage)` in `artifacts/04-launch-setup.html`, which is about processing an already-attached image, not the 4-type intake UI the item names.
- **#4 Smart Default Target** — `artifacts/02-home.html` panel D ("Run-on picker") shows a preselected "Active" target but never surfaces the *why* (last-successful machine/repo/agent) the item specifically calls out.
- **#12 Question Cards / Question Ladder** — `artifacts/05-work-thread.html` panel A draws only the single "glance" card state; the described 5-stage ladder (lock-screen chips → evidence reveal → typed instruction → contract update) never appears as distinct states in any artifact.
- **#35 Changed Files Review (hunk-level comment/send-back)** — `artifacts/06-review-diff.html` implements one free-text "Ask for changes" box, not a per-line/hunk-anchored comment. The artifact itself says it's "deliberately not importing PR comments or full review threads" — worth a 10-second confirmation that this reading of "hunk-level" was an intentional simplification and not a silent drop, since the checklist phrasing implies per-hunk anchoring.
- **#62 Team / Client Proof Layer, Proof Share Link** — the Proof Share Link half got a real row (`artifacts/08-ship-history.html` panel E, "Share proof link"); the Team/Client multi-role layer half is only a roadmap caption, never its own panel or state.
- **#79 Billing dual-mechanism caveat** — the checklist explicitly warns not to flatten `isPro` (dormant IAP) and `hasCloudEntitlement` (real Stripe gate) into one status. `artifacts/10-settings.html` cites only `PurchaseManager.shared` and a single PRO/FREE badge — the two-mechanism distinction the checklist called out doesn't carry forward.
- **#37 Light Automations** — only 2 of the 4 named variants appear (`artifacts/05-work-thread.html`: "Rerun proof," "Remind me in 30m"); "notify on CI fail" and "pause until morning" aren't shown anywhere.

## 4. Resolved, not dropped (worth noting so it isn't re-flagged later)

Checklist's own "Known open thread #1" (nav discrepancy: real app has 4 sidebar rows vs. the wireframe's proposed 3-root IA) was actually investigated and resolved during artifact authoring: `artifacts/02-home.html` and `artifacts/10-settings.html` cite real code (`LancerSidebarView.swift:30-266`, `AppRoot.swift:294-296`) showing the sidebar is already down to 2 rows (Home, Machines) with Inbox and Governance already folded — a genuine finding, correctly closing that open thread rather than leaving it silently unresolved.

## 5. Reverse check — scope creep / additions not on the checklist

No genuinely new *feature* concepts were found beyond the checklist's scope. The one recurring pattern worth flagging as a process note (not a feature gap): every one of the 10 artifacts embeds a "bug-callout" box auditing real code state against the doc (e.g., stale sidebar screenshots, the hardcoded "Relay connected · 3 hosts" footer, `PurchaseManager` entitlement risk). This is valuable engineering-handoff content, but it means the artifacts are partly QA/reality-check documents bundled with wireframes — appropriate if that was the intent, worth confirming it was, since it's a step beyond pure wireframing.

## Files referenced
- `docs/design-audit/2026-07-05-feature-checklist-for-wireframing.md`
- `artifacts/01-onboarding.html` through `artifacts/10-settings.html`
