import SwiftUI

// MARK: - DSChip
// Fully spec-matched to primitives.css:14-49 + primitives.jsx:10-36.

public enum DSChipVariant {
    case `default`   // tinted soft bg (same as old .soft)
    case soft        // alias for .default — backward compat
    case solid       // neutralSoft bg, no border
    case outlined    // transparent, toned border
    case mono        // mono uppercase, surfaceSunk bg
    case monoInverse // mono uppercase, accentSoft bg
    case dashed      // transparent, dashed border
}
public enum DSChipSize    { case sm, md, lg }
public enum DSChipTone    { case accent, ok, warn, orange, danger, info, neutral }

// Keep old API names for backward compat
public typealias DSChipStyle = DSChipVariant

public struct DSChip: View {
    let label: String
    let icon: DSIcon?
    let systemImage: String?
    let tone: DSChipTone
    let variant: DSChipVariant
    let size: DSChipSize
    let leadingDot: Color?

    @Environment(\.conduitTokens) private var t

    // MARK: Legacy init (backward compat — old .solid/.soft style enum)
    public init(
        _ label: String,
        systemImage: String? = nil,
        tone: DSChipTone = .neutral,
        style: DSChipVariant = .default
    ) {
        self.label = label
        self.icon = nil
        self.systemImage = systemImage
        self.tone = tone
        self.variant = style
        self.size = .md
        self.leadingDot = nil
    }

    // MARK: Full init
    public init(
        _ label: String,
        icon: DSIcon? = nil,
        systemImage: String? = nil,
        tone: DSChipTone = .neutral,
        variant: DSChipVariant = .default,
        size: DSChipSize = .md,
        leadingDot: Color? = nil
    ) {
        self.label = label
        self.icon = icon
        self.systemImage = systemImage
        self.tone = tone
        self.variant = variant
        self.size = size
        self.leadingDot = leadingDot
    }

    public var body: some View {
        HStack(spacing: size == .sm ? 4 : 6) {
            // Leading dot
            if let dot = leadingDot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            // Leading icon (prefer DSIcon, fall back to SF Symbol)
            if let icon {
                DSIconView(icon, size: iconSize, color: fgColor)
            } else if let img = systemImage {
                Image(systemName: img).font(.system(size: iconSize))
            }
            // Label
            Text(label)
                .font(labelFont)
                .lineLimit(1)
                .fixedSize()
                .if(variant == .mono || variant == .monoInverse || false) {
                    $0.tracking(label.count > 0 ? 11 * 0.08 : 0)
                      .textCase(.uppercase)
                }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(bgColor)
        .foregroundStyle(fgColor)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(borderColor, lineWidth: variant == .outlined ? 1 : 0)
        )
        .overlay(
            Group {
                if variant == .dashed {
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(borderColor)
                }
            }
        )
    }

    // MARK: Size
    private var hPad: CGFloat {
        switch size {
        case .sm: return 6
        case .md: return 8
        case .lg: return 10
        }
    }
    private var vPad: CGFloat {
        switch size {
        case .sm: return 2
        case .md: return 3
        case .lg: return 5
        }
    }
    private var iconSize: CGFloat {
        switch size {
        case .sm: return 11
        case .md: return 12
        case .lg: return 13
        }
    }
    private var labelFont: Font {
        switch (variant, size) {
        case (.mono, _), (.monoInverse, _):
            return .dsMonoPt(11, weight: .medium)
        default:
            switch size {
            case .sm: return .dsSansPt(11, weight: .medium)
            case .md: return .dsSansPt(12, weight: .medium)
            case .lg: return .dsSansPt(13, weight: .medium)
            }
        }
    }

