#if os(iOS)
import SwiftUI

struct ThoughtProcessSheet: View {
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Text(text)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .padding(.bottom, 24)
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("thought-process-sheet")
    }

    private var header: some View {
        ZStack {
            Text("Thought process")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        )
                }
                .accessibilityLabel(Text("Close"))

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
#endif
