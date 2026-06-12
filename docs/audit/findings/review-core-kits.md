# Governed Approvals v1 — Pre-submission Audit: Core Kits

**Scope:** AgentKit, SecurityKit, SyncKit, PersistenceKit, NotificationsKit, DiffKit + ConduitCore types.
**Branch:** `feat/governed-approvals` (worktree `governed-approvals-audit`).
**Method:** read-only correctness/security/concurrency review. No source modified, no build run.
**Focus:** correctness, edge cases, races/actor-isolation, retain cycles, security, silent failures.

Paths below are repo-relative to the worktree root.

---

## BLOCKER

None found. (Several MAJOR items below are governance/security-relevant and should be triaged before submission.)

---

## MAJOR

### [MAJOR][security] BiometricGate silently *succeeds* on `.biometryLockout` (PRIOR FLAG LOW-2, still unfixed)
`Packages/ConduitKit/Sources/SecurityKit/BiometricGate.swift:31-32`
```swift
case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
    cont.resume()  // Degrade gracefully
```
`biometryLockout` means biometrics *are* enrolled but are locked out after too many failed match attempts. Treating it like "no biometrics available" makes the gate **resolve as success with no authentication at all**. The policy used is `.deviceOwnerAuthenticationWithBiometrics` (no passcode fallback), so once an attacker forces a lockout (e.g. 5 failed Face ID attempts), the gate is fully bypassed.

**Reachability:** confirmed reachable. `AppRoot.openSession` calls `BiometricGate.shared.unlock()` immediately before loading the Ed25519 SSH private key (`Packages/ConduitKit/Sources/AppFeature/AppRoot.swift:819-821`). So a locked-out attacker holding the device can unlock and use stored SSH keys.

**Proposed fix:** On `.biometryLockout`, do **not** resume success. Either throw (`ConduitError.authFailed`) or re-evaluate with `.deviceOwnerAuthentication` (allows secure passcode fallback) and only resume on a real success. Keep graceful skip only for `.biometryNotAvailable`/`.biometryNotEnrolled` (and ideally gate even those behind device-passcode existence).

---

### [MAJOR][correctness] SSH-host run cancellation is ineffective, and every finished run is force-marked "succeeded"
`Packages/ConduitKit/Sources/AgentKit/Runtimes/SSHHostRuntime.swift:71-76, 88-97, 292-304, 331-337`

Three compounding defects in the run lifecycle:

1. **`monitorTask` is never stored.** `startRun` builds `ActiveRun(... monitorTask: nil)` and spawns the monitor in a detached `Task { ... }` whose handle is discarded (lines 71-76). `cancelRun` then calls `active.monitorTask?.cancel()` (line 92) — always a no-op, so the monitor loop is never cancelled.

2. **`finalizeRun` hardcodes success.** `monitorEvents` always calls `finalizeRun(runID:succeeded: true)` when the event stream ends (line 303), and `finalizeRun` unconditionally overwrites status (lines 331-337). There is no code path that ever passes `succeeded: false`. So a run that errors out, disconnects, or is cancelled is reported as `.succeeded` with a "Run completed." log line. For an approvals/governance product this is a silent correctness failure (a killed/failed agent run reads as a clean success).

3. **Actor-reentrancy lost update in `cancelRun`.** `cancelRun` captures `var active = activeRuns[id]` (line 89) **before** `await active.channel?.stop()` (line 93). Stopping the channel ends the event stream, which lets `monitorEvents` resume and run `finalizeRun` on the actor during the await. When `cancelRun` resumes it writes back its **stale** snapshot (line 96), either clobbering concurrent updates (approvals/log lines appended during the await) or being clobbered by `finalizeRun` → the run ends `.succeeded` instead of `.cancelled` depending on interleaving.

**Reachability:** any hosted ssh-host run that is cancelled or that ends for any reason other than success.

