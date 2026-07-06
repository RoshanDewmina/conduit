#if os(iOS)
import Foundation
import Observation
import InboxFeature
import LancerCore

/// Bridges real AppRoot infrastructure into the Cursor-style navigation shell
/// for Tier-0 phone-usable flows (workspaces, threads, dispatch, approvals).
@MainActor
@Observable
public final class CursorShellLiveBridge {
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

    public var onDispatch: ((String, String) async -> Void)?
    public var onContinue: ((String, String) async -> Void)?
    public var onDecide: ((ApprovalID, Approval.Decision) async -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onRequestPairing: (() -> Void)?

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
