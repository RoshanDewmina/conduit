import Foundation
import Testing
import LancerCore
@testable import AppFeature

// Sendable fake: an actor satisfies RunControlling's Sendable requirement and
// records the exact call sequence for assertions.
actor FakeRunChannel: RunControlling {
    private(set) var calls: [String] = []
    func pauseRun(runId: String) async throws -> Bool { calls.append("pause:\(runId)"); return true }
    func resumeRun(runId: String) async throws -> Bool { calls.append("resume:\(runId)"); return true }
    func stopRun(runId: String) async throws -> Bool { calls.append("stop:\(runId)"); return true }
    func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { calls.append("budget:\(runId):\(budgetUSD)"); return true }
    func continueRun(runId: String, prompt: String) async throws -> DispatchResult {
        calls.append("continue:\(runId)")
        return DispatchResult(runId: "\(runId)-2", status: "started")
    }
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

    @Test @MainActor func controlAvailabilityTracksStatus() {
        let fake = FakeRunChannel()
        let running = RunControlStore(channel: fake, runId: "r1", status: .running)
        #expect(running.canStop && running.canPause && !running.canResume)

        let paused = RunControlStore(channel: fake, runId: "r1", status: .paused)
        #expect(paused.canStop && !paused.canPause && paused.canResume)

        let stopped = RunControlStore(channel: fake, runId: "r1", status: .stopped)
        #expect(!stopped.canStop && !stopped.canPause && !stopped.canResume)

        let exceeded = RunControlStore(channel: fake, runId: "r1", status: .budgetExceeded)
        #expect(!exceeded.canStop && !exceeded.canPause && !exceeded.canResume && !exceeded.canSetBudget)
    }
}

// Throwing fake: exercises RunControlStore's catch branch (the only error path).
private actor ThrowingRunChannel: RunControlling {
    struct Boom: Error {}
    func pauseRun(runId: String) async throws -> Bool { throw Boom() }
    func resumeRun(runId: String) async throws -> Bool { throw Boom() }
    func stopRun(runId: String) async throws -> Bool { throw Boom() }
    func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { throw Boom() }
    func continueRun(runId: String, prompt: String) async throws -> DispatchResult { throw Boom() }
}
