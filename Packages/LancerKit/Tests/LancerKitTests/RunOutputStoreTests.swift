#if os(iOS)
import Testing
import LancerCore
@testable import AppFeature

@Suite("RunOutputStore")
@MainActor
struct RunOutputStoreTests {
    @Test("failed run with no output still has a visible failure summary")
    func failedRunWithoutOutputHasSummary() {
        let store = RunOutputStore()
        store.register(runId: "run-zero")
        store.updateStatus(RunStatusParams(runId: "run-zero", status: "failed", exitCode: 1))

        let run = store.run("run-zero")
        #expect(run?.text == "")
        #expect(run?.failureSummary == "Run failed with exit code 1.")
    }

    @Test("failed run with output uses the real output as the failure summary")
    func failedRunWithOutputUsesOutput() {
        let store = RunOutputStore()
        store.register(runId: "run-stderr")
        store.appendOutput(RunOutputParams(runId: "run-stderr", stream: "stderr", chunk: "model not found\n", seq: 1))
        store.updateStatus(RunStatusParams(runId: "run-stderr", status: "failed", exitCode: 1))

        #expect(store.run("run-stderr")?.failureSummary == "model not found")
    }
}
#endif
