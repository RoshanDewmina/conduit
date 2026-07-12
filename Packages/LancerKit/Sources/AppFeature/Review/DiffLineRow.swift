#if os(iOS)
import SwiftUI

/// Single unified-diff line with optional line number and add/del background.
struct DiffLineRow: View {
    let row: DiffDisplayRow
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .top, spacing: 0) {
                Text(lineNumberLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
                    .padding(.trailing, 8)

                Text(prefix + row.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityIdentifier("diff-line-\(row.displayLineNumber ?? 0)")
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var accessibilityDescription: String {
        let kindLabel: String
        switch row.kind {
        case .add: kindLabel = "Added"
        case .del: kindLabel = "Removed"
        case .context: kindLabel = "Context"
        }
        if let n = row.displayLineNumber {
            return "\(kindLabel) line \(n), \(row.text)"
        }
        return "\(kindLabel), \(row.text)"
    }

    private var lineNumberLabel: String {
        if let n = row.displayLineNumber { return "\(n)" }
        return " "
    }

    private var prefix: String {
        switch row.kind {
        case .add: return "+ "
        case .del: return "− "
        case .context: return "  "
        }
    }

    private var foreground: Color {
        switch row.kind {
        case .add: return Color.primary
        case .del: return Color.primary
        case .context: return Color.secondary
        }
    }

    private var background: Color {
        switch row.kind {
        case .add: return Color.green.opacity(0.14)
        case .del: return Color.red.opacity(0.14)
        case .context: return Color.clear
        }
    }
}
#endif
