import Testing
@testable import AppFeature

@Suite("Workspace routing")
struct WorkspaceRoutingTests {
    @Test("dirty branch changes require explicit confirmation")
    func dirtyBranchProtection() {
        #expect(WorkspaceBranchGuard.needsConfirmation(currentBranch: "main", targetBranch: "release", isClean: false))
        #expect(!WorkspaceBranchGuard.needsConfirmation(currentBranch: "main", targetBranch: "main", isClean: false))
        #expect(!WorkspaceBranchGuard.needsConfirmation(currentBranch: "main", targetBranch: "release", isClean: true))
    }

    @Test("relay-only workspace surfaces require SSH")
    func relayUnavailableState() {
        #expect(WorkspaceTransportAccess.terminalAccess(isSSHConnected: true) == .sshConnected)
        #expect(WorkspaceTransportAccess.terminalAccess(isSSHConnected: false) == .sshRequired)
    }
}
