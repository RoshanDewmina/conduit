import Foundation

/// The app-level workspace presenter uses one route instead of one Boolean per
/// sheet. It is deliberately cross-platform so routing can be unit tested.
public enum WorkspaceRoute: String, Identifiable, Sendable {
    case launcher
    case environment
    case review
    case terminal
    case browser
    case files

    public var id: String { rawValue }
}

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
