import Testing
@testable import AppFeature
import LancerCore

@Suite("CursorComposerContract")
struct CursorComposerContractTests {

    @Test("resolvedContract returns nil when all fields empty")
    func emptyContractOmitsWirePayload() {
        let contract = CursorComposerContract.resolvedContract(
            prompt: "Build the feature",
            goal: "",
            doneCriteria: [""],
            validationCommands: [""]
        )
        #expect(contract == nil)
    }

    @Test("resolvedContract defaults goal to first prompt line when criteria present")
    func goalDefaultsToFirstLine() {
        let contract = CursorComposerContract.resolvedContract(
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
        let contract = CursorComposerContract.resolvedContract(
            prompt: "Ship it",
            goal: "Ship it",
            doneCriteria: (1...10).map { "criterion \($0)" },
            validationCommands: (1...6).map { "cmd \($0)" }
        )
        #expect(contract?.doneCriteria.count == 8)
        #expect(contract?.validationCommands.count == 4)
    }

    @Test("Home / empty repo resolves to ~ and is never blocked")
    func homeCWDAlwaysResolves() {
        let home = CursorComposerCWDResolution.resolve(
            repoName: "Home",
            repoPaths: [:],
            hasSelectedThread: false
        )
        #expect(home.path == "~")
        #expect(home.blocked == false)

        let empty = CursorComposerCWDResolution.resolve(
            repoName: "",
            repoPaths: [:],
            hasSelectedThread: false
        )
        #expect(empty.path == "~")
        #expect(empty.blocked == false)
    }

    @Test("named workspace uses repoPaths absolute path when known")
    func namedWorkspaceUsesRepoPaths() {
        let resolved = CursorComposerCWDResolution.resolve(
            repoName: "command-center",
            repoPaths: ["command-center": "/Users/dev/command-center"],
            hasSelectedThread: false
        )
        #expect(resolved.path == "/Users/dev/command-center")
        #expect(resolved.blocked == false)
        #expect(resolved.message == nil)
    }

    @Test("named workspace without path blocks until a thread is opened")
    func unknownNamedWorkspaceBlocksWithoutThread() {
        let blocked = CursorComposerCWDResolution.resolve(
            repoName: "command-center",
            repoPaths: [:],
            hasSelectedThread: false
        )
        #expect(blocked.path == nil)
        #expect(blocked.blocked == true)
        #expect(blocked.message?.contains("command-center") == true)

        let unblocked = CursorComposerCWDResolution.resolve(
            repoName: "command-center",
            repoPaths: [:],
            hasSelectedThread: true
        )
        #expect(unblocked.blocked == false)
    }
}
