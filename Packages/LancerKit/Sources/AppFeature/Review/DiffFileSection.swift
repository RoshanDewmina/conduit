#if os(iOS)
import SwiftUI

/// Sticky-ish file header + collapsible hunks for one changed file.
struct DiffFileSection: View {
    let file: RepoDiffFile
    let fileDiff: RepoFileDiff?
    let isLoading: Bool
    var loadError: String? = nil
    var expandAll: Bool
    var onOpenViewer: () -> Void
    var onComment: (DiffDisplayRow) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .background(Color(.secondarySystemGroupedBackground))

            if isExpanded {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading diff…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                } else if let loadError {
                    Text(loadError)
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .padding(14)
                } else if let fileDiff {
                    if fileDiff.hunks.isEmpty {
                        emptyHunksBody
                    } else {
                        ForEach(fileDiff.hunks) { hunk in
                            DiffHunkView(
                                hunk: hunk,
                                expandAll: expandAll,
                                onComment: onComment
                            )
                            Divider()
                        }
                    }
                    if fileDiff.truncated {
                        Text("Diff truncated")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(12)
                    }
                } else {
                    Text("No hunks")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            }
        }
        .onChange(of: expandAll) { _, newValue in
            isExpanded = newValue
        }
        .onAppear { isExpanded = expandAll }
    }

    private var emptyHunksBody: some View {
        Text(emptyHunksMessage)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(emptyHunksMessage))
    }

    private var emptyHunksMessage: String {
        switch file.statusLabel {
        case "deleted":
            return "File deleted"
        case "renamed", "copied":
            return "Renamed — no textual changes"
        case "added" where file.added == 0 && file.removed == 0:
            return "Binary or empty file"
        case "binary":
            return "Binary file"
        default:
            if file.added == 0 && file.removed == 0 {
                return "Mode-only or binary change"
            }
            return "No textual hunks"
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(file.fileName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(file.statusLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(statusForeground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(statusBackground))
                        }
                        if !file.directoryPath.isEmpty {
                            Text(file.directoryPath)
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(file.countsLabel)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(isExpanded ? "Collapse" : "Expand") \(file.fileName), \(file.statusLabel)"))

            Button(action: onOpenViewer) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open \(file.fileName) in viewer"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusForeground: Color {
        switch file.statusLabel {
        case "added": return .green
        case "deleted": return .red
        case "renamed", "copied": return .orange
        default: return .secondary
        }
    }

    private var statusBackground: Color {
        switch file.statusLabel {
        case "added": return Color.green.opacity(0.14)
        case "deleted": return Color.red.opacity(0.14)
        case "renamed", "copied": return Color.orange.opacity(0.14)
        default: return Color(.tertiarySystemFill)
        }
    }
}
#endif
