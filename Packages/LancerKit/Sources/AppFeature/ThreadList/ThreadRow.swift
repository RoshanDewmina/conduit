#if os(iOS)
import SwiftUI

/// Shared thread-row model + view for Section 5 of the frontend rebuild:
/// used by both `ThreadListView` (per-workspace, date-grouped) and
/// `SearchView` (flat, repo-tagged). Visual-only — static sample data,
/// no live wiring.
struct ThreadRow: Identifiable {
    let id = UUID()
    let title: String
    let status: ThreadRowStatus
    let diffStat: String?
    var repoName: String? = nil
}

enum ThreadRowStatus {
    case checksPassed
    case merged
    case noChanges
}

/// A single thread row: a small status dot, a title line, and a status
/// line (icon + label, optionally followed by " · +NNN -NNN" diff stats
/// and, in Search results, " · <repo name>").
struct ThreadListRow: View {
    let thread: ThreadRow
    var showsRepoName: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(.systemGray3))
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                statusLine
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 4) {
            switch thread.status {
            case .checksPassed:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Checks Passed")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            case .merged:
                Image(systemName: "arrow.trianglehead.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Merged")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            case .noChanges:
                Text("No Changes")
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(.secondary)
            }

            if let diffStat = thread.diffStat {
                Text("· \(diffStat)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            if showsRepoName, let repoName = thread.repoName {
                Text("· \(repoName)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
