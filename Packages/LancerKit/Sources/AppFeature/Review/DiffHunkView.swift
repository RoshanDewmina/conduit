#if os(iOS)
import SwiftUI

/// Collapsible hunk: "Lines X–Y +a −d" + unified diff lines.
struct DiffHunkView: View {
    let hunk: RepoDiffHunk
    let path: String
    var expandAll: Bool
    var onComment: (DiffDisplayRow) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(hunk.sectionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(DiffHunkPresentation.rows(from: hunk)) { row in
                    DiffLineRow(row: row) {
                        onComment(row)
                    }
                }
            }
        }
        .onChange(of: expandAll) { _, newValue in
            isExpanded = newValue
        }
        .onAppear { isExpanded = expandAll }
    }
}
#endif
