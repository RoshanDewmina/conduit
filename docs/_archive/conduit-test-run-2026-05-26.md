# Conduit Test Run - 2026-05-26

## Environment

- Repo: `/Users/roshansilva/Documents/command-center`
- Primary simulator: iPhone 17 Pro, iOS 26.4, `8D60CE4E-E396-43D5-907D-45A53C2F790E`
- Secondary simulator: iPad Pro 13-inch (M5), iOS 26.4, `DEF71AF9-2BBA-4D18-B6C7-1A053B8EEAD7`
- Fresh-install onboarding simulator: iPhone 17e, iOS 26.4, `F308345C-CAEA-4A05-8577-BACAE3854C1A`
- Remote SSH smoke host: `roshansilva@35.201.3.231`

## Automated Result

- Command path: `xcodebuild test -project Conduit.xcodeproj -scheme ConduitKitTests -destination 'platform=iOS Simulator,id=8D60CE4E-E396-43D5-907D-45A53C2F790E' -configuration Debug`
- Result: 97 passed, 0 failed, 0 skipped
- Final xcresult: `/tmp/conduit-final-tests-project-setting.xcresult`
- Final log: `/tmp/conduit-final-tests-project-setting.log`
- Warnings/errors: none found by `rg -n "warning:|error:" /tmp/conduit-final-tests-project-setting.log`

## Manual Simulator Coverage

- Launch/onboarding: fresh install showed onboarding; "Add your first host" opened `HostEditorView`; "Set up a workspace for me" opened `ProvisioningWizard`, provider selection worked, and the workspace-name step rendered.
- Workspaces: add, edit, delete, persistence, and host status surface were exercised. Tap-to-edit was added through a leading swipe action.
- SSH/TOFU: Ed25519 key connect to GCP host succeeded; first trust showed fingerprint; repeat connect skipped TOFU.
- Terminal block mode: command execution, failing command, context menu copy command, rerun-to-composer, block collapse, and persistence were exercised.
- Raw PTY/keyboard rail: manual raw mode rendered; typed bytes reached the shell; symbol insertion worked; sticky Ctrl sent Ctrl-C and reset.
- Composer/snippets: snippet palette opens, search filters, insertion fills composer, Settings snippet add/edit/delete persists through GRDB.
- AI no-key path: `# list files` now shows "No AI provider configured. Add an API key in Settings." and preserves the request in the composer.
- Inbox: seeded approval cards showed correct risk badges; Allow once and Reject updated UI and persisted decisions.
- Files/SFTP: home directory loaded over the real SSH session; directory navigation and `.bashrc` text preview worked; SFTP EOF fallback was fixed.
- Diff: empty-state "No patch pending" rendered.
- Preview: empty state, remote port detection for `8080`, SSH-proxied WKWebView load, reload/menu controls, viewport selection, and manual closed-port error were exercised.
- Settings: default provider persistence, Save alert, sync status, Billing view, Snippets, and SSH Keys were exercised.
- Billing: view renders; StoreKit config is now present in the Xcode run scheme; MCP/simctl launch still cannot exercise the purchase sheet, so product-load failure is shown clearly.
- iPad: build and launch succeeded; hierarchy showed `NavigationSplitView` with sidebar and content pane.
- Appearance: dark mode plus Accessibility Extra Large rendered on Workspaces without crash or obvious overlap; simulators were reset to light/large after the check.

## Fixes Applied During The Run

- Wired host editing and immediate workspace refresh after add/edit/delete.
- Changed block context-menu rerun to populate the composer instead of auto-submitting.
- Fixed raw terminal byte forwarding and sticky Ctrl behavior.
- Added robust SFTP listing fallback for Citadel EOF/status behavior and started Files at the session cwd.
- Fixed preview port label formatting and forced reload when manual port changes.
- Replaced sample-only global inbox wiring with repository-backed live inbox wiring and fixed approval risk decoding.
- Persisted the default AI provider and made session AI client selection honor it.
- Added visible no-key/error feedback for natural-language command translation.
- Wired Settings snippets to the real `SnippetRepository`.
- Derived SSH key fingerprints/public keys for all stored keys and added a persistent copy action.
- Added StoreKit config to `project.yml` for the Conduit run scheme and made missing product state explicit.
- Disabled App Intents metadata extraction because the app does not define App Intents, removing the Xcode metadata warning from app/test builds.
- Guarded CloudKit access when the entitlement/container is not active.
- Cleaned test warnings in unit tests and kept the suite at 97 tests.

## Not Fully Verified

- Face ID success/failure prompt: simulator had no enrolled biometrics, so only the no-biometric bypass path was verified.
- Password-auth SSH: not exercised with a real password credential.
- Valid Anthropic/OpenAI streaming calls: no real API keys were configured; no-key/error paths were verified.
- StoreKit purchase sheet: Xcode run-scheme config is fixed, but XcodeBuildMCP launches via `simctl`, which does not attach the StoreKit config.
- Daemon/APNs end-to-end: requires the live conduitd hook setup and external notification delivery path.
- CloudKit sync: account/container activation remains external-account dependent.
- Performance Instruments targets: not run in Time Profiler/Memory instruments in this pass.

## Cleanup

- Removed temporary seeded approval rows and codex test snippets from the primary simulator database.
- Stopped the temporary remote `python3 -m http.server 8080`.
- Removed the app-generated Ed25519 public key from the GCP host's `authorized_keys`.
- Shut down the disposable iPhone 17e and iPad simulators; the primary iPhone 17 Pro simulator remains booted with the final app build running.
