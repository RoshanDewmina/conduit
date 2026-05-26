import SwiftUI
import ConduitCore

struct InboxListView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            if store.approvals.isEmpty {
                emptyState
            } else {
                ForEach(store.approvals) { item in
                    NavigationLink(value: item) {
                        ApprovalRowView(item: item)
                    }
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Inbox")
        .navigationDestination(for: WatchApprovalTransfer.self) { item in
            ApprovalDetailView(item: item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No pending\napprovals")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Row

private struct ApprovalRowView: View {
    let item: WatchApprovalTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(riskColor(item.risk))
                    .frame(width: 6, height: 6)
                Text(item.agent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(timeAgo(from: item.createdDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if let cmd = item.command {
                Text(cmd)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(2)
            } else {
                Text(item.kind.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
