# Governed Approvals v1 — UI / Features Pre-Submission Review

**Reviewer scope:** KeysFeature, FilesFeature, DiffFeature + DiffKit, PreviewFeature + PreviewKit, SettingsFeature, DesignSystem.
**Branch:** `feat/governed-approvals` (worktree `governed-approvals-audit`).
**Constraints honored:** no source modified, no build run. Findings are read-only analysis.

Each finding has been through an adversarial reachability pass before listing. Format:
`[SEVERITY] path:line — issue. Reachability. Proposed fix.`

---

## Summary

- **Blockers:** 0 — release billing/Pro gating is sound (all DEBUG bypasses are `#if DEBUG`/file-guarded and `.unknown` purchase state stays locked); no private-key material is shown/copied/logged; no crashers on normal paths.
- **Major:** 4 — snippet tag data-loss on edit, BillingView usage stub, TextPreview binary-detection defeated, encrypted-key import gated on a fragile English error-substring.
- **Minor/nit:** many (dead code, fragile patterns, missing empty states, M6 limitations).
- **Theme/Token drift:** 14 meaningful violations (mono text via `.system` + hardcoded colors) across 6 modules, plus a large set of *acceptable* SF-Symbol `.system(size:)` sizings.

Verified-good (prior flags resolved):
- `AgentIsland` / `AgentStatusHeader` no longer use `.system` text fonts — they use `DI.mono(_:)` / `.dsSansPt` (always-dark `DI` palette is the documented exception). Prior `.system`-font flag is **resolved**.
- `isPro` DEBUG bypass + `DebugSeeder` are correctly compiled out of Release (`PurchaseManager.isPro`/`hasCloudEntitlement` `#if DEBUG`; `DebugProBypassToggle` `#if DEBUG`; `DebugSeeder.swift` file-level `#if os(iOS) && DEBUG`; `AppRoot`/`SessionShellView` bypasses `#if DEBUG`).
- Pro IAP product id `dev.conduit.mobile.pro` and `$14.99` fallback price match the spec (`PurchaseManager.proProductID`).
- Terminal settings toggles/pickers are all actually consumed (font/keepAlive/preventSleep/haptics/scrollback/theme/all gesture flags); "Off" keep-alive (0) and "Unlimited" scrollback (0) are handled by the real readers.

---

## BLOCKER

None.

---

## MAJOR

**[MAJOR] SettingsFeature/SnippetEditorView.swift:178-182 — editing a snippet silently drops `tags` and `hostTags` (data loss).**
`SnippetEditSheet` initializes `hostTagsRaw`/`tagsRaw` from the snippet (lines 157-158) and defines `parseTags(_:)` (line 280), but the Save action constructs `Snippet(id:name:body:arguments:useCount:createdAt:)` with **no** `tags:`/`hostTags:` arguments. `Snippet.init` defaults both to `[]` (ConduitCore/Snippet.swift:20-21), so any snippet that has tags/host-tags (e.g. imported from Warp YAML or arrived via SyncEngine) is rewritten with empty arrays on every edit. `modifiedAt` also resets to `.now`, so LWW propagates the loss to other devices.
*Reachability:* any snippet with non-empty `tags`/`hostTags` opened in the editor and saved. The editor has no tag-editing UI, so `hostTagsRaw`/`tagsRaw`/`parseTags` are also dead, but the round-trip wipe is the real bug.
*Fix:* pass `hostTags: snippet.hostTags` and `tags: snippet.tags` through `original…` captured state (mirroring `originalCreatedAt`/`originalUseCount`), or wire the existing `parseTags(hostTagsRaw)` / `parseTags(tagsRaw)` into the constructor and add the missing tag fields to the form.

**[MAJOR] SettingsFeature/BillingView.swift:222 — "AI usage today" is a hardcoded `$0.00` stub.**
`loadCloudBilling()` fetches `creditBalance` from the backend but then unconditionally sets `usageTodayUSD = 0`; nothing else ever writes it. The "AI usage today" row (lines 150-161) therefore always renders `$0.00` even for an entitled, actively-metered cloud user.
*Reachability:* US storefront (`externalStripeEligible == true`) → `cloudBillingSection` renders the row. Shipping a billing screen that always claims $0 usage is a consumer-trust / App-Store-review risk and contradicts "BillingView must match backend billing/credits/entitlements".
*Fix:* fetch real per-day usage from the control plane (the `HostedAgentAPIClient` is already constructed here), or remove the row until the usage endpoint is wired.

