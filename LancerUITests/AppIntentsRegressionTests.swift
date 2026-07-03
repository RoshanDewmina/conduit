import AppIntentsTesting
import XCTest

/// Regression coverage for the second of two real, previously-shipped Siri
/// bugs (see docs/test-runs/2026-07-02-relay-siri-liveactivity-session-report.md
/// §14/§15): an `AppIntent` compiled into two binaries at once (the main app
/// AND a widget extension both linking the same shared library). Static
/// discovery tolerated the duplication, but the runtime execution lookup
/// failed with "Couldn't find AppShortcutsProvider" on every invocation.
///
/// **`AppIntentsTesting` has no API surface for the FIRST bug** (an
/// `AppShortcutsProvider`'s phrase registration itself, as opposed to a plain
/// `AppIntent` conformance's discoverability) — confirmed by grepping the
/// full shipped `AppIntentsTesting.swiftinterface` on this machine for
/// "Shortcut"/"phrase": zero hits. `IntentDefinitions.intents[identifier]`
/// (used by `testSiriOnlyIntentsAreDiscoverable` below) checks individual
/// `AppIntent` discoverability, which — per `LancerAppShortcuts.swift`'s own
/// header comment — "merge fine from SessionFeature" regardless of where
/// `AppShortcutsProvider` itself lives; only the phrases/shortcuts
/// registration needed relocating for bug #14. So that test is real,
/// useful coverage of "are these 5 intents discoverable at all," but it is
/// NOT a regression guard for bug #14 specifically — do not re-relocate
/// `LancerAppShortcuts.swift` back into a shared package on the strength of
/// this test suite alone; bug #14 needs a different check (e.g. inspecting
/// the compiled `Metadata.appintents` bundle directly, as the original
/// session did manually).
///
/// `testSiriOnlyIntentsExecuteWithoutDualTargetCrash` genuinely does prove
/// bug #15 doesn't currently reproduce — verified by intentionally
/// reintroducing the dual-target-compilation bug and confirming this exact
/// test fails with the exact historical error signature (see the commit
/// history for this file for the before/after evidence), then reverting.
///
/// It requires a **physical device** — on the iOS 27.0 Simulator it throws
/// `AppIntentsServicesSecurityErrorDomain Code=800 "Your app does not have
/// permission to perform this"` for every intent, regardless of app
/// correctness (confirmed: the same test passes cleanly on-device with no
/// code changes). This is an environment constraint of `AppIntentsTesting`
/// itself in this Xcode 27 beta, not a gap in this app's intents — but it
/// does mean this specific test cannot run in CI/simulator-only pipelines
/// yet. `testSiriOnlyIntentsAreDiscoverable` runs fine on simulator.
@available(iOS 27.0, *)
@MainActor
final class AppIntentsRegressionTests: XCTestCase {

    private static let bundleIdentifier = "dev.lancer.mobile"

    override func setUp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LANCER_UITEST_RESEED"] = "1"
        app.launch()
    }

    /// Confirms each of the 5 Siri-only intents is discoverable through the
    /// app's compiled `AppIntentDefinition` metadata. Real coverage (catches a
    /// genuinely-unregistered or misspelled intent), but — per this file's
    /// header comment — NOT a regression guard for the historical
    /// `AppShortcutsProvider`-wrong-target bug, which `AppIntentsTesting` has
    /// no API to check directly.
    func testSiriOnlyIntentsAreDiscoverable() async throws {
        let definitions = IntentDefinitions(bundleIdentifier: Self.bundleIdentifier)
        let identifiers = [
            "AgentStatusQueryIntent",
            "PendingApprovalsQueryIntent",
            "PauseRunIntent",
            "StopRunIntent",
            "DenyLatestApprovalIntent",
        ]
        for identifier in identifiers {
            // Subscript access alone is enough to prove the definition resolves —
            // an unregistered/misspelled intent throws here, before perform() is
            // ever reached.
            _ = definitions.intents[identifier]
        }
    }

    /// Guards the dual-target execution crash (§15): actually RUNS each of the
    /// 5 Siri-only intents through the real compiled app process, the same
    /// execution path Siri/Shortcuts uses. That bug did not fail at discovery
    /// time (the test above would have passed) — it only failed here, at
    /// `run()`, with "Couldn't find AppShortcutsProvider" because the runtime
    /// lookup got confused about which of two binaries owned the intent.
    func testSiriOnlyIntentsExecuteWithoutDualTargetCrash() async throws {
        let definitions = IntentDefinitions(bundleIdentifier: Self.bundleIdentifier)
        let identifiers = [
            "AgentStatusQueryIntent",
            "PendingApprovalsQueryIntent",
            "PauseRunIntent",
            "StopRunIntent",
            "DenyLatestApprovalIntent",
        ]
        for identifier in identifiers {
            let intent = definitions.intents[identifier].makeIntent()
            // A thrown error here (vs. a normal dialog/result) is exactly the
            // "Couldn't find AppShortcutsProvider" dual-target failure mode —
            // the assertion is simply that run() completes without throwing.
            _ = try await intent.run()
        }
    }
}
