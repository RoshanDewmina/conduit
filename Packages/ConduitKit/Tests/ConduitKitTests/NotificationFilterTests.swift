import XCTest
@testable import NotificationsKit
import ConduitCore

final class NotificationFilterTests: XCTestCase {

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
        // start == end is defined as "all day quiet" — deterministic regardless of current hour.
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