**[MAJOR] FilesFeature/TextPreview.swift:13-16 — binary detection is defeated by the ISO-Latin-1 fallback; binary files render as garbage instead of the "Binary file" placeholder.**
`text` decodes UTF-8, then falls back to `.isoLatin1`. Every possible byte (0x00–0xFF) is a valid ISO-Latin-1 scalar, so `String(data:encoding:.isoLatin1)` essentially never returns `nil`. The `else` branch with the `ContentUnavailableView("Binary file", …)` (lines 29-39) is effectively dead, and binary content (images, archives, executables read by the SFTP preview) is rendered as mojibake text.
*Reachability:* SFTP browser → tap any non-UTF-8 file (`SFTPFilesViewModel.navigate` reads up to 512 KB and presents `TextPreview`). Common.
*Fix:* drop the `isoLatin1` fallback, or gate it behind a binary heuristic first (presence of NUL byte / high ratio of non-printable bytes ⇒ show the binary placeholder).

**[MAJOR] KeysFeature/KeyImportView.swift:75 — encrypted-key import relies on an English error-substring match; silent failure on rewording/localization.**
The transition into the passphrase-prompt state is `if msg.localizedCaseInsensitiveContains("passphrase") && effectivePassphrase == nil`. Control flow keys off the *localized* text of `ConduitError.errorDescription`. It works today (English descriptions contain "passphrase"), but any localization, copy edit, or upstream error-message change makes encrypted keys fall through to `.failed(...)` — the passphrase `SecureField` never appears and the user cannot import a passphrase-protected key, with only a confusing generic error.
*Reachability:* importing any encrypted OpenSSH key once the error wording changes / is localized. Latent now, but a brittle gate on a core path.
*Fix:* surface a typed error case (e.g. `ConduitError.encryptedKeyRequiresPassphrase` / `.wrongPassphrase`) from `KeyStore.importEd25519FromPEM` and switch on it instead of substring-matching the description.

---

## MINOR

**[MINOR] KeysFeature/KeysView.swift:175 & FilesFeature/FilesView.swift:418 — `.alert(isPresented: .constant(vm.error != nil))` anti-pattern.**
A `.constant` binding can't be driven back by the system; dismissal only works because the OK button nils `vm.error` and the view recomputes. Swipe/secondary dismissals leave state inconsistent and it's fragile across iOS releases.
*Fix:* use a real `Binding(get:set:)` that clears `vm.error` on `set(false)` (same shape already used for the rename/chmod alerts in `FilesView`).

**[MINOR] KeysFeature/KeysView.swift:243-248 — copied SSH public keys set no pasteboard expiration; no clipboard auto-expire exists anywhere.**
`copy(_:)` does `UIPasteboard.general.string = s` with no `expirationDate`. Only **public** keys / fingerprints are ever copied (private material is never shown or copied — verified), so risk is low, but the requested clipboard auto-expire control is absent across the app (also `AddHostView`, `ManagementViews2`, out of scope).
*Fix:* if a clipboard-expiry policy is required, use `UIPasteboard.general.setItems(_:options:)` with `.expirationDate`.

**[MINOR] KeysFeature/KeysView.swift:66-91, 264-273 — dead code; `importFromFile` has a latent security-scope bug.**
`KeysViewModel.importFromText`, `importFromFile`, and `StoredKey.algorithmLabel` are defined but never referenced anywhere in the repo (the UI imports via `KeyImportView`). `importFromFile` reads `Data(contentsOf:)` without `startAccessingSecurityScopedResource()` — it would fail for document-picker URLs if ever wired up (unlike `KeyImportView`, which does it correctly).
*Fix:* delete the dead members, or route the UI through them and add security-scoped access.

**[MINOR] KeysFeature/KeyImportView.swift:50-52 — redundant/dead branch in `effectivePassphrase`.**
The expression simplifies to `passphrase.isEmpty ? nil : passphrase`; the `showPassphraseField && …` branch is unreachable-as-distinct. Harmless but misleading.
*Fix:* collapse to the one-liner.

**[MINOR] SettingsFeature/TerminalSettingsView.swift:286-310 — `TerminalPrefs` enum is entirely unused dead code.**
No references anywhere; all real consumers (`SessionViewModel`, `RawTerminalView`, `ChatTranscriptView`, `Haptics`, `AnsiSGRParser`) read the `UserDefaults` keys directly. Note its `keepAliveInterval` would *mis-map* the "Off" (0) option to 60 if it were ever used — another reason to delete rather than adopt it.
*Fix:* remove the enum (or adopt it everywhere and fix the `0 → 60` mapping).