**Proposed fix:** Store the spawned task into `activeRuns[runID].monitorTask`. Make `finalizeRun` derive the outcome from the actual event/exit (or skip finalize when status is already terminal). In `cancelRun`, mutate via a fresh `guard var active = activeRuns[id]` re-read **after** the `await`, and guard `finalizeRun`/`monitorEvents` against overwriting an already-terminal (`.cancelled`/`.failed`) status. Also remove finished runs from `activeRuns` to bound memory (the dictionary currently grows forever).

---

### [MAJOR][data-integrity] CloudKit deletions never propagate; deleted hosts/snippets are resurrected on the next pull
`Packages/ConduitKit/Sources/SyncKit/SyncEngine.swift:98-161`, `Packages/ConduitKit/Sources/SyncKit/CloudSync.swift:51-82`, `Packages/ConduitKit/Sources/PersistenceKit/HostRepository.swift:24-28`, `Packages/ConduitKit/Sources/PersistenceKit/SnippetRepository.swift:73-76`

The sync cycle is pull-then-push (`SyncEngine.swift:80-87`). Two interacting problems destroy delete semantics:

1. **Pull re-inserts locally-deleted records and clears their tombstones.** For a remote record not present locally, `pull*` calls `upsertSync(incoming)` (`SyncEngine.swift:118-119`, `148-149`). `upsertSync` re-inserts the row **and** runs `DELETE FROM sync_tombstones ... (clearTombstone: true)` (`HostRepository.swift:26-28`, `71-76`; `SnippetRepository.swift:74-76`, `111-116`). So a host/snippet the user just deleted (tombstone pending) is pulled back in and its tombstone wiped *before* `push*` ever gets a chance to send the deletion. The pending-deletion is silently discarded and the record reappears.

2. **No server change token is persisted, so every pull is a full-zone refetch and server-side deletions are never observed.** `CloudSync.fetchChanges` builds a fresh `CKFetchRecordZoneChangesOperation.ZoneConfiguration()` with no `previousServerChangeToken` (`CloudSync.swift:54-58`). A tokenless fetch returns the entire zone and does **not** report deletions, so `recordWithIDWasDeletedBlock` (and therefore `deleteFromSync`) effectively never fires. Cross-device deletions never reach this device either.

Net effect when enabled: deletions of hosts/snippets do not stick — they bounce back on the next sync.

**Reachability:** Logic bug is live in the code, but currently *latent*: CloudKit is globally inert because `AppRoot` constructs `CloudSync()` with the default `cloudKitEnabled: false` (see next finding). Becomes active the moment sync is wired on.

**Proposed fix:** Persist and reuse the per-zone `serverChangeToken` so fetches are incremental and report deletions. In pull, skip `upsertSync` for any id with a pending tombstone (or push deletions before pulling). Do not clear a tombstone on pull-driven upsert unless the remote `modificationDate` is newer than the tombstone `deletedAt`.

---

### [MAJOR][gating/correctness] The `CONDUIT_ICLOUD_ENABLED` gate is dead code; iCloud sync is hard-disabled and, if turned on, runs **bidirectional** (contradicting the push-only contract)
`Packages/ConduitKit/Sources/SyncKit/CloudSync.swift:22-29, 155-157`, `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift:50`

`CloudSync.hasCloudKitEntitlement()` (the function that reads the `CONDUIT_ICLOUD_ENABLED` Info.plist flag) is `private static` and has **no callers** anywhere — it is dead code. The only construction site is `let cloudSync = CloudSync()` (`AppRoot.swift:50`), which takes the default `cloudKitEnabled: false`, so `container` is always `nil` and every CloudKit op no-ops regardless of the flag.

Two problems:
- The intended gate is not actually wired: flipping `CONDUIT_ICLOUD_ENABLED` to `true` does nothing, because nobody passes `hasCloudKitEntitlement()` into the initializer.
- The prior audit states iCloud sync must be **push-only** with its UI row hidden. The implemented `SyncEngine` is explicitly **bidirectional** (`pullHosts`/`pullSnippets` then push, `SyncEngine.swift:80-87`). If someone "fixes" the gate by wiring `hasCloudKitEntitlement()` in, they silently enable two-way sync (including the delete-resurrection bug above), violating the push-only contract.

