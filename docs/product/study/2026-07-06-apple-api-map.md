# Lancer × Apple Platform API Map

Compiled: 2026-07-06  
Scope: practical mapping for Tier 0/1 and V1 shipping decisions.  
Note: apple-docs MCP was unavailable in this session; floors and links were verified via Apple Developer Documentation fetches and WWDC26 session notes. WWDC26 ships as **iOS 27**; several APIs below landed in **iOS 26** — call out both where it affects deployment.

**Tier key:** **T0** = live loop must work · **T1** = MVP shell polish · **V1** = locked launch scope · **Post** = fast-follow after V1.

| Lancer feature | Primary Apple API(s) | iOS floor | Built-in vs custom | Doc | Tier |
|---|---|---:|---|---|---|
| Live Activities / Away status | `ActivityKit` (`Activity`, `ActivityAttributes`, `ActivityConfiguration`), push via `pushType: .token` + APNs ActivityKit topic | 16.1 (push 16.2; push-to-start 17.2) | **Hybrid** — Apple renders Lock Screen / Dynamic Island; Lancer maps relay/daemon state → `ContentState` (`LancerLiveActivityManager`) | [ActivityKit](https://developer.apple.com/documentation/activitykit) · [WWDC26 Live Activities](https://developer.apple.com/videos/play/wwdc2026/223/) | **T1 / V1** — approval Live Activity is partially wired today; full “Away Status” is V1 core but frozen until T0 E2E proves |
| App Intents + lock-screen approval | `AppIntents` (`LiveActivityIntent`, `AppIntent`), `IntentAuthenticationPolicy` (`.requiresAuthentication`, `.requiresLocalDeviceAuthentication`) | 17.0 (`LiveActivityIntent`); policy with App Intents 16+ | **Hybrid** — Apple runs intent lifecycle + lock-screen auth; Lancer bridges `perform()` → `ApprovalRelay` → `lancerd` (`ApprovalActionIntent`) | [IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy) · [WWDC26 Session 347](https://developer.apple.com/videos/play/wwdc2026/347/) | **T0** for approve/deny path · **T1** to set `authenticationPolicy` per risk tier (today intent has no policy) |
| Passkeys / pairing | Device pairing: **custom** Ed25519 relay (`lancerd pair`, Keychain). Optional cloud sign-in: `AuthenticationServices` / `ASAuthorizationPlatformPublicKeyCredentialProvider`, `requestStyle: .conditional` | Passkeys 16+; conditional upgrade iOS 18+ | **Custom bridge** for V1 pairing (not WebAuthn). Passkeys are **Apple built-in** only if Lancer adds a hosted account surface | [Passkeys WWDC25](https://developer.apple.com/videos/play/wwdc2025/279/) | **T0** = code pairing (custom) · Passkeys **Post** (not on critical path) |
| Speech / voice input | `Speech` framework: `SpeechAnalyzer` + `SpeechTranscriber` (modern); fallback `SFSpeechRecognizer` | 26.0 new path; 10.0 legacy | **Hybrid** — Apple on-device ASR; Lancer wires transcript → composer dispatch | [SpeechAnalyzer community ref](https://developer.apple.com/documentation/speech) | **V1** (“Voice Everywhere”) — ship legacy path at current min target, gate `SpeechAnalyzer` at 26+ |
| View Annotations / `.appEntityIdentifier` | `View.appEntityIdentifier(_:)` + `AppEntity` / `EntityIdentifier` for Siri & Apple Intelligence context | 18.4 | **Hybrid** — modifier is built-in; Lancer defines entities for threads/approvals/workspaces | [appEntityIdentifier](https://developer.apple.com/documentation/swiftui/view/appentityidentifier(_:)) | **Post** — Siri/AI surfacing; not a T0 gate |
| On-device Foundation Models | `FoundationModels` (`SystemLanguageModel`, `LanguageModelSession`, guided generation) | 26.0 + Apple Intelligence | **Hybrid** — Apple model runtime; Lancer owns prompts (audit digest, proof narration, diff captions) | [FoundationModels](https://developer.apple.com/documentation/foundationmodels) | **Post** — needs audit volume + AI availability checks |
| Push notification coalescing | Server: `apns-collapse-id`, `thread-id`; client: `UNNotificationContent.threadIdentifier`, `summaryArgument`; iOS 27 adds system app-level coalescing | Client APIs 10+; iOS 27 behavior | **Hybrid** — Apple groups/dedupes; Lancer `push-backend` must collapse approval bursts per session/host | [APNs collapse id](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/sending_notification_requests_to_apns) | **T0/T1** — reduces approval spam during agent runs |
| ActivityKit controls on lock screen | `WidgetKit` `ControlWidget` / `ControlWidgetButton`, `AppIntentControlConfiguration`, same `AppIntent` as Live Activity | 18.0 | **Mostly built-in** — reuse `ApprovalActionIntent`; custom value provider for pending count | [Creating controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system) | **T1** — one-tap approve without opening app; after intent auth hardening |
| CloudKit conversation sync | `CloudKit` (`CKContainer`, custom zone `LancerConversations`, `CKDatabaseSubscription`, silent push) | 13+ (modern subscriptions 15+) | **Hybrid** — Apple transport; Lancer `ConversationSyncEngine` + host ledger is execution truth | `ARCHITECTURE.md` §11.2 | **V1 shipped** — two-device QA still open |

## What makes T0/T1 easier

**Lean on Apple for surfaces, own the bridge.**

1. **T0 (prove the loop):** Pairing, dispatch, approval, continue need no iOS 27 betas. Use existing `UserNotifications` + `ApprovalRelay` + optional Live Activity updates. Highest-leverage fix: add `static var authenticationPolicy = .requiresAuthentication` on high-risk `ApprovalActionIntent` variants before expanding lock-screen actions.
2. **T1 (MVP polish):** Reuse one `AppIntent` type across Live Activity buttons, lock-screen `ControlWidget`, and Shortcuts — Apple’s “one intent, many surfaces” pattern (WWDC26). Away Status = one selective `Activity` (not per-agent); push-driven updates already match `LancerLiveActivityManager` design.
3. **Defer OS-26/27-only paths:** `SpeechAnalyzer`, `FoundationModels`, and Siri View Annotations are **availability-gated enhancements**, not launch blockers. Keep `SFSpeechRecognizer` and in-app UI as fallback.
4. **Don’t swap pairing for passkeys:** V1 device trust is Ed25519 + relay TOFU. Passkeys only matter for a future Lancer cloud account — unrelated to `lancerd pair`.
5. **CloudKit is done; don’t re-litigate:** Conversation mirror is shipped code. Remaining work is hardware QA, not API selection.

## Lancer code touchpoints

| Feature | In-tree seam |
|---|---|
| Live Activity | `SessionFeature/LiveActivityManager.swift`, `ApprovalActionIntent.swift` |
| Lock-screen decision | `ApprovalRelay`, `SecurityKit/ApprovalDecisionAuth.swift` |
| Push | `daemon/push-backend/`, `LancerApp` token registration |
| CloudKit sync | `SyncKit/ConversationSyncEngine.swift`, `ConversationCloudRecords.swift` |
| Pairing | `E2ERelayPairingView`, `CursorShellLiveBridge` |

## Open decisions (not API blockers)

- **Min deployment target vs. Speech/FoundationModels:** gate with `#available(iOS 26, *)`; do not raise app minimum for post-MVP AI.
- **iOS 27 notification coalescing:** likely free UX win — still send stable `thread-id` / `apns-collapse-id` so behavior is correct on iOS 26.
- **EU/China Siri AI delay:** View Annotations + Siri fast-follow remain Post per master plan.
