#if os(iOS)
import SwiftUI
import ConduitCore

// MARK: - InboxApprovalCard
//
// Unified inbox card replacing DSAskQuestionCard + DSMCPCallCard.
// Shows agent name, time, question/tool details, risk badge, and Deny + Approve buttons.
// Tapping the card opens InboxApprovalDetail.

public struct InboxApprovalCard: View {
    let agentKey: AgentKey
    let agentName: String
    let timeLabel: String
    let question: String?
    let toolName: String?
    let args: String?
    let risk: Int
    let isCritical: Bool
    let onDeny: () -> Void
    let onApprove: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        agentKey: AgentKey,
        agentName: String,
        timeLabel: String,
        question: String? = nil,
        toolName: String? = nil,
        args: String? = nil,
        risk: Int,
        isCritical: Bool = false,
        onDeny: @escaping () -> Void,
        onApprove: @escaping () -> Void
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.timeLabel = timeLabel
        self.question = question
        self.toolName = toolName
        self.args = args
        self.risk = risk
        self.isCritical = isCritical
        self.onDeny = onDeny
        self.onApprove = onApprove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Head: Agent + Risk + Time
            HStack(spacing: 6) {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                RiskBadge(risk: risk)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            // Content: question or tool call
            if let question {
                // Question block with left accent bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(t.accent)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("QUESTION")
                            .font(.dsDisplayPt(9, weight: .semibold))
                            .tracking(9 * 0.12)
                            .foregroundStyle(t.accent)
                        Text(question)
                            .font(.dsMonoPt(13))
                            .foregroundStyle(t.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let toolName {
                // Tool call block
                Text("\(Text(agentName).foregroundStyle(t.text))\(Text(" is asking permission to use \(toolName)").foregroundStyle(t.text2))")
                    .font(.dsMonoPt(12))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Command well
                HStack(alignment: .top, spacing: 8) {
                    Text("$")
                        .font(.dsMonoPt(12, weight: .semibold))
                        .foregroundStyle(t.danger)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(toolName)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text)
                        if let args {
                            Text(args)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(t.bg)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.divider, lineWidth: 1)
                )
            }

            // Face ID warning for CRITICAL
            if isCritical {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("Face ID required to approve")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(.orange)
                }
            }

            // Action buttons: Deny + Approve (list view)
            HStack(spacing: 8) {
                DSButton("Deny", variant: .destructive, size: .sm, mono: true, fullWidth: true, action: onDeny)
                DSButton("Approve", variant: .primary, size: .sm, mono: true, fullWidth: true, action: onApprove)
            }
        }
        .padding(13)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

#endif