**Reachability:** Currently safe-by-accident (sync never runs, so no unintended PII sync). Risk is the latent mismatch between the dead gate and the documented contract.

**Proposed fix:** Either delete the bidirectional pull paths to honor "push-only", or, if bidirectional is intended for v2, make the contract explicit and actually wire the gate: `CloudSync(cloudKitEnabled: CloudSync.hasCloudKitEntitlement())` (make the helper non-private) and add a test asserting `CloudSync()` stays inert when the flag is false.

---

## MINOR

### [MINOR][security] Redactor does not cover PEM private keys, generic `Bearer`/JWT tokens, or xAI keys (PRIOR FLAG LOW-5, still unfixed)
`Packages/ConduitKit/Sources/AgentKit/Redactor.swift:17-26`
Built-in patterns cover AWS, GitHub (`gh*`/`ghs_`), Anthropic, OpenRouter, and OpenAI keys only. Missing:
- **PEM blocks** (`-----BEGIN ... PRIVATE KEY-----`) — SSH/RSA/EC private keys would pass through unredacted if ever logged.
- **Generic `Authorization: Bearer <token>` / JWT (`eyJ...`)** — notably `CloudEntitlement.clientToken` (a control-plane bearer token, `CloudEntitlementClient`/`HostedAgentAPIClient`) is not matched.
- **xAI keys** (`xai-...`) even though `AIProvider.xai` exists (`AIKeyStore.swift:15`).
- The OpenAI pattern `sk-[A-Za-z0-9\-]{20,}` omits `_`, so underscore-containing OpenAI project keys are only partially redacted.

**Reachability:** defense-in-depth gap; only bites if these secrets reach a log/redaction path. The app should not log secrets in the first place, but the redactor is the safety net and it has holes the prior audit already flagged.
**Proposed fix:** add PEM-block, `Bearer\s+\S+`, JWT, and `xai-` patterns; add `_` to the OpenAI class. Add fixture tests for each.

### [MINOR][concurrency] Data race on `nonisolated(unsafe)` usage counters read concurrently with actor-isolated writes
`Packages/ConduitKit/Sources/AgentKit/OpenRouterClient.swift:13-14, 92-109`, `Packages/ConduitKit/Sources/AgentKit/AnthropicClient.swift:20, 111-113`
`sessionTokens`/`sessionCostUSD` are `nonisolated(unsafe)`, written inside actor-isolated `complete()` and read from `nonisolated` accessors (`latestTokenUsage()`/`latestCostUSD()`/`latestUsageRecord()`). A read can race with a write of a non-atomic value (`Double`, two-`Int` struct) → torn/stale reads (UB under the Swift memory model / TSan). The "only mutated inside the actor, so safe" comment ignores the concurrent *reader*.
**Reachability:** UI/usage-reporter polling `latestUsageRecord()` while a completion is in flight (`SessionViewModel.swift:1052`, `AgentStore.swift:585`).
**Proposed fix:** make the accessors `async` and actor-isolated, or back the counters with an atomic / a small lock; drop `nonisolated(unsafe)`.

### [MINOR][correctness/billing] OpenRouter streaming path never accumulates usage/cost, so `latestUsageRecord()` under-reports for streamed sessions
`Packages/ConduitKit/Sources/AgentKit/OpenRouterClient.swift:26-71` vs `73-90`
Only `complete()` updates `sessionTokens`/`sessionCostUSD`. `streamCompletion` yields `.usage` deltas but never folds them into the accumulators. Billing ingest reads `client.latestUsageRecord()` and skips when totals are zero (`AgentStore.ingestOpenRouterUsage` `AgentStore.swift:585-587`; `SessionViewModel.reportAIUsageIfNeeded` `SessionViewModel.swift:1049-1056`). For the streaming path (the primary one), the OpenRouter "inline cost tracking" silently reports nothing unless the consumer separately accumulates the `.usage` deltas.
**Reachability:** any managed-OpenRouter streamed chat/explain → usage/cost under-metered.
**Proposed fix:** accumulate `.usage` deltas into the actor's counters within `streamCompletion`, or document that streaming usage must be tracked by the caller and verify the caller does so.

