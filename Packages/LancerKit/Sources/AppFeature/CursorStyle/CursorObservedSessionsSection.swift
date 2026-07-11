#if os(iOS)
import SwiftUI
import LancerCore

/// User-visible import failure for terminal-originated session pickup.
public struct CursorObservedSessionImportError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Maps daemon `ObservedSession` rows into Cursor-shell list items and applies
/// workspace scoping for the per-repo thread list.
public enum CursorObservedSessionMapping {
    public struct RowModel: Identifiable, Sendable, Equatable {
        public let id: String
        public let provider: String
        public let providerLabel: String
        public let title: String
        public let cwd: String
        public let repoName: String
        public let lastActivity: Date
        public let machineID: String?
        public let hostName: String?

        public var subtitle: String {
            let repo = repoName.isEmpty ? cwd : repoName
            return "\(providerLabel) · \(repo) · \(Self.relativeTime(lastActivity))"
        }

        public init(
            id: String,
            provider: String,
            providerLabel: String,
            title: String,
            cwd: String,
            repoName: String,
            lastActivity: Date,
            machineID: String? = nil,
            hostName: String? = nil
        ) {
            self.id = id
            self.provider = provider
            self.providerLabel = providerLabel
            self.title = title
            self.cwd = cwd
            self.repoName = repoName
            self.lastActivity = lastActivity
            self.machineID = machineID
            self.hostName = hostName
        }

        public init(
            session: ObservedSession,
            machineID: String? = nil,
            hostName: String? = nil
        ) {
            self.init(
                id: session.sessionId,
                provider: session.provider,
                providerLabel: Self.providerLabel(session.provider),
                title: session.title,
                cwd: session.cwd,
                repoName: Self.repoName(from: session.cwd),
                lastActivity: session.lastActivity,
                machineID: machineID,
                hostName: hostName
            )
        }

        public static func providerLabel(_ provider: String) -> String {
            switch provider {
            case "claudeCode": return "Claude Code"
            case "codex": return "Codex"
            case "kimi": return "Kimi"
            case "opencode": return "OpenCode"
            default: return provider
            }
        }

        public static func repoName(from cwd: String) -> String {
            let base = (cwd as NSString).lastPathComponent
            return base.isEmpty ? cwd : base
        }

        public static func relativeTime(_ date: Date, now: Date = .now) -> String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: now)
        }

        public static func rows(
            from sessions: [ObservedSession],
            machineID: String? = nil,
            hostName: String? = nil
        ) -> [RowModel] {
            sessions
                .filter { $0.source == .transcriptObserved }
                .map { RowModel(session: $0, machineID: machineID, hostName: hostName) }
        }

        public static func scoped(
            _ rows: [RowModel],
            workspaceName: String
        ) -> [RowModel] {
            guard workspaceName != "All Repos" else { return rows }
            return rows.filter { $0.repoName == workspaceName }
        }

        public static func sorted(_ rows: [RowModel]) -> [RowModel] {
            rows.sorted { $0.lastActivity > $1.lastActivity }
        }

        #if DEBUG
        public static func mockRows(for workspaceName: String) -> [RowModel] {
            let all: [RowModel] = [
                RowModel(
                    id: "mock-observed-1",
                    provider: "claudeCode",
                    providerLabel: "Claude Code",
                    title: "Refactor relay session list",
                    cwd: "/Users/dev/command-center",
                    repoName: "command-center",
                    lastActivity: .now.addingTimeInterval(-3_600),
                    machineID: "mock-mac",
                    hostName: "Mac Mini Studio"
                ),
                RowModel(
                    id: "mock-observed-2",
                    provider: "codex",
                    providerLabel: "Codex",
                    title: "Add observed-session import UI",
                    cwd: "/Users/dev/lancer-ios",
                    repoName: "lancer-ios",
                    lastActivity: .now.addingTimeInterval(-7_200),
                    machineID: "mock-mac",
                    hostName: "Mac Mini Studio"
                )
            ]
            return sorted(scoped(all, workspaceName: workspaceName))
        }
        #endif
    }
}

/// "On your Mac" — terminal-started sessions offered for import.
public struct CursorObservedSessionsSection: View {
    private let rows: [CursorObservedSessionMapping.RowModel]
    private let onSelect: (CursorObservedSessionMapping.RowModel) -> Void

    public init(
        rows: [CursorObservedSessionMapping.RowModel],
        onSelect: @escaping (CursorObservedSessionMapping.RowModel) -> Void
    ) {
        self.rows = rows
        self.onSelect = onSelect
    }

    public var body: some View {
        if !rows.isEmpty {
            Section("On your Mac") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { onSelect(row) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("observed-session-row-\(index)")
                }
            }
            .accessibilityIdentifier("observed-sessions-section")
        }
    }
}
#endif
