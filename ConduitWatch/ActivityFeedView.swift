import SwiftUI
import ConduitCore

struct ActivityFeedView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            if store.recentActivity.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No recent activity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.recentActivity) { block in
                    ActivityRowView(block: block)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActivityRowView: View {
    let block: WatchActivityBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status + time
            HStack(spacing: 4) {
                statusIcon
                Spacer(minLength: 2)
                Text(timeAgo(from: block.startedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            // Command
            Text(block.command)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(.primary)
            // Output preview
            if !block.outputPreview.isEmpty {
                Text(block.outputPreview)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            // Duration
            if let duration = block.duration {
                Text(formatDuration(duration))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if block.exitCode == nil {
            // Still running
            Image(systemName: "circle.dotted")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if block.isSuccess == true {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        } else {
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        if d < 1 { return "\(Int(d * 1000))ms" }
        if d < 60 { return String(format: "%.1fs", d) }
        return "\(Int(d / 60))m \(Int(d) % 60)s"
    }
}

private func timeAgo(from interval: TimeInterval) -> String {
    let secs = Int(-Date(timeIntervalSinceReferenceDate: interval).timeIntervalSinceNow)
    if secs < 60 { return "\(secs)s" }
    let mins = secs / 60
    if mins < 60 { return "\(mins)m" }
    return "\(mins / 60)h"
}
