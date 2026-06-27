import Foundation

public enum WorkspaceTransportAccess: Equatable, Sendable {
    case sshConnected
    case sshRequired

    public static func terminalAccess(isSSHConnected: Bool) -> WorkspaceTransportAccess {
        isSSHConnected ? .sshConnected : .sshRequired
    }
}

public enum WorkspaceBranchGuard {
    /// Switching branch is safe without confirmation only when the branch is
    /// changing and the working tree is clean.
    public static func needsConfirmation(currentBranch: String, targetBranch: String, isClean: Bool) -> Bool {
        currentBranch != targetBranch && !isClean
    }
}
