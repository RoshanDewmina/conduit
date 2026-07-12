import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite struct ProofReelModelTests {
    private var fixtureReceipt: ProofReceipt {
        ProofReceipt(
            runId: "r-reel",
            conversationId: "c-reel",
            agent: "claude",
            model: "haiku",
            startedAt: "2026-07-08T10:00:00Z",
            endedAt: "2026-07-08T10:12:00Z",
            status: "completed",
            exitCode: 0,
            contract: .init(
                goal: "Ship proof reel",
                doneCriteria: ["Scrubber works"],
                validationCommands: ["swift test --filter ProofReelModelTests"]
            ),
            commands: [
                .init(
                    command: "swift build",
                    exitCode: 0,
                    kind: "build",
                    startedAt: "2026-07-08T10:02:00Z"
                ),
                .init(
                    command: "legacy-no-ts",
                    exitCode: 1,
                    kind: "shell",
                    startedAt: nil
                ),
                .init(
                    command: "swift test --filter ProofReelModelTests",
                    exitCode: 0,
                    kind: "test",
                    startedAt: "2026-07-08T10:08:00Z"
                ),
            ],
            filesTouched: [
                .init(path: "ProofReelView.swift", additions: 180, deletions: 0),
                .init(path: "ReceiptCardView.swift", additions: 12, deletions: 2),
            ],
            tests: .init(ran: true, passed: 5, failed: 0),
            criteria: [
                .init(text: "Scrubber works", status: .met, evidence: "ProofReelModelTests pass"),
                .init(text: "Screenshots captured", status: .unknown),
                .init(text: "Daemon ordering", status: .unmet, evidence: "Lane H2 not built"),
            ],
            git: .init(startRef: "abcdef012345", endRef: "fedcba987654", dirtyAtStart: true)
        )
    }

    @Test("stops orders commands by startedAt then files then criteria")
    func stopOrdering() {
        let stops = ProofReelModel.stops(from: fixtureReceipt)
        #expect(stops.count == 8)

        guard case .command(let first) = stops[0].kind else {
            Issue.record("Expected first stop to be a command")
            return
        }
        #expect(first.command == "swift build")

        guard case .command(let second) = stops[1].kind else {
            Issue.record("Expected second stop to be a command")
            return
        }
        #expect(second.command == "swift test --filter ProofReelModelTests")

        guard case .command(let third) = stops[2].kind else {
            Issue.record("Expected third stop to be an undated command")
            return
        }
        #expect(third.command == "legacy-no-ts")
        #expect(third.exitCode == 1)

        guard case .file(let firstFile) = stops[3].kind else {
            Issue.record("Expected fourth stop to be a file")
            return
        }
        #expect(firstFile.path == "ProofReelView.swift")

        guard case .file(let secondFile) = stops[4].kind else {
            Issue.record("Expected fifth stop to be a file")
            return
        }
        #expect(secondFile.path == "ReceiptCardView.swift")

        guard case .criterion(let met) = stops[5].kind else {
            Issue.record("Expected sixth stop to be a criterion")
            return
        }
        #expect(met.status == .met)

        guard case .criterion(let unknown) = stops[6].kind else {
            Issue.record("Expected seventh stop to be a criterion")
            return
        }
        #expect(unknown.status == .unknown)

        guard case .criterion(let unmet) = stops[7].kind else {
            Issue.record("Expected eighth stop to be a criterion")
            return
        }
        #expect(unmet.status == .unmet)
    }

    @Test("scrubState resolves index and progress at several positions")
    func scrubStateTransitions() {
        let stops = ProofReelModel.stops(from: fixtureReceipt)

        let start = ProofReelModel.scrubState(stops: stops, index: 0)
        #expect(start?.index == 0)
        #expect(start?.stopCount == 8)
        #expect(start?.progress == 0)
        #expect(ProofReelModel.stopLabel(for: start!.stop) == "Command")

        let mid = ProofReelModel.scrubState(stops: stops, index: 3)
        #expect(mid?.index == 3)
        guard case .file(let file) = mid?.stop.kind else {
            Issue.record("Expected mid scrub stop to be a file")
            return
        }
        #expect(file.path == "ProofReelView.swift")
        #expect(mid?.progress == 3.0 / 7.0)

        let criteria = ProofReelModel.scrubState(stops: stops, index: 7)
        #expect(criteria?.index == 7)
        #expect(criteria?.isAtEnd == true)
        #expect(criteria?.progress == 1)
        guard case .criterion(let last) = criteria?.stop.kind else {
            Issue.record("Expected last scrub stop to be a criterion")
            return
        }
        #expect(last.status == .unmet)
    }

    @Test("scrubState clamps out-of-range indices")
    func scrubStateClamping() {
        let stops = ProofReelModel.stops(from: fixtureReceipt)
        #expect(ProofReelModel.scrubState(stops: stops, index: -1) == nil)
        #expect(ProofReelModel.scrubState(stops: stops, index: 99) == nil)
    }

    @Test("scrubState from progress maps to nearest stop")
    func scrubStateFromProgress() {
        let stops = ProofReelModel.stops(from: fixtureReceipt)
        let quarter = ProofReelModel.scrubState(stops: stops, progress: 0.25)
        #expect(quarter?.index == 2)
        guard case .command(let command) = quarter?.stop.kind else {
            Issue.record("Expected quarter-progress stop to be a command")
            return
        }
        #expect(command.command == "legacy-no-ts")

        let end = ProofReelModel.scrubState(stops: stops, progress: 1.0)
        #expect(end?.index == 7)
        #expect(end?.isAtEnd == true)
    }

    @Test("empty receipt yields no stops")
    func emptyReceipt() {
        let receipt = ProofReceipt(
            runId: "r-empty",
            conversationId: "c-empty",
            agent: "claude",
            status: "completed"
        )
        #expect(ProofReelModel.stops(from: receipt).isEmpty)
        #expect(ProofReelModel.scrubState(stops: [], index: 0) == nil)
    }

    @Test("decodeReceipt reads chat_artifacts and chat_events shapes")
    func decodeFromRepositoryShapes() throws {
        let receipt = fixtureReceipt
        let data = try JSONEncoder().encode(receipt)
        let payload = try #require(String(data: data, encoding: .utf8))

        let artifact = ChatArtifact(
            id: "receipt:r-reel",
            conversationID: "c-reel",
            turnID: "t-reel",
            runID: "r-reel",
            kind: .receipt,
            title: "Run proof",
            payloadJSON: payload,
            status: .done
        )
        let fromArtifact = ProofReelModel.decodeReceipt(from: artifact)
        #expect(fromArtifact?.runId == "r-reel")
        #expect(fromArtifact?.model == "haiku")
        #expect(fromArtifact?.git?.dirtyAtStart == true)

        let event = ChatEvent(
            conversationID: "c-reel",
            seq: 9,
            turnID: "t-reel",
            runID: "r-reel",
            kind: "receipt",
            payloadJSON: payload
        )
        let fromEvent = ProofReelModel.decodeReceipt(from: event)
        #expect(fromEvent?.agent == "claude")
        #expect(ProofReelModel.stops(from: fromEvent!).count == 8)

        let nonReceipt = ChatEvent(
            conversationID: "c-reel",
            seq: 1,
            kind: "output",
            payloadJSON: payload
        )
        #expect(ProofReelModel.decodeReceipt(from: nonReceipt) == nil)
    }

    @Test("decodes a real daemon lancer.proof/v0 payload with no conversationId")
    func decodesRealDaemonPayload() {
        // Verbatim daemon output (receipt.go marks conversationId omitempty) —
        // sim live-loop gate 2026-07-11 caught the required-field decode failure.
        let payload = """
        {"schema":"lancer.proof/v0","runId":"f7abbf2b-8ca7-403c-8b3e-f948b5232425",\
        "agent":"claude","model":"haiku","startedAt":"2026-07-12T02:58:50Z",\
        "endedAt":"2026-07-12T02:58:54Z","exitCode":0,"status":"completed",\
        "commands":null,"filesTouched":null,"tests":{"ran":false,"passed":0,"failed":0},\
        "criteria":null,"git":{"startRef":"3ee418542fdd113cff645de6c07eb1c621cb32ca",\
        "endRef":"3ee418542fdd113cff645de6c07eb1c621cb32ca","dirtyAtStart":true},\
        "confidence":{"commands":"complete","files":"complete","tests":"bestEffort"},\
        "resume":{"agent":"claude","vendorSessionId":"379f9b3a-a5bb-4a93-b9d0-2b5fd4a6f699"},\
        "answersReserved":null}
        """
        let receipt = ProofReelModel.decodeReceiptPayload(payload)
        #expect(receipt != nil)
        #expect(receipt?.conversationId == nil)
        #expect(receipt?.runId == "f7abbf2b-8ca7-403c-8b3e-f948b5232425")
        #expect(receipt?.status == "completed")
    }

    @Test("durationText and shortGitRef format observed metadata")
    func formattingHelpers() {
        #expect(
            ProofReelModel.durationText(
                startedAt: "2026-07-08T10:00:00Z",
                endedAt: "2026-07-08T10:12:00Z"
            ) == "12m 0s"
        )
        #expect(ProofReelModel.shortGitRef("abcdef012345") == "abcdef0")
        #expect(ProofReelModel.shortGitRef("abc") == "abc")
        #expect(ProofReelModel.shortGitRef(nil) == nil)
    }

    @Test("iso8601Date accepts fractional and plain internet timestamps")
    func iso8601FractionalAndPlain() {
        let fractional = ProofReelModel.iso8601Date(from: "2026-07-12T08:30:00.123Z")
        let plain = ProofReelModel.iso8601Date(from: "2026-07-12T08:30:00Z")
        #expect(fractional != nil)
        #expect(plain != nil)
        #expect(ProofReelModel.localizedTimestamp("2026-07-12T08:30:00.123Z") != nil)
        #expect(ProofReelModel.localizedTimestamp("not-a-date") == nil)
    }
}
