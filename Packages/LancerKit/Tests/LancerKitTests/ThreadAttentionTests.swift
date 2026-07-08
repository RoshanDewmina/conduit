import Testing
import Foundation
@testable import AppFeature

@Suite("ThreadAttentionTests — reason priority")
struct ThreadAttentionTestsReasonPriority {

    struct DeriveCase: Sendable {
        let name: String
        let state: CursorThreadAttention.ThreadState
        let expectedAttention: CursorThreadAttention
        let expectedReason: AttentionReason
    }

    private static let deriveCases: [DeriveCase] = [
        DeriveCase(
            name: "pendingApproval",
            state: CursorThreadAttention.ThreadState(hasPendingApproval: true),
            expectedAttention: .needsApproval,
            expectedReason: .pendingApproval
        ),
        DeriveCase(
            name: "blockingQuestion",
            state: CursorThreadAttention.ThreadState(
                hasBlockingQuestion: true,
                statusText: "Which auth flow should I use?"
            ),
            expectedAttention: .awaitingInput,
            expectedReason: .blockingQuestion
        ),
        DeriveCase(
            name: "runFailed",
            state: CursorThreadAttention.ThreadState(
                conversationStatus: .failed,
                errorDetail: "exit code 1"
            ),
            expectedAttention: .failed,
            expectedReason: .runFailed
        ),
        DeriveCase(
            name: "providerAuth",
            state: CursorThreadAttention.ThreadState(
                statusText: "provider_auth: re-login required"
            ),
            expectedAttention: .failed,
            expectedReason: .providerAuth
        ),
        DeriveCase(
            name: "outOfCredits",
            state: CursorThreadAttention.ThreadState(
                statusText: "out_of_credits: quota exceeded"
            ),
            expectedAttention: .failed,
            expectedReason: .outOfCredits
        ),
        DeriveCase(
            name: "modelUnavailable",
            state: CursorThreadAttention.ThreadState(
                statusText: "model_unavailable for sonnet"
            ),
            expectedAttention: .failed,
            expectedReason: .modelUnavailable
        ),
        DeriveCase(
            name: "providerError",
            state: CursorThreadAttention.ThreadState(
                statusText: "provider_error: upstream 502"
            ),
            expectedAttention: .failed,
            expectedReason: .providerError
        ),
        DeriveCase(
            name: "receiptReady",
            state: CursorThreadAttention.ThreadState(
                conversationStatus: .completed,
                hasUnacknowledgedReceipt: true,
                statusText: "Proof receipt ready"
            ),
            expectedAttention: .ready,
            expectedReason: .receiptReady
        ),
        DeriveCase(
            name: "working",
            state: CursorThreadAttention.ThreadState(conversationStatus: .active),
            expectedAttention: .working,
            expectedReason: .none
        ),
        DeriveCase(
            name: "ready",
            state: CursorThreadAttention.ThreadState(conversationStatus: .completed),
            expectedAttention: .ready,
            expectedReason: .none
        ),
        DeriveCase(
            name: "idle",
            state: CursorThreadAttention.ThreadState(conversationStatus: .archived),
            expectedAttention: .idle,
            expectedReason: .none
        ),
    ]

    @Test("derive maps each reason to the expected attention + reason", arguments: deriveCases)
    func deriveMapsReason(case deriveCase: DeriveCase) {
        let (attention, reason, _) = CursorThreadAttention.derive(deriveCase.state)
        #expect(attention == deriveCase.expectedAttention, "case: \(deriveCase.name)")
        #expect(reason == deriveCase.expectedReason, "case: \(deriveCase.name)")
    }

    @Test("priority ordering matches spec tier", arguments: deriveCases)
    func priorityMatchesSpec(case deriveCase: DeriveCase) {
        let derived = CursorThreadAttention.derive(deriveCase.state)
        let priority = CursorThreadAttention.sortPriority(
            attention: derived.0,
            reason: derived.1
        )
        let expected: Int = switch deriveCase.name {
        case "pendingApproval": 800
        case "blockingQuestion": 700
        case "runFailed": 600
        case "providerAuth", "outOfCredits", "modelUnavailable", "providerError": 500
        case "receiptReady": 400
        case "working": 300
        case "ready": 200
        case "idle": 100
        default: -1
        }
        #expect(priority == expected, "case: \(deriveCase.name)")
    }

    @Test("pendingApproval beats blockingQuestion and runFailed")
    func pendingApprovalWinsTies() {
        let state = CursorThreadAttention.ThreadState(
            hasPendingApproval: true,
            hasBlockingQuestion: true,
            conversationStatus: .failed
        )
        let (_, reason, _) = CursorThreadAttention.derive(state)
        #expect(reason == .pendingApproval)
    }

    @Test("detail is capped at 180 characters")
    func detailCap() {
        let long = String(repeating: "x", count: 250)
        let state = CursorThreadAttention.ThreadState(
            conversationStatus: .failed,
            errorDetail: long
        )
        let (_, _, detail) = CursorThreadAttention.derive(state)
        #expect(detail?.count == 180)
    }
}

@Suite("ThreadAttentionTests — sort")
struct ThreadAttentionTestsSort {

