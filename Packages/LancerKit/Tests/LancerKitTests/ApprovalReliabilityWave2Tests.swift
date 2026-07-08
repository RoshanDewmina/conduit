import Testing
import Foundation
import GRDB
@testable import LancerCore
@testable import PersistenceKit
@testable import SSHTransport

// Wave-2 reliability majors: M7 (governance-context persistence round-trip),
// M8 (stable device id), M9 (exactly-once decision gate).

@Suite("M7 — governance context persistence round-trip")
struct GovernanceContextPersistenceTests {

    @Test("blastRadius / question / choices / answeredChoice survive the DB round-trip")
    func governanceFieldsRoundTrip() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)

        let blast = ApprovalBlastRadius(
            files: ["src/main.go", "README.md"],
            touchesGit: true,
            touchesNetwork: false,
            matchedRule: "deny-network-writes"
        )
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .askQuestion,
            cwd: "/repo",
            risk: .high,
            question: "Proceed with the migration?",
            choices: ["Yes", "No", "Dry run"],
            answeredChoice: 2,
            blastRadius: blast
        )

        try await repo.upsert(approval)

        let stored = try await repo.all()
        #expect(stored.count == 1)
        let read = try #require(stored.first)

        // Blast radius — the governance banner's source data.
        #expect(read.blastRadius?.files == ["src/main.go", "README.md"])
        #expect(read.blastRadius?.touchesGit == true)
        #expect(read.blastRadius?.touchesNetwork == false)
        #expect(read.blastRadius?.matchedRule == "deny-network-writes")

        // Ask-question fields — the choice UI's source data.
        #expect(read.question == "Proceed with the migration?")
        #expect(read.choices == ["Yes", "No", "Dry run"])
        #expect(read.answeredChoice == 2)
    }

    @Test("an approval with no governance context decodes to nil (legacy / plain rows)")
    func governanceFieldsNilWhenAbsent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)

        let approval = Approval(
            sessionID: SessionID(),
            agent: .codex,
            kind: .command,
            command: "ls",
            cwd: "/tmp",
            risk: .low
        )
        try await repo.upsert(approval)

        let read = try #require(try await repo.all().first)
        #expect(read.blastRadius == nil)
        #expect(read.question == nil)
        #expect(read.choices == nil)
        #expect(read.answeredChoice == nil)
    }
}

@Suite("Content-hash binding — persistence round-trip")
struct ContentHashPersistenceTests {

    @Test("contentHash survives the DB round-trip")
    func contentHashRoundTrips() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)

        let hash = Approval.computeContentHash(command: "rm -rf build", patch: nil, cwd: "/repo", toolInput: nil)
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "rm -rf build",
            cwd: "/repo",
            risk: .high,
            contentHash: hash
        )
        try await repo.upsert(approval)

        let read = try #require(try await repo.all().first)
        #expect(read.contentHash == hash)

        let found = try await repo.find(id: approval.id)
        #expect(found?.contentHash == hash)
    }

    @Test("an approval with no contentHash decodes to nil (legacy / on-device-only rows)")
    func contentHashNilWhenAbsent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)

        let approval = Approval(
            sessionID: SessionID(),
            agent: .codex,
            kind: .command,
            command: "ls",
            cwd: "/tmp",
            risk: .low
        )
        try await repo.upsert(approval)

        let read = try #require(try await repo.all().first)
        #expect(read.contentHash == nil)
    }

    @Test("find(id:) returns nil for an id with no row")
    func findReturnsNilForMissingRow() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let found = try await repo.find(id: ApprovalID())
        #expect(found == nil)
    }
}

@Suite("M8 — stable device identity")
struct DeviceIdentityTests {

    @Test("sessionID is generated once and reused for the install")
    func sessionIDIsStable() {
        let suite = "test-deviceid-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = DeviceIdentity.sessionID(defaults: defaults)
        let second = DeviceIdentity.sessionID(defaults: defaults)
        let third = DeviceIdentity.sessionID(defaults: defaults)

        #expect(first == second)
        #expect(second == third)
        #expect(!first.isEmpty)
        // It is a valid UUID string.
        #expect(UUID(uuidString: first) != nil)
    }

