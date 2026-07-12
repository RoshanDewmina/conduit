#if os(iOS)
import SwiftUI

/// Collapsed-by-default thinking caption; tap expands full text.
/// Caption/default match `ThinkingPresentation` (unit-tested).
struct ThinkingRow: View {
    let text: String

    @State private var isExpanded = ThinkingPresentation.isExpandedByDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(ThinkingPresentation.collapsedCaption)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(ThinkingPresentation.collapsedCaption))
            .accessibilityHint(Text(isExpanded ? "Collapse thinking" : "Expand thinking"))

            if isExpanded {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
