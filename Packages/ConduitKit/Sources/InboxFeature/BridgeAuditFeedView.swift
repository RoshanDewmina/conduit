#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        AuditEntryRow(entry: entry)
                        if entry.id != entries.last?.id {
                            Divider()
                                .background(t.divider)
                        }
                    }
                }
            }
        }
    }
}

private struct AuditEntryRow: View {
    let entry: AuditLogEntry
    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DSStatusDot(tone: chipTone.asDotTone, size: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    DSChip(chipLabel, systemImage: chipIcon, tone: chipTone, variant: .soft, size: .sm)
                    Spacer()
                    Text(entry.timestamp)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text4)
                        .lineLimit(1)
                }

                if let agent = entry.agent, !agent.isEmpty {
                    Text(agent)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }

                if let cmd = entry.command, !cmd.isEmpty {
                    Text(cmd)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text2)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                if let rule = entry.rule, !rule.isEmpty {
                    Text(rule)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text4)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var chipLabel: String {
        switch entry.action {
        case "auto-allow":               return "auto-allow"
        case "auto-deny":                return "auto-deny"
        case "escalate":                 return "escalate"
        case "approve":                  return "you-allowed"
        case "approveAlways":            return "you-always"
        case "deny":                     return "you-denied"
        case "dispatch-launched":        return "dispatch"
        case "dispatch-denied":          return "dispatch-deny"
        case "dispatch-needs-approval":  return "dispatch-ask"
        case "dispatch-budget-exceeded",
             "run-budget-exceeded":      return "budget"
        case "dispatch-error":           return "error"
        case "run-stopped":              return "stopped"
        case "run-paused":               return "paused"
        case "run-resumed":              return "resumed"
        default:                         return entry.action
        }
    }

    private var chipTone: DSChipTone {
        switch entry.action {
        case "auto-allow":               return .ok
        case "auto-deny":                return .danger
        case "escalate":                 return .orange
        case "approve", "approveAlways": return .neutral
        case "deny":                     return .danger
        case "dispatch-launched":        return .info
        case "dispatch-denied":          return .danger
        case "dispatch-needs-approval":  return .orange
        case "dispatch-budget-exceeded",
             "run-budget-exceeded":      return .warn
        case "dispatch-error":           return .warn
        case "run-stopped",
             "run-paused",
             "run-resumed":              return .neutral
        default:                         return .neutral
        }
    }

    private var chipIcon: String? {
        switch entry.action {
        case "auto-allow":               return "checkmark"
        case "auto-deny":                return "xmark"
        case "escalate":                 return "bell"
        case "approve", "approveAlways": return "hand.thumbsup"
        case "deny":                     return "hand.thumbsdown"
        case "dispatch-launched":        return "play"
        case "dispatch-denied":          return "xmark.circle"
        case "dispatch-needs-approval":  return "bell"
        case "dispatch-budget-exceeded",
             "run-budget-exceeded":      return "exclamationmark.circle"
        case "dispatch-error":           return "exclamationmark.triangle"
        case "run-stopped":              return "stop"
        case "run-paused":               return "pause"
        case "run-resumed":              return "play"
        default:                         return nil
        }
    }
}

private extension DSChipTone {
    var asDotTone: DSStatusDotTone {
        switch self {
        case .ok:      return .ok
        case .warn:    return .warn
        case .orange:  return .orange
        case .danger:  return .danger
        case .info:    return .info
        case .accent:  return .accent
        case .neutral: return .off
        }
    }
}

#endif
