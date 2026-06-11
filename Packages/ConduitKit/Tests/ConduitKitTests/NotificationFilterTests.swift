import Testing
import XCTest
@testable import NotificationsKit
@testable import ConduitCore

@Suite struct NotificationFilterTests {
    @Test("minRisk gates low-risk approvals")
    func minRisk() {
        var f = NotificationFilter()
        f.minRisk = .high
        #expect(f.shouldDeliver(risk: .low, agent: .claudeCode) == false)
        #expect(f.shouldDeliver(risk: .high, agent: .claudeCode) == true)
        #expect(f.shouldDeliver(risk: .critical, agent: .codex) == true)
    }

    @Test("enabledAgents whitelist excludes others")
    func agents() {
        var f = NotificationFilter()
        f.enabledAgents = ["claudeCode"]
        #expect(f.shouldDeliver(risk: .high, agent: .claudeCode) == true)
        #expect(f.shouldDeliver(risk: .high, agent: .codex) == false)
    }
}

final class NotificationFilterXCTests: XCTestCase {

    func testDefaultFilterAllowsAll() {
        let filter = NotificationFilter()
        XCTAssertTrue(filter.shouldDeliver(risk: .low, agent: .claudeCode))
        XCTAssertTrue(filter.shouldDeliver(risk: .critical, agent: .codex))
    }

    func testMinRiskFiltersLow() {
        var filter = NotificationFilter()
        filter.minRisk = .medium
        XCTAssertFalse(filter.shouldDeliver(risk: .low, agent: .claudeCode))
        XCTAssertTrue(filter.shouldDeliver(risk: .medium, agent: .claudeCode))
        XCTAssertTrue(filter.shouldDeliver(risk: .high, agent: .claudeCode))
    }

    func testAgentFilterBlocksUnlisted() {
        var filter = NotificationFilter()
        filter.enabledAgents = ["claudeCode"]
        XCTAssertTrue(filter.shouldDeliver(risk: .low, agent: .claudeCode))
        XCTAssertFalse(filter.shouldDeliver(risk: .low, agent: .codex))
    }

    func testAgentFilterNilAllowsAll() {
        var filter = NotificationFilter()
        filter.enabledAgents = nil
        XCTAssertTrue(filter.shouldDeliver(risk: .low, agent: .codex))
    }

    func testQuietHoursBlocksDelivery() {
        var filter = NotificationFilter()
        filter.quietHoursEnabled = true
        filter.quietHoursStart = 0
        filter.quietHoursEnd = 0
        XCTAssertFalse(filter.shouldDeliver(risk: .critical, agent: .claudeCode))
    }

    func testQuietHoursDisabledAllows() {
        var filter = NotificationFilter()
        filter.quietHoursEnabled = false
        XCTAssertTrue(filter.shouldDeliver(risk: .low, agent: .claudeCode))
    }
}