**[MINOR] FilesFeature/FilesView.swift:9-123 — `FilesView`/`FilesViewModel` (the `ls -la` browser) are dead code.**
Not referenced anywhere; the shipping Pro surface uses `SFTPFilesView`/`SFTPFilesViewModel` (`SessionShellView.swift:152`). The `ls -la` parser also has minor robustness gaps: `split(omittingEmptySubsequences:true)` collapses runs of spaces inside filenames, and symlink rows (`name -> target`) fold the arrow/target into `name`.
*Fix:* delete the legacy view/VM, or mark clearly as unused.

**[MINOR] FilesFeature/FilePreviewView.swift:20-50, 54-68 — unused in production + non-lazy line rendering.**
`FilePreviewView` is only reached via `filePreviewDrawer` (defined here but never called) and `DebugGalleryView`. Its body builds `ForEach(lines.indices)` inside a plain `VStack` (not `LazyVStack`), so a large file would eagerly materialize one row per line. The "keyword tint" promised in the header comment is not implemented.
*Fix:* if kept, switch to `LazyVStack`; otherwise remove the view + the unused `filePreviewDrawer` helper.

**[MINOR] DiffFeature → DiffKit/UnifiedDiff.swift:22 — `FilePatch.id` returns a fresh `UUID().uuidString` when both paths are nil, giving unstable SwiftUI identity.**
`id` is a computed property; for a patch where `oldPath == nil && newPath == nil` (e.g. both sides `/dev/null`, or a malformed block), each access yields a new UUID. In `ForEach(diff.files)` (DiffView.swift:22) this breaks diffing/animation and can cause re-render churn.
*Reachability:* malformed or dev-null-both file patches. Edge but real.
*Fix:* compute a stable id once (store a generated UUID in `init` as a fallback), not in a getter.

**[MINOR] DiffFeature/DiffView.swift:95-109 — hunk lines render in a non-lazy `VStack` (large-hunk performance).**
The outer `LazyVStack` only lazily renders file sections; within a file, `ForEach(hunk.lines.indices)` is inside a regular `VStack`, so a single huge hunk eagerly builds every line view. Relevant to the stated "large-file handling" requirement.
*Fix:* render lines via `LazyVStack`, or cap/virtualize very large hunks.

**[MINOR] DiffKit/UnifiedDiff.swift:118-131, 134-143 — two silent parser drops.**
(1) A `@@` hunk header encountered before any file header sets `pendingHunk`, but `commitHunk()` appends to `current?.hunks` while `current == nil`, so the hunk is silently discarded with **no** `parseErrors` entry. (2) A bare empty line (`""`) inside a hunk matches none of the `+/-/space/\` prefixes and hits `else { continue }`, dropping empty context lines.
*Fix:* record a `parseErrors` entry when a hunk has no enclosing file; treat `""` as an empty context line.

**[MINOR] PreviewFeature/PreviewViewModel.swift:13, 36 — `manualPortText` and `remoteHost` are dead state.**
`ManualPortSheet` (PreviewToolbar.swift:139-181) uses its own local `portText` and writes `selectedPort`; `manualPortText` is never read/written. `remoteHost` is never used (`PreviewSurface` hardcodes `conduit-preview://localhost/`).
*Fix:* remove the unused properties.

**[MINOR] PreviewFeature/PreviewViewModel.swift:54-68 — screenshot temp files are never cleaned up.**
`captureScreenshot` writes `preview-<uuid>.png` into `temporaryDirectory` on every capture; nothing deletes them. Minor disk growth.
*Fix:* clean up after the composer consumes the file, or write to a single reused path.

**[MINOR] PreviewKit/PreviewKit.swift:33-37, 72-96 — SSH-proxy preview silently corrupts binary assets and drops HTTP status/redirects.**
`executeCollected` returns a `String`; binary responses (images/fonts) are lossily decoded then re-encoded via `Data(body.utf8)` ⇒ corruption. `parse` also synthesizes a plain `URLResponse` (no real status code, no 3xx redirect handling, no cookies). This is the documented M6 curl-over-SSH baseline, but it's a user-visible silent failure for non-text assets.
*Fix:* document the limitation in UI, or move to the M7 stream/SOCKS path for binary + status fidelity.

