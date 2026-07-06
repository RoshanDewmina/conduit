#if os(iOS)
import Foundation
import Observation
import InboxFeature
import LancerCore
import AgentKit

/// Bridges real AppRoot infrastructure into the Cursor-style navigation shell
/// for Tier-0 phone-usable flows (workspaces, threads, dispatch, approvals).
@MainActor
@Observable
public final class CursorShellLiveBridge {
    public static let allReposWorkspaceName = "All Repos"

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
    public var relayMachineCount: Int = 0

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

    public func reloadWorkspaceThreads(_ rowsByWorkspace: [String: [ThreadRow]]) {
        let names = rowsByWorkspace.keys.sorted()
        let threadCounts = rowsByWorkspace.mapValues(\.count)
        reloadWorkspaces(from: names, threadCounts: threadCounts)

        threadsByWorkspace = [:]
        for (name, rows) in rowsByWorkspace {
            threadsByWorkspace[name] = sortedThreads(rows)
        }
        threadsByWorkspace[Self.allReposWorkspaceName] = sortedThreads(
            rowsByWorkspace.values.flatMap { $0 }
        )
    }

    private func sortedThreads(_ rows: [ThreadRow]) -> [ThreadRow] {
        rows.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }
}
#endif
