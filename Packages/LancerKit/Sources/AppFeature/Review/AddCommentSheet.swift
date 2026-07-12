#if os(iOS)
import SwiftUI

/// Add Comment sheet: Cancel / Attach, quoted file:line + line text, Comment field.
struct AddCommentSheet: View {
    let path: String
    let line: Int
    let lineText: String
    var onCancel: () -> Void
    var onAttach: (QueuedReviewComment) -> Void

    @State private var commentText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(ChatFileNameDisplay.displayName(for: path)):\(line)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(lineText)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemFill))
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Comment")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Add a comment for the agent…", text: $commentText, axis: .vertical)
                        .font(.system(size: 16))
                        .lineLimit(3...8)
                        .focused($isFocused)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Add Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") {
                        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onAttach(
                            QueuedReviewComment(
                                path: path,
                                line: line,
                                lineText: lineText,
                                comment: trimmed
                            )
                        )
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }
}
#endif
