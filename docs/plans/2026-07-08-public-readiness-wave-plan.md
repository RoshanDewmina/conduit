# Public / TestFlight readiness — ranked wave plan

Date: 2026-07-08 (Fable orchestration session). Owner mandate: Wave 0 (chat overhaul →
cross-device continue → pairing/search/add-repo dogfood slice) ships first; this file
ranks everything after it toward public/TestFlight readiness. Re-verify against
`docs/PUBLISH_READINESS_CHECKLIST.md` and `docs/STATUS_LEDGER.md` before starting any
lane — working code wins over this doc.

## Wave 0 (in flight — see session evidence, not this file)

W0.A chat/work-thread overhaul → W0.B cross-device continue (checklist C7) →
W0.C pairing/trusted-machines UI → W0.D search polish → W0.E GitHub add-repo honest-wire.
Done bar: owner phone script PASS, two-device continue PASS, add-repo not a lie.

## Wave 1 — ranked

| Rank | Item | Why this order | First concrete step | Risk/gate |
|------|------|----------------|--------------------|-----------|
| 1 | **Siri / App Intents without opening the app** | The product promise is "steer from anywhere"; approve/status/continue with `openAppWhenRun: false` where the platform allows is the visible differentiator, and intents already exist (I1/I2 landed — `RunDispatchService`, `SearchLancerIntent`, `OpenConversationIntent`). `ApprovalActionIntent.openAppWhenRun` is still `true`. | Audit every intent's `openAppWhenRun`; approve/deny + status can run headless against the relay (the lock-screen decision path already does it); continue needs the dispatch seam only. | Requires the relay decision path (proven, D0.2 PASS). Owner voice-test on device. |
| 2 | **Dynamic Island / Live Activities visible** | Pipeline exists (`LancerLiveActivityManager.updatePendingApprovals` is called) but nothing was observed on the Jul 8 device — either activities never start or entitlements/push config is off. High perceived quality per unit work once root-caused. | Reproduce on device with a pending approval; check activity request errors in os_log; verify `NSSupportsLiveActivities` + push-token path. | Device-only debugging; needs owner phone time. |
| 3 | **Typography/token consistency (finish A3)** | A3 merged for main surfaces; onboarding still hardcodes a light-only scheme and stray fonts remain. Cheap, mechanical, high polish-per-token. | Sweep for hardcoded `Font.system`/colors outside DesignSystem in AppFeature; fix onboarding dark scheme. | None — pure UI lane, can run parallel to anything not touching CursorStyle. |
| 4 | **iOS 26/27 API adoption behind availability** | Target stays iOS 26.0. Adopt 27 niceties (Liquid Glass chrome where it fits the Cursor shell) behind `#available` only where it doesn't fork the design language. | Inventory candidate surfaces (sheets, composer, banners); prototype one (composer) and screenshot-compare. | Cosmetic; never block a functional lane on it. |
| 5 | **GitHub PR/diff/ship UI wired real** | Daemon gated-ship shipped; `CursorPRDetailView`/ship sheets still render from mock/demo state. Closes the "review and ship from the phone" loop — the second half of dogfood after chat. | Wire `CursorPRDetailView` to the real ship/PR RPCs; same honest-disable rule as add-repo (no fake success). | Depends on W0.E patterns; daemon side exists. |
| 6 | **Localhost preview browser (PreviewKit)** | `PreviewKit` (port detect + forward) exists, unwired. Either a V1 surface (open a forwarded port in SFSafariViewController from the thread/receipt) or an explicit cut. Decide, don't let it rot. | Spike: from a receipt with a dev-server port, open the forwarded URL; if flaky over relay, cut for V1 and record in checklist. | Relay port-forwarding may not exist — SSH-only feature is acceptable V1. |
| 7 | **Mobile verification harness expansion** | `relay-approval-e2e.sh` should cover the question round-trip; post-A3 exhaustive UI re-run catches regressions the unit gates miss. This is what keeps Waves 0–1 honest as lanes merge. | Add question-card round-trip to the e2e script; schedule the UI sweep after each merged wave slice. | CI time only. |
| 8 | **Proof Reel parity research** | Keep receipt scrubber; research-only pass on Cursor-like proof presentation. No video capture this wave. | Short design note against `docs/design-reference/cursor-mobile-2026-07-08/`. | None. |
| 9 | **Screen recorder / video attachments** | Composer attachments currently disabled; explicitly later — depends on chat stability + storage/upload design. | None this wave. | Deferred. |
| 10 | **Away Launch Composer** | Owner-deferred until chat is green; then it's the next product lane (specs exist in the Jul 7 desktop docs). | Unfreeze only on explicit owner go after Wave 0 device PASS. | Owner gate. |
| 11 | **Billing — StoreKit vs Stripe (checklist C5/P1)** | Needed for public, not for TestFlight dogfood. StoreKit sandbox purchase must be verified in TestFlight; decision StoreKit-first (App Store rules for digital services). | Verify existing IAP flow in sandbox; write the entitlement gate matrix (solo $25 / team $99 per validation memo). | Owner-gated (sandbox account, App Store Connect). |
| 12 | **Remote (non-localhost) host E2E (checklist C1)** | Final trust gate before public: the localhost sim subset is proven; a real remote SSH host exercises TOFU, reconnect, latency. | Provision a real remote host (hermes-box); run LIVE_LOOP_RUNBOOK end-to-end. | Owner-gated (hardware/host access). |

## Sequencing notes

- Ranks 1–3 are parallelizable after Wave 0 merges (disjoint write-sets: intents /
  LiveActivity / DesignSystem-onboarding). Rank 5 must wait for W0.C–E to merge
  (CursorStyle collisions).
- Nothing above claims "App Store ready" — that requires C1, C5, C7 checked off in
  `docs/PUBLISH_READINESS_CHECKLIST.md` with evidence, plus the legal/privacy rows
  already tracked there.
