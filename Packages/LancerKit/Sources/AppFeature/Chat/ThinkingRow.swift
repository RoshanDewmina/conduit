#if os(iOS)
import SwiftUI

struct ThinkingRow: View {
    let text: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("Thought process")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Thought process"))
        .accessibilityHint(Text("Show thought process"))
        .sheet(isPresented: $isPresented) {
            ThoughtProcessSheet(text: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