**[MINOR] PreviewKit/LocalPortForward.swift — no-op M6 placeholder.**
`start`/`stop` do nothing real (`localPort = remotePort`); forwarding is actually done per-request by `SSHProxyURLSchemeHandler`. By design, but it's a stub that reads like a working forwarder.
*Fix:* keep but clearly label as a placeholder, or remove until M7.

**[MINOR] AppFeature/SessionShellView.swift:53-65, AppFeature/AppRoot.swift:156-168, SettingsFeature/PurchaseManager.swift:44-51 — `isPro` logic triplicated with divergent DEBUG semantics.**
Three independent `isPro` implementations. In DEBUG with no overrides: `PurchaseManager.isPro` and `SessionShellView.isPro` default **unlocked** (`conduitDebugProBypass` absent ⇒ `true`), but `AppRoot.isPro` defaults **locked** (only `CONDUIT_FORCE_PRO=1` unlocks). The `DebugProBypassToggle` therefore unlocks session surfaces + BillingView but not `AppRoot`-driven paywalls. Release behavior is identical and correct across all three (`purchased` only, `.unknown` locked), so this is DEBUG-only confusion, but it invites drift.
*Fix:* centralize on `PurchaseManager.shared.isPro` and delete the copies.

**[MINOR] SettingsFeature/PremiumComparisonView.swift:20 vs AppFeature/SessionShellView.swift:173-184 — Free/Pro table contradicts gating for "inbox".**
The comparison lists "Agent inbox & approvals" as `freeTier: true` (and renders a "(free)" tag), but the per-session `.inbox` surface is gated behind `if isPro` with a `PaywallSheet(featureName: "AI Agent Inbox")`. A reviewer/user can read this as a free feature that then hits a paywall.
*Fix:* reconcile copy (clarify global Inbox = free vs session-embedded inbox = Pro) or align the gate.

**[MINOR] KeysFeature/KeyImportView.swift:43-83 — raw private-key PEM is retained in `@State pemText` after a parse failure.**
On `.failed`/`.needsPassphrase` the PEM (private key material) stays in view-model memory for retry; it's cleared on success (lines 68-69) and on Cancel/Done via `reset()`. Acceptable, but the sensitive blob lives longer than necessary on the failure path.
*Fix:* acceptable as-is; optionally clear `pemText` if the sheet is backgrounded/dismissed without `reset()`.

**[MINOR] FilesFeature/FilesView.swift (SFTPFilesView) & legacy FilesView — no empty-folder state.**
An empty directory shows only the path header + ".." with no "empty folder" affordance; SFTP errors are surfaced only via the alert. `DSEmptyState` exists and is used elsewhere (KeysView, SnippetEditorView).
*Fix:* add a `DSEmptyState` when `entries.isEmpty && !isLoading && error == nil`.

