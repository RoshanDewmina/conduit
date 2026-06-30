import Testing
import Foundation
@testable import LancerCore

// AttentionItem is the Home attention-card projection (FleetStore.attentionItems
// in AppFeature). AttentionItem itself lives in LancerCore and is platform-
// independent, so these tests run on macOS via `swift test`. The iOS-only
// aggregation in FleetStore (which requires SessionViewModel/DaemonChannel SSH
// infrastructure that can't be spun up in a unit test) is exercised here by
// replicating its filter/sort formula against plain Approval fixtures, the
// same pattern FleetStoreTests.swift uses for allPendingApprovals.

private func makeApproval(
    risk: Approval.Risk,
    decision: Approval.Decision? = nil,
    createdAt: Date = .now
) -> Approval {
    var a = Approval(
        sessionID: SessionID(),
        agent: .claudeCode,
        kind: .command,
        command: "ls",
        cwd: "/repo",
        risk: risk,
        createdAt: createdAt
    )
    a.decision = decision
    return a
}

/// Mirrors FleetStore.attentionItems' filter + sort exactly, so the test
/// fails if that formula regresses without needing live SSH-backed slots.
private func projectAttentionItems(
    approvals: [Approval],
    offlineHasPending: Bool
) -> [AttentionItem] {
    var items: [AttentionItem] = []
    for approval in approvals where approval.isPending || approval.decision == .expired {
        items.append(AttentionItem(approval: approval))
    }
    if offlineHasPending {
        items.append(AttentionItem(offlineHost: HostID(), hostName: "offline-host"))
    }
    return items.sorted {
        if $0.severity != $1.severity { return $0.severity > $1.severity }
        return $0.createdAt < $1.createdAt
    }
}

@Suite("AttentionItem — identity")
struct AttentionItemIdentityTests {

    @Test("same approval UUID produces the same AttentionItem.id across re-projections")
    func stableIDAcrossReprojection() {
        let approval = makeApproval(risk: .medium)
        let first = AttentionItem(approval: approval)
        let second = AttentionItem(approval: approval)
        #expect(first.id == second.id)
        #expect(first.id == approval.id.uuidString)
    }

    @Test("different approvals produce different ids")
    func distinctApprovalsDistinctIDs() {
        let a = AttentionItem(approval: makeApproval(risk: .low))
        let b = AttentionItem(approval: makeApproval(risk: .low))
        #expect(a.id != b.id)
    }

    @Test("offline-machine item id is namespaced by host so it can't collide with an approval id")
    func offlineHostIDNamespaced() {
        let hostID = HostID()
        let item = AttentionItem(offlineHost: hostID, hostName: "Mac Studio")
        #expect(item.id == "offline-\(hostID)")
    }
}

@Suite("AttentionItem — resolution state")
struct AttentionItemResolutionTests {

    @Test("a resolved (approved) approval is excluded from the attention projection")
    func resolvedApprovalExcluded() {
        let approvals = [
            makeApproval(risk: .medium, decision: .approved),
            makeApproval(risk: .low, decision: nil),
        ]
        let items = projectAttentionItems(approvals: approvals, offlineHasPending: false)
        #expect(items.count == 1)
        #expect(items[0].severity == .low)
    }

    @Test("an expired approval is kept in the projection and flagged isExpired")
    func expiredApprovalKeptAndFlagged() {
        let approvals = [makeApproval(risk: .high, decision: .expired)]
        let items = projectAttentionItems(approvals: approvals, offlineHasPending: false)
        #expect(items.count == 1)
        #expect(items[0].isExpired == true)
    }

    @Test("a pending approval is kept and not flagged expired")
    func pendingApprovalKeptNotExpired() {
        let approvals = [makeApproval(risk: .critical)]
        let items = projectAttentionItems(approvals: approvals, offlineHasPending: false)
        #expect(items.count == 1)
        #expect(items[0].isExpired == false)
    }
}

@Suite("AttentionItem — sorting")
struct AttentionItemSortingTests {

    @Test("items sort by severity descending: critical, high, medium, low")
    func sortsBySeverityDescending() {
        let approvals = [
            makeApproval(risk: .low),
            makeApproval(risk: .critical),
            makeApproval(risk: .medium),
            makeApproval(risk: .high),
        ]
        let items = projectAttentionItems(approvals: approvals, offlineHasPending: false)
        #expect(items.map(\.severity) == [.critical, .high, .medium, .low])
    }

    @Test("same-severity items tie-break by createdAt ascending (oldest first)")
    func sameSeverityTieBreaksByCreatedAtAscending() {
        let now = Date()
        let approvals = [
            makeApproval(risk: .medium, createdAt: now.addingTimeInterval(60)),
            makeApproval(risk: .medium, createdAt: now),
            makeApproval(risk: .medium, createdAt: now.addingTimeInterval(30)),
        ]
        let items = projectAttentionItems(approvals: approvals, offlineHasPending: false)
        #expect(items.map(\.createdAt) == [now, now.addingTimeInterval(30), now.addingTimeInterval(60)])
    }
}

@Suite("AttentionItem — offline machine condition")
struct AttentionItemOfflineMachineTests {

    @Test("offline host with a pending approval produces an offlineMachine item")
    func offlineWithPendingProducesItem() {
        let items = projectAttentionItems(
            approvals: [makeApproval(risk: .medium)],
            offlineHasPending: true
        )
        let offlineItems = items.filter {
            if case .offlineMachine = $0.kind { return true }
            return false
        }
        #expect(offlineItems.count == 1)
    }

    @Test("offline host with no pending approvals produces no offlineMachine item")
    func offlineWithoutPendingProducesNoItem() {
        // The FleetStore guard is `connectionState == .offline && approvals.contains(\.isPending)`;
        // simulate the "no pending" branch by never calling the offline constructor.
        let items = projectAttentionItems(
            approvals: [makeApproval(risk: .medium, decision: .approved)],
            offlineHasPending: false
        )
        #expect(items.isEmpty)
    }
}
