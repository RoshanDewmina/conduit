import AppIntentsTesting
import XCTest

/// Runtime App Intents tests (iOS 27 test lane). Does not import app internals —
/// drives metadata from the installed `dev.lancer.mobile` binary via `AppIntentsTesting`.
///
/// Note: `AnyAppIntent.run()` currently fails with
/// `AppIntentsServicesSecurityErrorDomain Code=800` when invoked from a separate
/// test bundle — see `docs/wwdc26-lancer-opportunity-audit/ios27-fast-follow.md`.
@available(iOS 27.0, *)
final class LancerAppIntentsRuntimeTests: XCTestCase {
    private let bundleID = "dev.lancer.mobile"
    private lazy var definitions = IntentDefinitions(bundleIdentifier: bundleID)

    func testIntentCatalogIncludesCoreSiriIntents() throws {
        let required = [
            "AgentStatusQueryIntent",
            "PendingApprovalsQueryIntent",
            "SearchLancerIntent",
            "OpenConversationIntent",
            "OpenMachineIntent",
            "OpenApprovalIntent",
            "PauseRunIntent",
            "StopRunIntent",
            "DenyApprovalIntent",
            "DenyLatestApprovalIntent",
            "StartAgentRunIntent",
        ]
        for name in required {
            let def = definitions.intents[name]
            XCTAssertEqual(def.identifier, name)
            XCTAssertEqual(def.bundleIdentifier, bundleID)
        }
    }

    func testEntityCatalogIncludesCoreTypes() throws {
        let required = [
            "MachineEntity",
            "RunEntity",
            "ApprovalEntity",
            "ConversationEntity",
            "WorkspaceEntity",
        ]
        for name in required {
            let def = definitions.entities[name]
            XCTAssertEqual(def.typeIdentifier, name)
            XCTAssertEqual(def.bundleIdentifier, bundleID)
        }
    }

    func testAgentVendorEnumRegistered() throws {
        let def = definitions.enums["AgentVendorAppEnum"]
        XCTAssertEqual(def.typeIdentifier, "AgentVendorAppEnum")
    }

    func testRuntimeIntentExecutionRequiresHostEntitlement() async throws {
        throw XCTSkip(
            "AppIntentsTesting.run() requires host entitlement (AppIntentsServicesSecurityErrorDomain 800) — configure test-host or entitlements in fast-follow."
        )
    }
}
