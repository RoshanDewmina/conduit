import Testing
import Foundation
@testable import LancerCore

/// TEST-02: a continued run is only usable when the daemon reports `status:"started"`
/// AND a non-empty runId. An empty-string runId must be rejected like a missing one,
/// or it silently breaks approval/output matching on the follow-up turn.
@Suite("DispatchResult.startedRunId")
struct DispatchResultStartedRunIdTests {
    @Test("started + valid runId is accepted")
    func startedValid() {
        let r = DispatchResult(runId: "run-123", status: "started")
        #expect(r.startedRunId == "run-123")
    }

    @Test("started + empty-string runId is rejected (the TEST-02 gap)")
    func startedEmpty() {
        let r = DispatchResult(runId: "", status: "started")
        #expect(r.startedRunId == nil)
    }

    @Test("started + missing runId is rejected")
    func startedNil() {
        let r = DispatchResult(runId: nil, status: "started")
        #expect(r.startedRunId == nil)
    }

    @Test("non-started status is rejected even with a runId")
    func notStarted() {
        let r = DispatchResult(runId: "run-9", status: "denied")
        #expect(r.startedRunId == nil)
    }

    @Test("decodes from a daemon JSON envelope with an empty runId → rejected")
    func decodesEmptyRunId() throws {
        let json = Data(#"{"runId":"","status":"started","message":"ok"}"#.utf8)
        let r = try JSONDecoder().decode(DispatchResult.self, from: json)
        #expect(r.startedRunId == nil)
    }
}
