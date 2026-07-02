# 07 — Security and trust

> Research method: apple-docs MCP search index returned zero hits for App Attest/LocalAuthentication/
> agentic-security terms even for pre-2026 API names (appears stale/broken for this query set) —
> relied on WebSearch/WebFetch of live developer.apple.com pages plus direct inspection of the
> shipped iOS 27.0 SDK headers/swiftinterface files. WWDC26 session pages were fetched in full
> (transcripts/descriptions), which is strong evidence; SDK grep is ground truth for API surface.

## Current threats (from `02-current-codebase-state.md`)

Three confirmed gaps, in order of severity: (1) approvals are not hash-bound to the exact
command/diff/tool-input the user saw; (2) the no-client path fails **open** — auto-approves after
8 seconds; (3) the E2E relay has no replay resistance (no sequence/epoch/replay cache). Relay
*transport* auth itself (shared control-plane secret, per-session token, constant-time compare,
TTLs, prod secret guard — `daemon/push-backend/relay_security.go:33,98,143`) is already strong and
is not in question here.

## API / capability table

| API/capability | Min OS + Xcode | Beta? | Entitlements | Restrictions | Background limits | Privacy/App Review | Applicability | Source | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| `DCAppAttestService` (`generateKey`, `attestKey`, `generateAssertion`) | iOS 14.0+, unchanged in iOS 27 SDK | N (API stable; WWDC26 session content is new) | `com.apple.developer.devicecheck.appattest-environment` | **Does not work in Simulator** (stable, unchanged Apple platform behavior) | Attestation should run in background tasks off the interactive path (explicit WWDC26 guidance); assertion generation is CPU-expensive, must not be done in bulk | No PII collected by the API itself; server stores receipts/public keys | Main app (needs Secure Enclave); not usable inside most extensions without their own entitlement + physical device | `DeviceCheck.framework/Headers/DCAppAttestService.h:14`; WWDC26 s201 | High |
| App Attest — iOS 27 authenticator-data extensions (Launch Validation Category, Bundle Version) | iOS 27.0+ | **Y — new** | Same as above | Server must parse new W3C-WebAuthn-formatted extension fields; older servers silently ignore them (non-breaking) | N/A | Adds forensic signal (TestFlight vs App Store launch) — fraud/version-mismatch detection | Main app | WWDC26 s201 transcript | High (directly stated) |
| App Attest fraud metric (`risk_metric` receipt POST) | iOS 14+ infra | N | Requires stored receipt | 30-day rolling unique-key count per device, server-side | N/A | Use as investigative signal only, **never a hard block** (explicit Apple guidance) | Backend, not the app | WWDC26 s201 | High |
| `DCDevice` (DeviceCheck, non-attestation) | iOS 11.0+ | N | `com.apple.developer.devicecheck` | Works in Simulator (degraded); far weaker guarantee than App Attest — no Secure Enclave binding, no per-key assertions; **zero iOS-27 additions found** | N/A | — | Anonymous fraud-scoring (e.g. trial abuse), not per-approval binding | `DeviceCheck.framework/Headers/DeviceCheck.h,DCError.h` (grepped, no `ios(27` markers) | Medium-high |
| `LAContext`/LocalAuthentication (`.deviceOwnerAuthenticationWithBiometrics` vs `.deviceOwnerAuthentication`) | iOS 8+/9+ | N — no new iOS-27-gated symbols found | `NSFaceIDUsageDescription` Info.plist key | `LAContext`'s biometric "session" does not persist across process boundaries — a fresh `LAContext` in a different process has no memory of a prior auth elsewhere | N/A | Prompt reason string is reviewed as normal UX copy | Main app; extension applicability is the crux of the cross-process question below | `LocalAuthentication.framework/Headers/LAContext.h` (grepped) | Medium — grep found no new API, not an exhaustive symbol diff |
| `LAContext` inside a widget extension / Live Activity process | N/A | N/A | N/A | **No Apple statement found saying this directly fails for WidgetKit specifically.** Strong analogy only: `LAErrorNotInteractive` (-1004) is documented for Network Extension's `PacketTunnelProvider` — a structurally similar non-interactive extension context — but this is not a WidgetKit-specific citation | N/A | N/A | Widget extension / Live Activity content | Apple Developer Forums thread 129480 | **Low-medium — explicitly flagged as inference by analogy, not a direct fact** |
| `IntentAuthenticationPolicy` (`.alwaysAllowed`, `.requiresAuthentication`, `.requiresLocalDeviceAuthentication`) on `AppIntent` | Pre-existing App Intents enum; WWDC26 s347 reinforces it as *the* mechanism for iOS-27-era agentic gating | N (mechanism itself); reinforced framing is new | None beyond normal App Intents adoption | **This is the real answer to the cross-process question.** `authenticationPolicy` is a static/declarative property on the intent type, enforced by the **system's** App Intents dispatch infrastructure *before* `perform()` runs — the system presents the Face ID/passcode challenge using system-owned UI, not the extension calling `LAContext` itself. Schema-adopted intents can only tighten, never weaken, the schema default (compiler-enforced) | System-mediated — no background-task constraints apply to the auth step | Mitigates "attacker with a locked device invokes Siri/widget without unlocking" — the same threat class as someone tapping an Approve button on a backgrounded, unlocked-but-not-attended Live Activity | Widget / Live Activity interactive buttons, Siri, Shortcuts, Spotlight — anywhere an `AppIntent` is the entry point | WWDC26 s347 transcript; `developer.apple.com/documentation/appintents/intentauthenticationpolicy` | **Medium-high** — mechanism confirmed for App Intents generally; its specific Live-Activity-button applicability is inference from "any AppIntent entry point," not a transcript line naming Live Activities explicitly. Verify on-device before relying on it. |
| `.onToolCall` modifier (Foundation Models) — synchronous confirm-or-throw gate before every tool call | iOS 27.0+ | **Y — new** | None extra | Runs in-process with the model session; blocks execution until the closure returns/throws | N/A | Not App-Review-relevant directly | Main app only (Foundation Models is on-device/Apple-Intelligence-only, not usable from a widget) | WWDC26 s347 (session-verified code sample) | High |
| Keychain `kSecAccessControl`/`biometryCurrentSet` | iOS 9+/11.3+ | N | None | `biometryCurrentSet` invalidates the protected key the instant Face ID/Touch ID enrollment changes (stronger than `biometryAny`, which survives enrollment changes) — **not independently re-verified against the iOS 27 SDK this pass**, carried from stable long-standing documentation | N/A | — | Main app, any process with Keychain access-group entitlement | Apple's "Restricting Keychain Item Accessibility" doc (stable) | Medium |
| Passkeys/WebAuthn (`ASAuthorizationPlatformPublicKeyCredentialProvider`) | iOS 16+ | N | Associated domains entitlement | **Not a good fit** for authenticating a paired relay device/session — passkeys authenticate a user to a website/RP identifier, not device-to-device pairing; would require standing up a WebAuthn relying party for marginal benefit over the existing E2E pairing-code + Keychain design | N/A | — | Main app | General WebAuthn knowledge, not deeply re-researched this pass — explicitly deprioritized given low relevance | Medium |

