#if os(iOS)
import Foundation
import Observation
import InboxFeature
import LancerCore
import SSHTransport
import AgentKit

/// Bridges real AppRoot infrastructure into the Cursor-style navigation shell
/// for Tier-0 phone-usable flows (workspaces, threads, dispatch, approvals).
@MainActor
@Observable
public final class CursorShellLiveBridge {
    public enum ConnectionPhase: Sendable, Equatable {
        case connected
        case reconnecting
        case offline
        case needsPairing
    }

    public struct WorkspaceRow: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let threadCount: Int
    }

    public struct ThreadRow: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let repoName: String
        public let updatedAt: Date?
    }

    public var workspaces: [WorkspaceRow] = []
    public var threadsByWorkspace: [String: [ThreadRow]] = [:]
    public var pendingApprovalID: ApprovalID?
    public var composerCWD: String = ""
    public var selectedThreadID: String?
    /// OpenRouter / vendor model slug used for the next dispatch from the composer.
    public var composerModelSlug: String = ManagedModel.claudeHaiku.rawValue
    public var composerModelLabel: String = ManagedModel.claudeHaiku.label
    public var connectionPhase: ConnectionPhase = .connected
    public var threadAttention: [String: CursorThreadAttention] = [:]

    public var onDispatch: ((String, String, String?) async -> Void)?
    public var onContinue: ((String, String, String?) async -> Void)?
    public var onDecide: ((ApprovalID, Approval.Decision) async -> Void)?
    public var onRequestPairing: (() -> Void)?
    public var onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)?
    public var relayMachineCount: Int = 0

    public init() {}

    public func threads(for workspaceName: String) -> [ThreadRow] {
        threadsByWorkspace[workspaceName] ?? []
    }

    public func reloadWorkspaces(from names: [String], threadCounts: [String: Int]) {
        workspaces = names.map { name in
            WorkspaceRow(id: name, name: name, threadCount: threadCounts[name] ?? 0)
        }
    }

    public func reloadThreads(workspaceName: String, rows: [ThreadRow]) {
        threadsByWorkspace[workspaceName] = rows
    }
}
#endif
