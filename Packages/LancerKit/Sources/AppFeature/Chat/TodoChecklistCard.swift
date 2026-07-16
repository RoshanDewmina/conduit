#if os(iOS)
import SwiftUI

/// Inline agent to-dos card: "To-dos m/n" with check circles and strikethrough.
struct TodoChecklistCard: View {
    let state: TodoChecklistState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: leadingSymbol(for: item.status))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(leadingColor(for: item.status))
                            .frame(width: 18, height: 18)

                        Text(item.content)
                            .font(.system(size: 14))
                            .foregroundStyle(item.isComplete ? .secondary : .primary)
                            .strikethrough(item.isComplete, color: .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(accessibilityLabel(for: item)))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private func leadingSymbol(for status: TodoChecklistItem.Status) -> String {
        switch status {
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .inProgress:
            return "circle.lefthalf.filled"
        case .pending:
            return "circle"
        }
    }

    private func leadingColor(for status: TodoChecklistItem.Status) -> Color {
        switch status {
        case .completed:
            return .green
        case .cancelled:
            return .secondary
        case .inProgress:
            return .orange
        case .pending:
            return .secondary
        }
    }

    private func accessibilityLabel(for item: TodoChecklistItem) -> String {
        let status: String
        switch item.status {
        case .completed: status = "completed"
        case .cancelled: status = "cancelled"
        case .inProgress: status = "in progress"
        case .pending: status = "pending"
        }
        return "\(status): \(item.content)"
    }
}
#endif