## Agentic approval security — the three questions

### 1. Fail-open 8s grace vs. now-correct indefinite wait

**Apple's WWDC26 session 347 does not give explicit fail-open/fail-closed timeout guidance** — the
transcript was checked directly and this was flagged as not addressed. Apple's own design has no
timeout-based auto-approve concept anywhere: gate risky `AppIntent`/tool actions with
`authenticationPolicy` and `.onToolCall`; if the confirmation callback throws, the tool call
simply does not execute. There is no "confirmation timed out, so proceed" path in Apple's own
human-in-the-loop primitives — which is itself informative.

General security-engineering guidance (NIST SP 800-53 access-control / fail-secure principles,
standard HSM/payment-authorization design — not Apple-specific but directly applicable):

- **A human-approval gate protecting agentic tool execution should fail closed by default.** An
  unreachable approver is evidence of *reduced* trust in the environment (network partition,
  offline/compromised device, a dropped relay frame), not evidence the action is safe to
  auto-approve.
- Lancer's current 8-second auto-approve is the textbook fail-open anti-pattern for exactly this
  threat model: an AI agent executing shell commands/diffs on the user's behalf. Anyone (or any
  misbehaving agent under prompt injection — WWDC26 s347's "lethal trifecta") who can suppress
  client reachability for 8 seconds — kill the relay connection, jam Wi-Fi, or simply have the
  phone screen off at the wrong moment — gets unconditional approval of *any* pending action.
