#if os(iOS)
import SwiftUI

/// Sticky-ish file header + collapsible hunks for one changed file.
struct DiffFileSection: View {
    let file: RepoDiffFile
    let fileDiff: RepoFileDiff?
    let isLoading: Bool
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
                } else if let fileDiff {
                    ForEach(fileDiff.hunks) { hunk in
                        DiffHunkView(
                            hunk: hunk,
                            path: file.path,
                            expandAll: expandAll,
                            onComment: onComment
                        )
                        Divider()
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
                        Text(file.fileName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
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
}
#endif