    @Test("a pre-seeded value is honored (no re-mint)")
    func sessionIDHonorsExistingValue() {
        let suite = "test-deviceid-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let seeded = UUID().uuidString
        defaults.set(seeded, forKey: "dev.lancer.stableDeviceSessionID")
        #expect(DeviceIdentity.sessionID(defaults: defaults) == seeded)
    }
}

@Suite("M9 — exactly-once decision delivery gate")
struct ExactlyOnceDecisionTests {

    // The whole exactly-once design rests on `decide` being authoritative on the
    // FIRST call only: callers (inbox card / watch / relay) forward the wire
    // decision exactly once because they fire only when the row actually changed.
    @Test("first decision wins; a second decision does not re-resolve")
    func firstDecisionWins() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "rm -rf build",
            cwd: "/repo",
            risk: .high
        )
        try await repo.upsert(approval)

        let firstApprove = try await repo.decide(id: approval.id, decision: .approved)
        #expect(firstApprove == true)   // resolves → caller forwards once

        // A lingering banner tap (or a double-tap) must NOT flip / re-forward.
        let secondReject = try await repo.decide(id: approval.id, decision: .rejected)
        #expect(secondReject == false)  // no change → caller does not forward again

        let read = try #require(try await repo.all().first)
        #expect(read.decision == .approved)  // first decision held
    }

    @Test("decision wire values are stable across the SSH + relay transports")
    func decisionWireValuesStable() {
        #expect(DaemonChannel.decisionWireValue(for: .approved) == "approve")
        #expect(DaemonChannel.decisionWireValue(for: .approvedAlways) == "approveAlways")
        #expect(DaemonChannel.decisionWireValue(for: .rejected) == "deny")
        #expect(DaemonChannel.decisionWireValue(for: .expired) == "deny")
    }
}

#if os(iOS)
import InboxFeature
import SessionFeature

@Suite("M8/M9 — relay decision body uses the agreed session id")
@MainActor
struct RelayDecisionBodyTests {

    @Test("backend decision body carries the same sessionId used to register")
    func backendBodyCarriesSessionID() throws {
        // The sessionId in the decision POST body is the backend's per-session
        // token lookup key — it MUST equal the id sent to registerDevice (M8/B2).
        let sessionID = DeviceIdentity.sessionID()
        let data = ApprovalRelay.backendDecisionBody(
            approvalID: "11111111-0000-0000-0000-000000000001",
            decision: .approved,
            sessionID: sessionID,
            editedToolInput: nil
        )
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(obj["sessionId"] as? String == sessionID)
        #expect(obj["decision"] as? String == "approve")
        #expect(obj["approvalId"] as? String == "11111111-0000-0000-0000-000000000001")
    }
}

@Suite("Relay approval decision race")
@MainActor
struct RelayApprovalDecisionRaceTests {

    @Test("pending in-memory relay approval forwards when durable row is not present yet")
    func inMemoryPendingApprovalStillForwardsDecision() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ApprovalRepository(db)
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "printf ready",
            cwd: "/repo",
            risk: .medium,
            contentHash: "shown-content"
        )
        let recorder = DecisionRecorder()
        let vm = LiveInboxViewModel(
            repository: repo,
            onDecision: { id, decision, edited, contentHash in
                await recorder.record(id: id, decision: decision, edited: edited, contentHash: contentHash)
            },
            clearDeliveredApproval: { _ in }
        )
        vm.approvals = [approval]

        vm.decide(approval.id, decision: .approved)
        try await Task.sleep(for: .milliseconds(50))

        let recorded = await recorder.value
        #expect(recorded?.id == approval.id)
        #expect(recorded?.decision == .approved)
        #expect(recorded?.edited == nil)
        #expect(recorded?.contentHash == "shown-content")
    }
}

private actor DecisionRecorder {
    struct Value: Sendable {
        let id: ApprovalID
        let decision: Approval.Decision
        let edited: String?
        let contentHash: String?
    }

    private(set) var value: Value?

    func record(id: ApprovalID, decision: Approval.Decision, edited: String?, contentHash: String?) {
        value = Value(id: id, decision: decision, edited: edited, contentHash: contentHash)
    }
}
#endif