- **Recommendation:** replace the blanket 8s-then-auto-approve with a **risk-tiered fallback**:
  low-risk/reversible actions (read-only commands, `git status`) can keep a bounded auto-approve
  grace period; destructive/irreversible/high-blast-radius actions (deletes, force-push,
  credential access — reuse the existing blast-radius classification from the Governance work)
  should **fail closed** (deny/hold) when no client is reachable. This reuses infrastructure
  Lancer already built rather than requiring new plumbing.
- If a grace period is kept for UX reasons, make the window configurable per policy tier and
  ensure every auto-approved decision is prominently surfaced in the audit trail (already built —
  audit verify/export from the governance work) so a silent auto-approval is at least discoverable
  after the fact.

### 2. Hash-binding the approval to the exact content shown

Neither App Attest nor App Intents solve this "for free" — it is squarely a protocol-design
responsibility. Two convergent sources:

- **From WWDC26 201 (App Attest) directly:** *"App Attest proves payload integrity in transit, not
  user approval of payload contents... Developer must implement additional controls: Request
  specific nonce per transaction, tie nonce to user action in app UI, validate server receives
  matching nonce in assertion."* This is Apple confirming, in their own words, that attestation
  machinery does **not** prove "the user looked at diff X and tapped Approve on diff X" — even if
  Lancer adopted App Attest fully, this specific gap would remain unsolved by it.
- **Standard TOCTOU-safe human-approval pattern**: the daemon computes
  `approvalHash = SHA-256(canonicalize(command || args || cwd || diffContent || toolInputJSON))`
  once, when the pending-approval record is created. The phone's UI renders exactly the content
  matching that hash; the decision message echoes the hash back. The daemon **re-verifies the
  echoed hash against the still-pending record before executing** — mismatch (stale UI, a race, a
  second dispatch mutating the command) means refuse and re-request approval, not execute. This is
  the same shape as an idempotency key bound to exact charge parameters, or a CSRF token bound to
  form state — well-trodden, not novel.
- Given Lancer already has E2E encryption, HMAC the content-hash with the same session key used
  for the E2E channel, so a relay-side attacker who can't decrypt still can't forge a
  valid-looking approval for different content — defense in depth beyond the encryption itself.
- **Concretely for Lancer:** extend the approval payload schema on both `daemon/lancerd/dispatch.go`
  and the iOS decision path to carry this hash. This is a schema + verification-logic change, not
  an Apple API — the single highest-priority security fix in this report.

### 3. E2E relay replay resistance

Apple's WWDC26 materials don't address WebSocket/relay replay protection — this is standard
applied-cryptography territory, with two directly transferable reference architectures:

- **WireGuard-style counter + sliding window**: each encrypted frame carries a monotonically
  increasing 64-bit counter; the receiver keeps a small bitmap of recently-seen counters and
  rejects any frame at-or-below the window floor or already marked seen. This is exactly the shape
  App Attest's own assertion counter uses for the same reason ("counter must be strictly
  increasing; decreasing/steady counter = potential compromise" — WWDC26 s201) — Lancer already
  has an in-house precedent to point to.
- **Signal-protocol-style per-message key ratchet**: probably overkill for Lancer's current design
  (forward secrecy per message), noted for completeness.
- **Minimum viable fix**: add a monotonic sequence number **inside the encrypted envelope** (not
  relay-visible, so a relay-side attacker can't selectively drop-and-replay based on visible
  sequence info) plus a small in-memory replay cache on the daemon side (last-N seen
  `(sequence, messageId)` per session) — reject any frame whose sequence isn't strictly greater
  than the last accepted one for that session+generation. Lancer already has prior art for exactly
  this class of fix (the 2026-07-01/02 connect-generation-counter fix for stale-socket decrypt
  failures) — this composes cleanly with that existing pattern.
