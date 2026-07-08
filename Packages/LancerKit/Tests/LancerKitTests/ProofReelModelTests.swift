import Foundation
import Testing
@testable import LancerCore
@testable import SessionFeature

@Suite struct ProofReelModelTests {
    private var fixtureReceipt: ProofReceipt {
        ProofReceipt(
            runId: "r-reel",
            conversationId: "c-reel",
            agent: "claude",
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
            ]
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
}