**[NIT] SettingsFeature/SnippetEditorView.swift:217, 270-272 — `ForEach(arguments.indices, id: \.self)` + index-keyed edit sheet.**
Index-as-identity is fragile; deleting an argument while the `.sheet(item:)` holds a stale `IdentifiableIndex` could read `arguments[idx.value]` out of range. Not currently reachable (sheet and inline delete aren't simultaneous), but brittle.
*Fix:* identify arguments by a stable id.

**[NIT] SettingsFeature/BillingEligibility.swift:4 — dead `"US"` branch.**
`Storefront.countryCode` is ISO-3166-1 alpha-3 ("USA"); the `code == "US"` comparison never matches. Harmless.

**[NIT] SettingsFeature/SettingsView.swift:168, 333 — `flag.autonomyPresets` gates only its own section and has no toggle UI (always-on default `true`).**
Not dead (it does gate `agentApprovalsSection`) but nothing can flip it.

**[NIT] SettingsFeature/ShortcutBarEditor.swift:14 — body type-check cost (prior 331 ms flag).**
The single `body` nests two `List` sections with per-row `Button`/`HStack`/`.background` closures plus a reset section; this is the kind of expression that inflates type-check time. Functionally fine.
*Fix:* extract `activeKeyRow`/`availableKeyRow` into `@ViewBuilder` helpers (as done in `SettingsView`) to keep the inferencer's budget down.

**[NIT] SettingsFeature/PolicyEditorView.swift:30-79 — uses default `Form`/`Section` chrome, not the BLOCKS `settingsCard` language.**
Visual inconsistency vs the rest of Settings (square cards, tokenized). Power-user bridge screen, low priority.

---

## Theme / Token drift

Mostly minor individually, collectively a Phase-5 theme concern. Two true classes below; the SF-Symbol `.system(size:)` sizings are listed separately as *acceptable*.

### Mono **text** rendered with `.system(…, design: .monospaced)` instead of `.dsMono*` (Fira Code)
These render real text content with the OS monospaced face, breaking glyph/metric consistency with the BLOCKS type system.

- `FilesFeature/TextPreview.swift:23` — file body `Text` → use `.dsMonoPt(13)` / `.dsMono(.caption)`.
- `FilesFeature/FilePreviewView.swift:28` — line-number gutter → `.dsMonoPt(11)`.
- `FilesFeature/FilePreviewView.swift:35` — line content → `.dsMonoPt(13)`.
- `FilesFeature/FilesView.swift:227` — `SFTPEntryRow` filename → `.dsMonoPt(14)` (matches the legacy `FilesView` rows which correctly use `dsMonoPt`).
- `DiffFeature/DiffView.swift:133` — diff line text → `.dsMono(.caption)`.
- `PreviewFeature/PreviewToolbar.swift:131` — active-port label → `.dsMonoPt(14)`.
- `SettingsFeature/PolicyEditorView.swift:41` — YAML `TextEditor` → `.dsMono(.caption)`.

### Hardcoded colors instead of tokens
- `KeysFeature/KeyImportView.swift:195` — `.foregroundStyle(.green)` → `t.ok`.
- `KeysFeature/KeyImportView.swift:214` — `.foregroundStyle(.orange)` → `t.warn`.
- `PreviewFeature/PreviewToolbar.swift:155` (`ManualPortSheet`) — `.foregroundStyle(.red)` → `t.danger` (and adopt `@Environment(\.conduitTokens)` here; the sheet currently has no token access).
- `FilesFeature/FilesView.swift:272` — `renameSwipeButton.tint(.blue)` → `t.accent` (or `t.info`).
- `DesignSystem/Components/InboxCards.swift:128` — selected letter chip `.foregroundStyle(.white)` → `t.accentFg`.
- `DesignSystem/Components/InboxCards.swift:360` (`DSAutonomyPresetBar`) — active label `.foregroundStyle(.white)` → `t.accentFg`.

**Meaningful drift count: 14** (7 mono-text + 6 hardcoded-color + the `ManualPortSheet` lacking token env). By module: KeysFeature 2, FilesFeature 5, DiffFeature 1, PreviewFeature 2, SettingsFeature 1, DesignSystem 2.

### Acceptable (low priority) — SF-Symbol sizing via `.system(size:)`
Sizing `Image(systemName:)` with `.font(.system(size:))` is idiomatic for SF Symbols; ideally routed through `DSIconView` for consistency but not a correctness issue:
`SettingsView.swift:456,702,710,726`; `SyncStatusView.swift:25,61,106,139`; `ShortcutBarEditor.swift:34,74`; `DSOfflineState.swift:25,50`; `DSScreenHeader.swift:100`; `InboxCards.swift:137`; `DSButton.swift:76,83`; `DSChip.swift:77`.

### Documented exceptions (NOT drift)
- `Tokens.swift` `Color(.sRGB …)` definitions, the `spectrumColors` device signature, and the always-dark `DI` palette (`AgentStatusHeader`, `PersistentStatusBar`) are the canonical token sources / documented always-dark surfaces.
- Brand/state colors in `Primitives.swift` (agent-kind), `PixelBox.swift`, `DotMatrixView.swift`, `TerminalTheme` presets (`AnsiSGRParser`) are intentional non-token palettes.
- Scrim/overlay `Color.black.opacity(...)` / `.white.opacity(...)` in `DSSlowOverlay`, `BottomDrawer`, `Composites` are conventional dimming layers.

---

## Light/Dark correctness

All scoped feature views consume `@Environment(\.conduitTokens)` and apply via `.conduitTokens()` upstream, so they flip with scheme. The hardcoded `.green/.orange/.red/.blue/.white` literals above are the only scheme-blind spots in the feature surfaces; each has a scheme-adaptive token equivalent. Terminal/HUD/island stay always-dark by design.

## Fixed-geometry list-row invariant

No violations in scope. Inbox approvals are **card** layouts (`InboxCards.swift`), not the fixed-trailing-slot row pattern, so the badge-slot invariant doesn't apply. `AgentStatusHeader`'s conditional approval-count badge sits behind a `Spacer(minLength:)` before an always-present chevron, so toggling it doesn't shift the leading host/status text. The canonical `ReviewSessionRow` fixed-width-`ZStack` pattern lives in `DebugGalleryView` (out of scope) and is not re-implemented incorrectly here.