- Bind the sequence number into the same HMAC as the content-hash from item 2 — one signed
  envelope serving both replay resistance and content binding, rather than two independent
  mechanisms.

## The BiometricGate question — RESOLVED 2026-07-02 (owner decision)

**Decision: no Face ID / biometric gate on approvals for V1, full stop.** The owner confirmed this
directly after reviewing this section — fast tap-to-approve from anywhere (including the Lock
Screen), with no lock-screen friction, is a deliberate, informed product choice, not an oversight.
`IntentAuthenticationPolicy` (the system-owned Face-ID-prompt mechanism researched above) is
**not** to be implemented for V1 under any framing, narrow or otherwise.

`SecurityKit/BiometricGate.swift` stays in the tree unchanged — it still gates the legacy SSH
Ed25519 private-key unlock path (`CredentialResolver.swift`, `AppRoot.swift:1939`), which is
explicitly **V2 scope** (SSH is not wired into V1 navigation per `ARCHITECTURE.md` §0.1) and
therefore doesn't execute for any V1 user regardless. No source change was needed or made — this
was purely a report-finalization decision. Do not revisit this for V1; if a future audit wants to
reopen approval-gating, that's a V2+ conversation tied to whatever SSH/session-holding story V2
adopts, not something to bundle into V1 hardening work.

## Recommended hardening sequence

1. **Approval content-hash binding** (§2 above) — highest priority, closes the largest confirmed
   gap, pure protocol/schema work, no Apple API dependency, no OS version gate.
2. **Risk-tiered fail-closed no-client policy** (§1 above) — reuses existing blast-radius
   classification, no new infrastructure.
3. **E2E replay resistance** (§3 above) — composes with the existing connect-generation-counter
   pattern already shipped.
4. **App Attest for sensitive relay registration/device binding** — genuinely new value (iOS 27
   authenticator-data extensions), but note simulator incompatibility means it can only be tested
   on physical devices; scope to account/device-binding flows, not every approval (App Attest
   proves the app/device is genuine, not that this specific approval matches this specific
   content — that's §2's job, not App Attest's).
5. ~~`IntentAuthenticationPolicy` for Live-Activity/widget approve buttons~~ — **rejected for V1**
   (owner decision, 2026-07-02): no Face ID/biometric gate on approvals, full stop. Not on the
   roadmap.

## Sourcing caveats

- Entitlements/App Review implications are the weakest-evidence area throughout — nothing in
  grepped SDK files declares an Info.plist key or entitlement string for the WWDC26-new security
  APIs, and WWDC26 transcripts didn't surface explicit App Review guidance either. Treat every
  "not found" as "not found in available evidence," not "confirmed absent."
- The `LAErrorNotInteractive`-in-widget-extension claim is explicitly flagged as inference by
  analogy to Network Extension's `PacketTunnelProvider`, not a direct WidgetKit-specific Apple
  statement — verify on-device before treating as settled fact.
- Passkeys/WebAuthn relevance to relay-device pairing was explicitly deprioritized rather than
  exhaustively researched, given low apparent fit.

## Sources

- [Secure your apps with App Attest — WWDC26 Session 201](https://developer.apple.com/videos/play/wwdc2026/201/)
- [Secure your app: mitigate risks to agentic features — WWDC26 Session 347](https://developer.apple.com/videos/play/wwdc2026/347/)
- [IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy)
- [IntentAuthenticationPolicy.requiresLocalDeviceAuthentication](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy/requireslocaldeviceauthentication)
- [DeviceCheck documentation](https://developer.apple.com/documentation/DeviceCheck)
- Apple Developer Forums thread 129480, "Biometrics error LAErrorNotInteractive in network extension"
- Direct SDK inspection: `iPhoneOS27.0.sdk/.../DeviceCheck.framework/Headers/DCAppAttestService.h:14`;
  `.../LocalAuthentication.framework/Modules/LocalAuthentication.swiftmodule/arm64e-apple-ios.swiftinterface`
- General replay/TOCTOU references: OWASP WebSocket Security Cheat Sheet, WireGuard protocol
  (counter + sliding-window replay protection) — established prior knowledge, not re-fetched this
  pass, flagged as such.