    private struct Fixture: Sendable {
        let id: String
        let updatedAt: Date
        let state: CursorThreadAttention.ThreadState
    }

    @Test("mixed fixture sorts needs-you-first by priority then updatedAt")
    func mixedFixtureSortOrder() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fixtures: [Fixture] = [
            Fixture(id: "idle", updatedAt: base.addingTimeInterval(80), state: .init(conversationStatus: .archived)),
            Fixture(id: "ready", updatedAt: base.addingTimeInterval(70), state: .init(conversationStatus: .completed)),
            Fixture(id: "working", updatedAt: base.addingTimeInterval(60), state: .init(conversationStatus: .active)),
            Fixture(id: "receiptReady", updatedAt: base.addingTimeInterval(50), state: .init(
                conversationStatus: .completed,
                hasUnacknowledgedReceipt: true
            )),
            Fixture(id: "providerAuth", updatedAt: base.addingTimeInterval(40), state: .init(
                statusText: "provider_auth expired"
            )),
            Fixture(id: "runFailed", updatedAt: base.addingTimeInterval(30), state: .init(
                conversationStatus: .failed
            )),
            Fixture(id: "blockingQuestion", updatedAt: base.addingTimeInterval(20), state: .init(
                hasBlockingQuestion: true
            )),
            Fixture(id: "pendingApproval", updatedAt: base.addingTimeInterval(10), state: .init(
                hasPendingApproval: true
            )),
        ]

        let sorted = sortThreadsByAttention(
            fixtures,
            updatedAt: \.updatedAt,
            threadState: \.state
        )

        #expect(sorted.map(\.id) == [
            "pendingApproval",
            "blockingQuestion",
            "runFailed",
            "providerAuth",
            "receiptReady",
            "working",
            "ready",
            "idle",
        ])
    }

    @Test("same priority tie-breaks by updatedAt descending")
    func samePriorityUpdatedAtDescending() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fixtures: [Fixture] = [
            Fixture(id: "older", updatedAt: base, state: .init(conversationStatus: .active)),
            Fixture(id: "newer", updatedAt: base.addingTimeInterval(120), state: .init(conversationStatus: .active)),
        ]

        let sorted = sortThreadsByAttention(
            fixtures,
            updatedAt: \.updatedAt,
            threadState: \.state
        )

        #expect(sorted.map(\.id) == ["newer", "older"])
    }
}

@Suite("ThreadAttentionTests — home layout")
struct ThreadAttentionTestsHomeLayout {

    @Test("all clear only when relay healthy and needs-you count is zero")
    func allClearWhenHealthyAndEmpty() {
        let message = homeAttentionStatusMessage(
            needsYouCount: 0,
            relayHealthy: true,
            lastSnapshotAt: Date(),
            now: Date(),
            relativeTime: { _, _ in "2 min. ago" }
        )
        #expect(message == "All clear — nothing needs you")
    }

    @Test("stale relay never shows all clear")
    func staleRelayNeverAllClear() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = now.addingTimeInterval(-120)
        let message = homeAttentionStatusMessage(
            needsYouCount: 0,
            relayHealthy: false,
            lastSnapshotAt: snapshot,
            now: now,
            relativeTime: { _, _ in "2 min. ago" }
        )
        #expect(message == "As of 2 min. ago — reconnecting")
        #expect(message?.contains("All clear") == false)
    }

    @Test("stale relay with pending items still shows reconnecting status")
    func staleWithNeedsYou() {
        let message = homeAttentionStatusMessage(
            needsYouCount: 2,
            relayHealthy: false,
            lastSnapshotAt: Date(),
            now: Date(),
            relativeTime: { _, _ in "1 min. ago" }
        )
        #expect(message == "As of 1 min. ago — reconnecting")
    }

    @Test("healthy relay with needs-you items has no status banner")
    func noBannerWhenNeedsYouPresent() {
        let message = homeAttentionStatusMessage(
            needsYouCount: 1,
            relayHealthy: true,
            lastSnapshotAt: Date()
        )
        #expect(message == nil)
    }

    @Test("isNeedsYouThread matches positive reason priority")
    func needsYouDetection() {
        #expect(isNeedsYouThread(.init(hasPendingApproval: true)))
        #expect(!isNeedsYouThread(.init(conversationStatus: .active)))
        #expect(!isNeedsYouThread(.init(conversationStatus: .completed)))
    }

    @Test("needs-you rows sort ahead of working rows in home fixture")
    func needsYouRowsSortFirst() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        struct Row: Sendable { let id: String; let updatedAt: Date; let state: CursorThreadAttention.ThreadState }
        let rows: [Row] = [
            Row(id: "working", updatedAt: base.addingTimeInterval(100), state: .init(conversationStatus: .active)),
            Row(id: "approval", updatedAt: base, state: .init(hasPendingApproval: true)),
        ]
        let sorted = sortThreadsByAttention(rows, updatedAt: \.updatedAt, threadState: \.state)
        #expect(sorted.first?.id == "approval")
        let needsYou = sorted.filter { isNeedsYouThread($0.state) }
        #expect(needsYou.map(\.id) == ["approval"])
    }
}