### [MINOR][governance] RiskScorer substring rules are trivially evadable; an underscored risk can suppress approval push notifications
`Packages/ConduitKit/Sources/AgentKit/RiskScorer.swift:9-46`, `Packages/ConduitKit/Sources/NotificationsKit/Notifications.swift:34-39, 101`
Scoring is literal `lowercased().contains(...)`. Flag reordering (`rm -fr /`), extra whitespace (`rm  -rf  /`), absolute paths (`/bin/rm -rf /`), or env prefixes evade the critical/high lists and score `.low`. Because `NotificationFilter.shouldDeliver` gates on `risk.rawValue >= minRisk` (`Notifications.swift:35`, used in `notifyPendingApproval` line 101), a destructive-but-underscored command will **not** generate a push notification when the user has raised `minRisk`. The in-app Inbox still lists it, which limits severity, but a user relying on notifications could miss a dangerous pending approval.
**Reachability:** user sets `minRisk` above `.low`; agent proposes an evasive destructive command.
**Proposed fix:** the scorer is advisory by design, but since notifications gate on it, fail safe: tokenize/normalize the command, and treat unknown/parse-failure as at least `.medium`, or do not let the notification filter suppress on risk band alone (e.g. always notify for agent-proposed `command`/`patch` regardless of band, filtering only by agent/quiet-hours).

### [MINOR][reliability/silent-failure] Device-token registration is fire-and-forget with no error handling or transport check
`Packages/ConduitKit/Sources/NotificationsKit/Notifications.swift:162-171`
`registerDeviceToken` does `_ = try? await URLSession.shared.data(for: req)` — a failed registration (network error, non-2xx) is swallowed with no retry and no signal. For an approvals product this silently breaks remote (app-killed) approval delivery. Also no enforcement that `backendURL` is https (a misconfigured http URL would send the APNs token in clear).
**Reachability:** transient failure during registration → remote approvals never arrive, user unaware.
**Proposed fix:** check the HTTP status, surface/log failures, and retry with backoff; assert/require https for the backend URL.

