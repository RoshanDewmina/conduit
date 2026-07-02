import Testing
#if os(iOS)
@testable import SessionFeature

@Suite @MainActor struct ActiveRunRegistryTests {
    @Test("markActive then markTerminal removes the run from activeRunIDs")
    func activeThenTerminal() {
        let registry = ActiveRunRegistry()
        registry.markActive(runId: "run-1")
        #expect(registry.activeRunIDs.contains("run-1"))

        registry.markTerminal(runId: "run-1")
        #expect(!registry.activeRunIDs.contains("run-1"))
    }

    @Test("marking the same run active twice does not duplicate it")
    func idempotentMarkActive() {
        let registry = ActiveRunRegistry()
        registry.markActive(runId: "run-2")
        registry.markActive(runId: "run-2")
        #expect(registry.activeRunIDs.filter { $0 == "run-2" }.count == 1)
    }

    @Test("marking an unknown run terminal is a no-op, not a crash")
    func markTerminalUnknownRunIsNoOp() {
        let registry = ActiveRunRegistry()
        registry.markTerminal(runId: "never-registered")
        #expect(registry.activeRunIDs.isEmpty)
    }
}
#endif
