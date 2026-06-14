import Foundation
import Testing
@testable import AppFeature

// Sendable fake: an actor satisfies RunControlling's Sendable requirement and
// records the exact call sequence for assertions.
actor FakeRunChannel: RunControlling {
    private(set) var calls: [String] = []
    func pauseRun(runId: String) async throws -> Bool { calls.append("pause:\(runId)"); return true }
    func resumeRun(runId: String) async throws -> Bool { calls.append("resume:\(runId)"); return true }
    func stopRun(runId: String) async throws -> Bool { calls.append("stop:\(runId)"); return true }
    func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { calls.append("budget:\(runId):\(budgetUSD)"); return true }
}

@Suite("RunControlStore")
struct RunControlStoreTests {
    @Test @MainActor func pauseThenResumeUpdatesStatus() async {
        let fake = FakeRunChannel()
        let store = RunControlStore(channel: fake, runId: "r1")
        await store.pause()
        #expect(store.status == .paused)
        await store.resume()
        #expect(store.status == .running)
        #expect(await fake.calls == ["pause:r1", "resume:r1"])
    }

    @Test @MainActor func setBudgetThenStopSetsStoppedStatus() async {
        let fake = FakeRunChannel()
        let store = RunControlStore(channel: fake, runId: "r1")
        await store.setBudget(2.50)
        await store.stop()
        #expect(store.status == .stopped)
        #expect(await fake.calls == ["budget:r1:2.5", "stop:r1"])
    }

    @Test @MainActor func channelErrorLeavesStatusAndRecordsLastError() async {
        let store = RunControlStore(channel: ThrowingRunChannel(), runId: "r1")
        await store.pause()
        // A failed control call must leave status unchanged and surface the error.
        #expect(store.status == .running)
        #expect(store.lastError != nil)
    }
}

// Throwing fake: exercises RunControlStore's catch branch (the only error path).
private actor ThrowingRunChannel: RunControlling {
    struct Boom: Error {}
    func pauseRun(runId: String) async throws -> Bool { throw Boom() }
    func resumeRun(runId: String) async throws -> Bool { throw Boom() }
    func stopRun(runId: String) async throws -> Bool { throw Boom() }
    func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { throw Boom() }
}
