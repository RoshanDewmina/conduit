#if os(iOS)
import SwiftUI

/// Shared thread-row view for `ThreadListView` and `SearchView`.
/// Status labels come from `WorkspaceRepoCatalog` — never invented CI copy.
struct ThreadListRow: View {
    let thread: ThreadListItem
    var showsRepoName: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(dotColor)
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

    private var dotColor: Color {
        switch thread.statusKind {
        case .working: return .orange
        case .completed: return Color(.systemGray3)
        case .failed: return .red
        case .archived: return Color(.systemGray4)
        case .idle: return Color(.systemGray4)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 4) {
            switch thread.statusKind {
            case .working:
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            case .completed:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
            case .archived, .idle:
                EmptyView()
            }

            Text(thread.statusLabel)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .italic(thread.statusKind == .idle)

            if showsRepoName, let repoName = thread.repoName {
                Text("· \(repoName)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
