#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

/// "While you were away" feed of bridge autonomous policy decisions.
public struct BridgeAuditFeedView: View {
    public let entries: [AuditLogEntry]

    @Environment(\.conduitTokens) private var t

    public init(entries: [AuditLogEntry]) {
        self.entries = entries
    }

    public var body: some View {
        Group {
            if entries.isEmpty {
                DSEmptyState(
                    icon: .hourglass,
                    title: "no decisions yet",
                    subtitle: "Auto-allow, auto-deny, and escalations from conduitd appear here."
                )
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.effect ?? entry.action)
                                .font(.dsMonoPt(12, weight: .semibold))
                                .foregroundStyle(color(for: entry.effect ?? entry.action))
                            Spacer()
                            Text(entry.timestamp)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text4)
                        }
                        if let agent = entry.agent {
                            Text(agent).font(.dsMonoPt(11)).foregroundStyle(t.text3)
                        }
                        if let rule = entry.rule {
                            Text(rule).font(.dsMonoPt(11)).foregroundStyle(t.text4)
                        }
                        if let cmd = entry.command {
                            Text(cmd)
                                .font(.dsMonoPt(11))
                                .lineLimit(2)
                                .foregroundStyle(t.text2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func color(for decision: String) -> Color {
        switch decision {
        case "allow", "approve", "approveAlways":
            return t.ok
        case "deny":
            return t.danger
        default:
            return t.warn
        }
    }
}

#endif
