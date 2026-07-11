import Testing
import Foundation
@testable import AppFeature

/// Lane D — pure AttentionReason priority ordering for the workspace thread list.
/// OS-agnostic; runs on macOS host `swift test`.
@Suite("CursorThreadOrderingTests")
struct CursorThreadOrderingTests {

    private struct Row: Sendable, Identifiable {
        let id: String
        let updatedAt: Date?
        let state: CursorThreadAttention.ThreadState
    }

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Priority ladder

    @Test("orders approval > question > failed > auth/credits > receiptReady > working > rest")
    func fullPriorityLadder() {
        // Deliberately reverse chronological updatedAt so priority alone must win.
        let rows: [Row] = [
            Row(id: "idle", updatedAt: base.addingTimeInterval(700), state: .init(conversationStatus: .archived)),
            Row(id: "ready", updatedAt: base.addingTimeInterval(600), state: .init(conversationStatus: .completed)),
            Row(id: "working", updatedAt: base.addingTimeInterval(500), state: .init(conversationStatus: .active)),
            Row(id: "receiptReady", updatedAt: base.addingTimeInterval(400), state: .init(
                conversationStatus: .completed,
                hasUnacknowledgedReceipt: true
            )),
            Row(id: "outOfCredits", updatedAt: base.addingTimeInterval(300), state: .init(
                statusText: "out_of_credits: quota exceeded"
            )),
            Row(id: "runFailed", updatedAt: base.addingTimeInterval(200), state: .init(
                conversationStatus: .failed
            )),
            Row(id: "blockingQuestion", updatedAt: base.addingTimeInterval(100), state: .init(
                hasBlockingQuestion: true
            )),
            Row(id: "pendingApproval", updatedAt: base, state: .init(hasPendingApproval: true)),
        ]

        let sorted = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state)

        #expect(sorted.map(\.id) == [
            "pendingApproval",
            "blockingQuestion",
            "runFailed",
            "outOfCredits",
            "receiptReady",
            "working",
            "ready",
            "idle",
        ])
    }

    @Test("auth/credits provider failures share one tier below runFailed")
    func providerFailuresShareAuthCreditsTier() {
        let rows: [Row] = [
            Row(id: "providerAuth", updatedAt: base.addingTimeInterval(10), state: .init(
                statusText: "provider_auth expired"
            )),
            Row(id: "outOfCredits", updatedAt: base.addingTimeInterval(30), state: .init(
                statusText: "out of credits"
            )),
            Row(id: "modelUnavailable", updatedAt: base.addingTimeInterval(20), state: .init(
                statusText: "model_unavailable"
            )),
            Row(id: "providerError", updatedAt: base, state: .init(
                statusText: "provider_error: 502"
            )),
            Row(id: "runFailed", updatedAt: base.addingTimeInterval(5), state: .init(
                conversationStatus: .failed
            )),
        ]

        let sorted = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state)

        #expect(sorted.first?.id == "runFailed")
        #expect(sorted.dropFirst().map(\.id) == [
            "outOfCredits",
            "modelUnavailable",
            "providerAuth",
            "providerError",
        ])

        for row in sorted.dropFirst() {
            let derived = CursorThreadAttention.derive(row.state)
            #expect(CursorThreadAttention.sortPriority(attention: derived.0, reason: derived.1) == 500)
        }
    }

    // MARK: - Tie-break

    @Test("same priority ties break by most-recent updatedAt")
    func samePriorityRecencyDescending() {
        let rows: [Row] = [
            Row(id: "oldest", updatedAt: base, state: .init(hasPendingApproval: true)),
            Row(id: "middle", updatedAt: base.addingTimeInterval(60), state: .init(hasPendingApproval: true)),
            Row(id: "newest", updatedAt: base.addingTimeInterval(120), state: .init(hasPendingApproval: true)),
        ]

        let sorted = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state)
        #expect(sorted.map(\.id) == ["newest", "middle", "oldest"])
    }

    @Test("nil updatedAt sorts as oldest within a priority tier")
    func nilUpdatedAtIsOldest() {
        let rows: [Row] = [
            Row(id: "nilDate", updatedAt: nil, state: .init(conversationStatus: .active)),
            Row(id: "hasDate", updatedAt: base, state: .init(conversationStatus: .active)),
        ]

        let sorted = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state)
        #expect(sorted.map(\.id) == ["hasDate", "nilDate"])
    }

    @Test("working beats ready/idle; ready beats idle; all below receiptReady")
    func restByAttentionThenRecency() {
        let rows: [Row] = [
            Row(id: "idle-new", updatedAt: base.addingTimeInterval(300), state: .init(conversationStatus: .archived)),
            Row(id: "ready-old", updatedAt: base, state: .init(conversationStatus: .completed)),
            Row(id: "working", updatedAt: base.addingTimeInterval(50), state: .init(conversationStatus: .active)),
            Row(id: "receipt", updatedAt: base.addingTimeInterval(10), state: .init(
                conversationStatus: .completed,
                hasUnacknowledgedReceipt: true
            )),
        ]

        let sorted = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state)
        #expect(sorted.map(\.id) == ["receipt", "working", "ready-old", "idle-new"])
    }

    // MARK: - Sort key + purity

    @Test("ThreadAttentionSortKey Comparable is ascending (sortThreads reverses for display)")
    func sortKeyAscendingComparable() {
        let low = ThreadAttentionSortKey(priority: 300, updatedAt: base)
        let high = ThreadAttentionSortKey(priority: 800, updatedAt: base.addingTimeInterval(-100))
        #expect(low < high)
        #expect(!(high < low))
    }

    @Test("empty input returns empty output")
    func emptyInput() {
        let sorted = sortThreadsByAttention(
            [Row](),
            updatedAt: \.updatedAt,
            threadState: \.state
        )
        #expect(sorted.isEmpty)
    }

    @Test("sort is pure — same input yields same order twice")
    func pureDeterministic() {
        let rows: [Row] = [
            Row(id: "b", updatedAt: base, state: .init(hasBlockingQuestion: true)),
            Row(id: "a", updatedAt: base.addingTimeInterval(1), state: .init(hasPendingApproval: true)),
            Row(id: "c", updatedAt: base.addingTimeInterval(2), state: .init(conversationStatus: .active)),
        ]
        let first = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state).map(\.id)
        let second = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state).map(\.id)
        #expect(first == second)
        #expect(first == ["a", "b", "c"])
    }
}
