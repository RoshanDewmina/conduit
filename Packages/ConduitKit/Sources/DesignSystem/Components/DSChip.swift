import SwiftUI

public enum DSChipTone { case accent, ok, warn, danger, info, neutral }
public enum DSChipStyle { case solid, soft }

public struct DSChip: View {
    let label: String
    let systemImage: String?
    let tone: DSChipTone
    let style: DSChipStyle

    @Environment(\.conduitTokens) private var t

    public init(
        _ label: String,
        systemImage: String? = nil,
        tone: DSChipTone = .neutral,
        style: DSChipStyle = .soft
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let img = systemImage {
                Image(systemName: img).font(.caption2)
            }
            Text(label).font(.caption2.weight(.semibold)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(bg)
        .foregroundStyle(fg)
        .clipShape(Capsule())
    }

    private var baseColor: Color {
        switch tone {
        case .accent:  return t.accent
        case .ok:      return t.ok
        case .warn:    return t.warn
        case .danger:  return t.danger
        case .info:    return t.info
        case .neutral: return t.text3
        }
    }

    private var bg: Color {
        style == .solid ? baseColor : baseColor.opacity(0.15)
    }

    private var fg: Color {
        style == .solid ? .white : baseColor
    }
}

// MARK: - Risk badge

public struct RiskBadge: View {
    let risk: Int  // 0–3 (low/medium/high/critical)
    @Environment(\.conduitTokens) private var t

    public init(risk: Int) { self.risk = risk }

    public var body: some View {
        DSChip(label, tone: tone, style: .soft)
    }

    private var label: String {
        switch risk {
        case 0:  "low"
        case 1:  "medium"
        case 2:  "high"
        default: "critical"
        }
    }

    private var tone: DSChipTone {
        switch risk {
        case 0:  .ok
        case 1:  .warn
        case 2:  .danger
        default: .danger
        }
    }
}

// MARK: - AgentBadge

public struct AgentBadge: View {
    let state: AgentState
    @Environment(\.conduitTokens) private var t

    public init(_ state: AgentState) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            if state == .streaming || state == .thinking {
                streamingDots
            } else {
                Image(systemName: state.systemImage).font(.caption2)
            }
            Text(state.label).font(.caption2.weight(.medium)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.color(tokens: t).opacity(0.12))
        .foregroundStyle(state.color(tokens: t))
        .clipShape(Capsule())
    }

    private var streamingDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(state.color(tokens: t))
                    .frame(width: 4, height: 4)
                    .phaseAnimator([0.3, 1.0, 0.3], trigger: state) { view, phase in
                        view.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.5).delay(Double(i) * 0.15).repeatForever(autoreverses: false)
                    }
            }
        }
    }
}

// MARK: - StatusIcon

public struct StatusIcon: View {
    let state: AgentState
    let size: CGFloat
    @Environment(\.conduitTokens) private var t

    public init(_ state: AgentState, size: CGFloat = 8) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(state.color(tokens: t))
            .frame(width: size, height: size)
            .overlay {
                if state == .streaming || state == .thinking {
                    Circle()
                        .stroke(state.color(tokens: t).opacity(0.4), lineWidth: 2)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulseScale)
                }
            }
    }

    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0.8
}
