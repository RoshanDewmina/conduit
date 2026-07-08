#if os(iOS)
import Testing
@testable import AppFeature
import LancerCore

@Suite("CursorComposerContract")
struct CursorComposerContractTests {

    @Test("resolvedContract returns nil when all fields empty")
    func emptyContractOmitsWirePayload() {
        let contract = CursorComposerSheet.resolvedContract(
            prompt: "Build the feature",
            goal: "",
            doneCriteria: [""],
            validationCommands: [""]
        )
        #expect(contract == nil)
    }

    @Test("resolvedContract defaults goal to first prompt line when criteria present")
    func goalDefaultsToFirstLine() {
        let contract = CursorComposerSheet.resolvedContract(
            prompt: "Add login flow\nWith OAuth support",
            goal: "",
            doneCriteria: ["Login screen renders"],
            validationCommands: [""]
        )
        #expect(contract?.goal == "Add login flow")
        #expect(contract?.doneCriteria == ["Login screen renders"])
    }

    @Test("resolvedContract caps criteria and validation commands")
    func capsRowCounts() {
        let contract = CursorComposerSheet.resolvedContract(
            prompt: "Ship it",
            goal: "Ship it",
            doneCriteria: (1...10).map { "criterion \($0)" },
            validationCommands: (1...6).map { "cmd \($0)" }
        )
        #expect(contract?.doneCriteria.count == 8)
        #expect(contract?.validationCommands.count == 4)
    }
}
#endif
