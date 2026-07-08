import Foundation
import Testing
@testable import LancerCore
@testable import SessionFeature

@Suite struct ReceiptCardModelTests {
    private let fixturePayload = """
    {"schema":"lancer.proof/v0","runId":"r-card","conversationId":"c-card","agent":"claude","status":"completed","exitCode":0,"startedAt":"2026-07-07T01:00:00Z","endedAt":"2026-07-07T01:05:00Z","contract":{"goal":"Ship receipt card","doneCriteria":["Card renders","Accept persists"],"validationCommands":["swift test --filter ReceiptCardModelTests"]},"commands":[{"command":"swift test --filter ReceiptCardModelTests","exitCode":0}],"filesTouched":[{"path":"ReceiptCardView.swift","additions":10,"deletions":1}],"tests":{"ran":true,"passed":3,"failed":0},"criteria":[{"text":"Card renders","status":"met"},{"text":"Accept persists","status":"unknown"}],"confidence":{"commands":"complete","files":"complete","tests":"bestEffort"},"resume":{"agent":"claude","vendorSessionId":"sess-card-test"}}
    """

    private var fixtureArtifact: ChatArtifact {
        ChatArtifact(
            id: "receipt:r-card",
            conversationID: "c-card",
            turnID: "t-card",
            runID: "r-card",
            kind: .receipt,
            title: "Run proof",
            payloadJSON: fixturePayload,
            status: .done
        )
    }

    @Test("decodeReceipt parses receipt artifacts")
    func decodeReceipt() throws {
        let receipt = try #require(ReceiptCardModel.decodeReceipt(from: fixtureArtifact))
        #expect(receipt.runId == "r-card")
        #expect(receipt.contract?.goal == "Ship receipt card")
    }

    @Test("mergeAcceptedAt adds acceptedAt to payload JSON")
    func mergeAcceptedAt() throws {
        let merged = try #require(ReceiptCardModel.mergeAcceptedAt(into: fixturePayload))
        #expect(ReceiptCardModel.isAccepted(payloadJSON: merged))
        #expect(ReceiptCardModel.isAccepted(payloadJSON: fixturePayload) == false)
        let receipt = try #require(ReceiptCardModel.decodeReceipt(from: ChatArtifact(
            conversationID: "c-card",
            turnID: "t-card",
            runID: "r-card",
            kind: .receipt,
            title: "Run proof",
            payloadJSON: merged,
            status: .done
        )))
        #expect(receipt.runId == "r-card")
    }

    @Test("durationText formats run duration")
    func durationText() {
        let text = ReceiptCardModel.durationText(
            startedAt: "2026-07-07T01:00:00Z",
            endedAt: "2026-07-07T01:05:00Z"
        )
        #expect(text == "5m 0s")
    }

    @Test("criteriaRows prefers explicit criteria over contract fallback")
    func criteriaRows() throws {
        let receipt = try #require(ReceiptCardModel.decodeReceipt(from: fixtureArtifact))
        let rows = ReceiptCardModel.criteriaRows(receipt: receipt)
        #expect(rows.count == 2)
        #expect(rows.first?.status == .met)
        #expect(rows.last?.status == .unknown)
    }

    @Test("anotherPassPrefill mentions unmet criteria")
    func anotherPassPrefill() throws {
        let receipt = try #require(ReceiptCardModel.decodeReceipt(from: fixtureArtifact))
        let prefill = ReceiptCardModel.anotherPassPrefill(receipt: receipt)
        #expect(prefill.contains("Ship receipt card") || prefill.contains("another pass"))
    }

    @Test("resumeShellCommand builds claude resume command")
    func resumeShellCommand() throws {
        let receipt = try #require(ReceiptCardModel.decodeReceipt(from: fixtureArtifact))
        let command = try #require(ReceiptCardModel.resumeShellCommand(
            receipt: receipt,
            workingDirectory: "/tmp/project"
        ))
        #expect(command.contains("sess-card-test"))
        #expect(command.contains("/tmp/project"))
    }

    @Test("confidenceCaption maps known values")
    func confidenceCaption() {
        #expect(ReceiptCardModel.confidenceCaption("complete") == "Complete capture")
        #expect(ReceiptCardModel.confidenceCaption("bestEffort") == "Best-effort capture")
    }
}
