import XCTest

/// Compile-time policy checks for Siri shortcut registration (no AppIntentsTesting required).
final class LancerShortcutsPolicyTests: XCTestCase {
    func testLancerAppShortcutsSourceExcludesApproveIntent() throws {
        #if targetEnvironment(simulator)
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Lancer/LancerAppShortcuts.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("intent: ApprovalActionIntent()"))
        let shortcutCount = source.components(separatedBy: "AppShortcut(").count - 1
        XCTAssertEqual(shortcutCount, 10, "App Shortcuts cap is 10")
        XCTAssertTrue(source.contains("intent: StartAgentRunIntent()"))
        XCTAssertFalse(source.contains("intent: DenyLatestApprovalIntent()"))
        #else
        throw XCTSkip("Source-policy check requires the host filesystem; run on simulator/host lanes, not physical device.")
        #endif
    }

    func testExecutionTargetsPinSensitiveIntents() throws {
        #if targetEnvironment(simulator)
        let policyURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Lancer/IntentExecutionPolicy.swift")
        let policy = try String(contentsOf: policyURL, encoding: .utf8)
        XCTAssertTrue(policy.contains("extension StartAgentRunIntent"))
        XCTAssertTrue(policy.contains("static var allowedExecutionTargets: IntentExecutionTargets { .main }"))
        XCTAssertTrue(policy.contains("extension ApprovalActionIntent"))
        XCTAssertTrue(policy.contains(".widgetKitExtension"))
        #else
        throw XCTSkip("Source-policy check requires the host filesystem.")
        #endif
    }
}