### [MINOR][injection/correctness] WorkflowEngine substitutes parameter values unquoted and in nondeterministic order
`Packages/ConduitKit/Sources/AgentKit/WorkflowEngine.swift:42-52`
`for (param, value) in resolved { command = command.replacingOccurrences(of: "{{\(param)}}", with: value) }` iterates a **dictionary** (nondeterministic order) and performs **no shell quoting** — unlike the careful `ShellQuoting` used in `AgentResumeBuilder`. A value containing `{{otherParam}}` gets re-substituted depending on iteration order (nondeterministic output), and metacharacter-bearing values break/inject into the emitted command.
**Reachability:** currently **low** — `WorkflowEngine` is not instantiated anywhere in app sources (only `WorkflowEngineTests`). The live parameterized-snippet path is `SnippetPaletteSheet.filledBody` (`Packages/ConduitKit/Sources/SessionFeature/SnippetPaletteSheet.swift:150-158`), which is *also* unquoted but renders into a user-reviewed preview before insertion (self-injection on the user's own host).
**Proposed fix:** substitute over `orderedParams` (already computed) instead of the dict; shell-quote values destined for command lines (reuse `ShellQuoting`), or clearly scope substitution to non-shell contexts.

---

## NIT

### [NIT][hardening] AgentResumeBuilder emits env keys unquoted and allows leading `-` in tokens
`Packages/ConduitKit/Sources/AgentKit/AgentResumeBuilder.swift:33-42, 142-146`
Env keys are interpolated bare (`"\(key)=\(singleQuoted(value))"`); a key with shell metacharacters would break/inject the `env …` prefix. `shellToken` permits a bare leading `-` (allowed set includes `-`), so a `sessionId`/value starting with `-` can be read as a flag by the agent CLI (argument injection, not shell injection). Inputs are app-controlled today, so low risk.
**Proposed fix:** validate/whitelist env key names; prefix ambiguous tokens with `--`/`./` or quote them.

### [NIT][security] HostKeyStore treats keychain read errors as "unknown host", weakening TOFU on transient failures
`Packages/ConduitKit/Sources/SecurityKit/HostKeyStore.swift:21-24, 34-41`
`recorded(for:)` does `try? await keychain.read(...)` → returns `nil` on *any* error (locked keychain, transient OSStatus), not just not-found. `verify` then returns `.unknown` instead of `.match`/`.mismatch`, producing a fresh trust prompt for an already-known host. A MITM coinciding with keychain unavailability could get a re-TOFU.
**Proposed fix:** distinguish `errSecItemNotFound` (genuinely unknown) from other errors (fail closed / surface error) rather than collapsing both to `nil`.

### [NIT][robustness] `HostedAgentAPIClient.url(for:)` force-unwraps `URLComponents`/`.url`
`Packages/ConduitKit/Sources/AgentKit/HostedAgentRuntime.swift:586-598`
`URLComponents(...)!` and `components.url!` can theoretically return `nil` for malformed query strings (e.g. an `agentID` with `&`/`#` in `listRuns`). Server-generated ids make this low-risk, but a crash on bad input is avoidable.
**Proposed fix:** build queries with `URLQueryItem` (percent-encoded) and return a thrown error instead of force-unwrapping.

### [NIT][robustness] OpenAIClient.complete assumes non-optional `message.content`
`Packages/ConduitKit/Sources/AgentKit/OpenAIClient.swift:81-86`
`Choice.Msg.content` is a non-optional `String`; an OpenAI response with `content: null` (tool-call/refusal) makes decoding throw rather than yielding empty text. AnthropicClient handles optional text. Minor robustness asymmetry.
**Proposed fix:** make `content` optional and default to `""`.

### [NIT][resource] SyncEngine.start() can leak a prior notification task; counters grow unbounded
`Packages/ConduitKit/Sources/SyncKit/SyncEngine.swift:48-61, 83`
Calling `start()` twice overwrites `notificationTask` without cancelling the previous observer (task leak). `conflictCount` accumulates across cycles and is never reset.
**Proposed fix:** cancel any existing `notificationTask` before reassigning; reset/define the lifetime of `conflictCount`.

---

## Areas reviewed and found sound
- **Keychain** (`SecurityKit/Keychain.swift`): generic-password items default to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` / `…AfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable: false`; no `…Always` accessibility; no UserDefaults/plaintext storage of secrets. Upsert via delete+add avoids the `SecItemUpdate` accessibility quirk.
- **KeyStore**: SSH private keys stored only in Keychain; documented rationale for raw Ed25519 representation; passphrases never persisted.
- **OpenSSHKeyParser / BcryptPBKDF / Blowfish**: bounds-checked `Reader` (length-prefixed reads guarded against truncation; no 64-bit overflow), correct AES-CTR big-endian counter, faithful bcrypt_pbkdf port.
- **PairingCrypto**: X25519 + HKDF-SHA256 + ChaCha20-Poly1305 with random 12-byte nonce (`SecRandomCopyBytes`), AAD-bound frames, version check (M5+; not on the v1 hot path).
- **AI clients**: API keys travel only in headers (`Authorization`/`x-api-key`), never in URLs/logs; decode via typed `Decodable`/guarded `try?`; streaming honors `Task.checkCancellation()` and `onTermination` cancels the task. (Gaps: no explicit timeouts/retry-backoff — acceptable for v1; usage-accumulation gap tracked above.)
- **GRDB layer** (`AppDatabase` + repositories): append-only migrations v1→v7 in correct order; all SQL parameterized (no injection); reads/writes go through `DatabaseWriter` (thread-confined); row decoders guard id parsing and fall back gracefully on malformed JSON; `ValueObservation` cancellation wired via `onTermination`.
- **AgentRegistry / AgentHookDef**: strong decode-time validation (id charset, reserved-kind collision, required resume placeholders, non-blank names); value types are `Sendable`/`Hashable`.
- **AuditRepository**: parameterized inserts, bounded `recent(limit:)`, deterministic JSON export.