    // MARK: Colors from tone
    private var toneColor: Color {
        switch tone {
        case .accent:  return t.accent
        case .ok:      return t.ok
        case .warn:    return t.warn
        case .orange:  return ConduitTokens.riskOrange
        case .danger:  return t.danger
        case .info:    return t.info
        case .neutral: return t.text3
        }
    }
    private var toneSoft: Color {
        switch tone {
        case .accent:  return t.accentSoft
        case .ok:      return t.okSoft
        case .warn:    return t.warnSoft
        case .orange:  return ConduitTokens.riskOrange.opacity(0.16)
        case .danger:  return t.dangerSoft
        case .info:    return t.infoSoft
        case .neutral: return t.neutralSoft
        }
    }
    private var toneInk: Color {
        switch tone {
        case .accent:  return t.accentInk
        case .ok:      return t.ok
        case .warn:    return t.warn
        case .orange:  return ConduitTokens.riskOrange
        case .danger:  return t.danger
        case .info:    return t.info
        case .neutral: return t.text2
        }
    }

    private var bgColor: Color {
        switch variant {
        case .default, .soft: return toneSoft
        case .solid:          return t.neutralSoft
        case .outlined:       return .clear
        case .mono:           return t.surfaceSunk
        case .monoInverse:    return t.accentSoft
        case .dashed:         return .clear
        }
    }

    private var fgColor: Color {
        switch variant {
        case .default, .soft: return toneInk
        case .solid:          return t.text
        case .outlined:       return toneColor
        case .mono:           return t.text2
        case .monoInverse:    return t.accentInk
        case .dashed:         return toneColor
        }
    }

    private var borderColor: Color {
        switch variant {
        case .outlined, .dashed: return toneColor
        default: return .clear
        }
    }
}

// MARK: - View helper
private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - RiskBadge — 3-bar chart pill (spec: primitives.css:209-232)

public struct RiskBadge: View {
    let risk: Int  // 0=low, 1=medium, 2=high, 3=critical
    @Environment(\.conduitTokens) private var t

    public init(risk: Int) { self.risk = risk }

    public var body: some View {
        HStack(spacing: 5) {
            // square status dot (BLOCKS: shape + colour for colour-blind safety)
            Rectangle()
                .fill(barColor)
                .frame(width: 5, height: 5)
            Text(riskLabel)
                .font(.dsDisplayPt(10, weight: .semibold))
                .tracking(10 * 0.1)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(softColor)
        .foregroundStyle(barColor)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(barColor.opacity(0.45), lineWidth: 1)
        )
    }

    // Canonical risk → colour mapping. Delegates to the token risk ramp (Tokens.risk/riskSoft)
    // so the pill, the command quote-block tint (DSApprovalCard.riskTone) and every other risk
    // surface stay in lockstep — and so risk never borrows the brand/CTA accent (R5.1/R5.2):
    // 0 ok green · 1 warn amber · 2 orange · 3+ danger red.
    private var barColor: Color { t.risk(risk) }
    private var softColor: Color { t.riskSoft(risk) }

    private var riskLabel: String {
        switch risk {
        case 0:  return "LOW"
        case 1:  return "MED"
        case 2:  return "HIGH"
        default: return "CRIT"
        }
    }
}

// MARK: - AgentBadge (AgentState status pill — keep existing API)

public struct AgentBadge: View {
    let state: AgentState
    @Environment(\.conduitTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ state: AgentState) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            if state == .streaming || state == .thinking {
                streamingDots
            } else {
                Image(systemName: state.systemImage).font(.caption2)
            }
            Text(state.label)
                .font(.dsSansPt(12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.color(tokens: t).opacity(0.12))
        .foregroundStyle(state.color(tokens: t))
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
    }

    private var streamingDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(state.color(tokens: t))
                    .frame(width: 4, height: 4)
                    .phaseAnimator([0.3, 1.0, 0.3], trigger: state) { v, p in
                        v.opacity(reduceMotion ? 1 : p)
                    } animation: { _ in
                        reduceMotion ? nil : .easeInOut(duration: 0.5).delay(Double(i) * 0.15).repeatForever(autoreverses: false)
                    }
            }
        }
    }
}

// MARK: - StatusIcon (simple dot, backward compat)

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
    }
}
