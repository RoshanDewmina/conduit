#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

/// "While you were away" feed of bridge autonomous policy decisions.
public struct AuditWhileAwayView: View {
    public let entries: [AuditLogEntry]

    @Environment(\.conduitTokens) private var t

    public init(entries: [AuditLogEntry]) {
        self.entries = entries
    }

    public var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No autonomous decisions yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Auto-allow, auto-deny, and escalations from conduitd appear here.")
                )
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.action)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: entry.action))
                            Spacer()
                            Text(entry.timestamp)
                                .font(.caption2.monospaced())
                                .foregroundStyle(t.text4)
                        }
                        if let agent = entry.agent {
                            Text(agent).font(.caption2).foregroundStyle(t.text3)
                        }
                        if let rule = entry.rule {
                            Text(rule).font(.caption2.monospaced()).foregroundStyle(t.text4)
                        }
                        if let cmd = entry.command {
                            Text(cmd)
                                .font(.caption2.monospaced())
                                .lineLimit(2)
                                .foregroundStyle(t.text2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func color(for action: String) -> Color {
        switch action {
        case "auto-allow", "approve", "approveAlways":
            return t.ok
        case "auto-deny", "deny":
            return t.danger
        default:
            return t.warn
        }
    }
}

#endif
