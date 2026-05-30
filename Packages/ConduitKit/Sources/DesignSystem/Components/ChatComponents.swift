import SwiftUI

// MARK: - MessageBubble (msg2)
// agent-chat-v2.css:250-291

public enum MessageSender { case user, agent }

public struct DSMessageBubble: View {
    let text: String
    let sender: MessageSender
    let meta: String?      // e.g. "2:34 PM"
    let who: String?       // agent display name
    let isStreaming: Bool

    @Environment(\.conduitTokens) private var t

    public init(
        _ text: String,
        sender: MessageSender,
        meta: String? = nil,
        who: String? = nil,
        isStreaming: Bool = false
    ) {
        self.text = text
        self.sender = sender
        self.meta = meta
        self.who = who
        self.isStreaming = isStreaming
    }

    public var body: some View {
        HStack {
            if sender == .user { Spacer(minLength: 48) }
            VStack(alignment: sender == .user ? .trailing : .leading, spacing: 3) {
                // Bubble
                HStack(spacing: 0) {
                    Text(text)
                        .font(.dsSansPt(14))
                        .foregroundStyle(sender == .user ? t.bg : t.text)
                        .lineSpacing(14 * 0.5)
                        .fixedSize(horizontal: false, vertical: true)
                    if isStreaming && sender == .agent {
                        // Blinking caret
                        Rectangle()
                            .fill(t.accent)
                            .frame(width: 2, height: 16)
                            .padding(.leading, 2)
                            .blinkingCaret()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(sender == .user ? t.text : t.surface)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .overlay(
                    sender == .agent
                    ? RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                    : nil
                )

                // Meta row
                if meta != nil || who != nil {
                    HStack(spacing: 4) {
                        if let w = who {
                            Text(w).fontWeight(.medium)
                        }
                        if let m = meta {
                            Text(m)
                        }
                    }
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
                }
            }
            if sender == .agent { Spacer(minLength: 48) }
        }
    }
}

private extension View {
    func blinkingCaret() -> some View {
        modifier(BlinkingCaretModifier())
    }
}

private struct BlinkingCaretModifier: ViewModifier {
    @State private var visible = true
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0).onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) { visible = false }
        }
    }
}

// MARK: - SystemEvent & ChatMarker
// agent-chat-v2.css:412-435

public struct DSSystemEvent: View {
    let label: String
    @Environment(\.conduitTokens) private var t

    public init(_ label: String) { self.label = label }

    public var body: some View {
        Text(label)
            .font(.dsMonoPt(11))
            .foregroundStyle(t.text3)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
    }
}

public struct DSChatMarker: View {
    let label: String
    @Environment(\.conduitTokens) private var t

    public init(_ label: String) { self.label = label }

    public var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(t.border).frame(height: 1)
            Text(label)
                .font(.dsMonoPt(10))
                .tracking(10 * 0.08)
                .textCase(.uppercase)
                .foregroundStyle(t.text4)
                .fixedSize()
            Rectangle().fill(t.border).frame(height: 1)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - ApprovalCard
// composites.css:232-279

public struct DSApprovalCard: View {
    let agentKey: AgentKey
    let risk: Int
    let timeLabel: String
    let agentName: String
    let action: String
    let hostLabel: String       // "hostname · /path"
    let command: String?
    let onViewDiff: (() -> Void)?
    let onDeny: () -> Void
    let onAllowAlways: () -> Void
    let onApprove: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        agentKey: AgentKey,
        risk: Int,
        timeLabel: String,
        agentName: String,
        action: String,
        hostLabel: String,
        command: String? = nil,
        onViewDiff: (() -> Void)? = nil,
        onDeny: @escaping () -> Void,
        onAllowAlways: @escaping () -> Void,
        onApprove: @escaping () -> Void
    ) {
        self.agentKey = agentKey
        self.risk = risk
        self.timeLabel = timeLabel
        self.agentName = agentName
        self.action = action
        self.hostLabel = hostLabel
        self.command = command
        self.onViewDiff = onViewDiff
        self.onDeny = onDeny
        self.onAllowAlways = onAllowAlways
        self.onApprove = onApprove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Head
            HStack {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                RiskBadge(risk: risk)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            // Description
            HStack(spacing: 4) {
                Text(agentName).fontWeight(.semibold)
                Text("wants to \(action) on")
                Text(hostLabel)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            }
            .font(.dsSansPt(14))
            .foregroundStyle(t.text)

            // Command block
            if let cmd = command {
                DSQuoteBlock(title: "bash", tags: riskTags, message: cmd, tone: riskTone)
            }

            // Actions row
            HStack(spacing: 8) {
                if let viewDiff = onViewDiff {
                    DSButton("VIEW DIFF", variant: .ghost, size: .sm, mono: true, action: viewDiff)
                }
                Spacer()
                DSButton("DENY", variant: .destructive, size: .sm, mono: true, action: onDeny)
                DSButton("ALLOW ALWAYS", variant: .secondary, size: .sm, mono: true, action: onAllowAlways)
                DSButton("APPROVE", variant: .primary, size: .sm, mono: true, action: onApprove)
            }
        }
        .padding(16)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private var riskTone: DSChipTone {
        switch risk {
        case 0:  return .ok
        case 1:  return .warn
        case 2:  return .accent
        default: return .danger
        }
    }

    private var riskTags: [String] {
        switch risk {
        case 0:  return []
        case 1:  return ["RISK"]
        case 2:  return ["DESTRUCTIVE"]
        default: return ["CRITICAL"]
        }
    }
}
