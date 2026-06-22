#if os(iOS)
import SwiftUI
import LancerCore

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
    let onOpenDetails: () -> Void

    @Environment(\.lancerTokens) private var t
    @State private var showsCommand = false

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
        onApprove: @escaping () -> Void,
        onOpenDetails: @escaping () -> Void = {}
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
        self.onOpenDetails = onOpenDetails
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                Spacer()
                Text(riskLabel)
                    .font(.dsSansPt(12, weight: .semibold))
                    .foregroundStyle(t.risk(risk))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(t.riskSoft(risk), in: Capsule())
                Text(timeLabel)
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            }

            Text(requestTitle)
                .font(.dsSansPt(19, weight: .semibold))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(requestSummary)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)

            if isCritical {
                Label("Face ID required to approve", systemImage: "faceid")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.warn)
            }

            if let commandPreview {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsCommand.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(.degrees(showsCommand ? 90 : 0))
                            Text(showsCommand ? "Hide command" : "Show command")
                                .font(.dsSansPt(14, weight: .medium))
                            Spacer()
                            Text("Technical detail")
                                .font(.dsSansPt(12))
                                .foregroundStyle(t.text3)
                        }
                        .foregroundStyle(t.text2)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)

                    if showsCommand {
                        Text(commandPreview)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                            .padding(.top, 10)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(role: .destructive, action: onDeny) {
                    Text("Deny")
                        .font(.dsSansPt(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(t.danger)
                        .background(t.surface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(t.danger.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onApprove) {
                    Text("Approve")
                        .font(.dsSansPt(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(t.accentFg)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: onOpenDetails) {
                Label("Review details", systemImage: "chevron.right")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.text3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review details for \(agentName)'s request")
        }
        .padding(20)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var requestTitle: String {
        question ?? "Review this action before \(agentName) continues."
    }

    private var requestSummary: String {
        guard let toolName, !toolName.isEmpty else {
            return "This request is paused until you make a decision."
        }
        return "\(agentName) wants permission to use \(toolName)."
    }

    private var commandPreview: String? {
        if let args, !args.isEmpty, args != toolName {
            return args
        }
        return toolName
    }

    private var riskLabel: String {
        switch risk {
        case 0: "Low risk"
        case 1: "Medium risk"
        case 2: "High risk"
        default: "Critical"
        }
    }
}

#endif
