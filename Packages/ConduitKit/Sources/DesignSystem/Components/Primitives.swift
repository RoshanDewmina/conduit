import SwiftUI

// MARK: - DSStatusDot
// primitives.css:174-193 — 8×8 circle, tone→color, optional pulse ring.

public enum DSStatusDotTone { case ok, warn, danger, info, accent, orange, off }

public struct DSStatusDot: View {
    let tone: DSStatusDotTone
    let pulse: Bool
    let size: CGFloat

    @Environment(\.conduitTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0.6

    public init(tone: DSStatusDotTone, pulse: Bool = false, size: CGFloat = 8) {
        self.tone = tone
        self.pulse = pulse
        self.size = size
    }

    public var body: some View {
        ZStack {
            if pulse {
                Circle()
                    .stroke(dotColor.opacity(pulseOpacity), lineWidth: 1.5)
                    .frame(width: size * pulseScale, height: size * pulseScale)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                            pulseScale = 2.2
                            pulseOpacity = 0
                        }
                    }
            }
            Circle().fill(dotColor).frame(width: size, height: size)
        }
    }

    private var dotColor: Color {
        switch tone {
        case .ok:      return t.ok
        case .warn:    return t.warn
        case .orange:  return ConduitTokens.riskOrange
        case .danger:  return t.danger
        case .info:    return t.info
        case .accent:  return t.accent
        case .off:     return t.text4
        }
    }
}

// MARK: - DSStatusIcon (connection glyph states)
// primitives.jsx:146-225 — 7 states rendered in 24×24 canvas.

public enum DSConnectionState {
    case connected
    case disconnected
    case reconnecting
    case agentRunning
    case awaitingApproval
    case approved
    case denied
}

public struct DSStatusIcon: View {
    let state: DSConnectionState
    let size: CGFloat

    @Environment(\.conduitTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    public init(state: DSConnectionState, size: CGFloat = 20) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        Canvas { ctx, _ in
            let scale = size / 24
            ctx.scaleBy(x: scale, y: scale)
            drawGlyph(ctx: ctx)
        }
        .frame(width: size, height: size)
        .rotationEffect(state == .reconnecting || state == .agentRunning ? .degrees(rotation) : .zero)
        .onAppear {
            guard !reduceMotion else { return }
            if state == .reconnecting || state == .agentRunning {
                withAnimation(.linear(duration: state == .reconnecting ? 1.6 : 2.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }

    private func drawGlyph(ctx: GraphicsContext) {
        let center = CGPoint(x: 12, y: 12)
        let outerR: CGFloat = 9
        let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round)

        switch state {
        case .connected:
            // Ring + filled dot
            ctx.stroke(ringPath(center: center, r: outerR), with: .color(t.ok), style: strokeStyle)
            ctx.fill(dotPath(center: center, r: 3.5), with: .color(t.ok))

        case .disconnected:
            // Dashed ring
            let dashed = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])
            ctx.stroke(ringPath(center: center, r: outerR), with: .color(t.text4), style: dashed)

        case .reconnecting:
            // Faint ring + spinning arc
            ctx.stroke(ringPath(center: center, r: outerR), with: .color(t.warn.opacity(0.25)), style: strokeStyle)
            let arc = arcPath(center: center, r: outerR, dashArray: [14, 30])
            ctx.stroke(arc, with: .color(t.warn), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        case .agentRunning:
            ctx.stroke(ringPath(center: center, r: outerR), with: .color(t.accent.opacity(0.2)), style: strokeStyle)
            let arc = arcPath(center: center, r: outerR, dashArray: [10, 50])
            ctx.stroke(arc, with: .color(t.accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.fill(dotPath(center: center, r: 2), with: .color(t.accent))

        case .awaitingApproval:
            let dashed = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 2.5])
            ctx.stroke(ringPath(center: center, r: outerR), with: .color(t.accent), style: dashed)
            // "!" glyph
            ctx.stroke(Path.line(.p(12, 8), .p(12, 13)), with: .color(t.accent),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.fill(dotPath(center: .p(12, 16.5), r: 1), with: .color(t.accent))

        case .approved:
            ctx.fill(dotPath(center: center, r: outerR), with: .color(t.ok))
            // White check
            var check = Path()
            check.move(to: .p(7, 12)); check.addLine(to: .p(10.5, 15.5)); check.addLine(to: .p(17, 8))
            ctx.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

        case .denied:
            ctx.fill(dotPath(center: center, r: outerR), with: .color(t.danger))
            // White X
            ctx.stroke(Path.line(.p(8.5, 8.5), .p(15.5, 15.5)), with: .color(.white),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            ctx.stroke(Path.line(.p(15.5, 8.5), .p(8.5, 15.5)), with: .color(.white),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private func ringPath(center: CGPoint, r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
    }
    private func dotPath(center: CGPoint, r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
    }
    private func arcPath(center: CGPoint, r: CGFloat, dashArray: [CGFloat]) -> Path {
        // Rendered as a dashed full circle; rotation drives the "spinning" effect
        let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
        return circle
    }
}

// MARK: - ProgressBar
// primitives.css:116-140

public struct DSProgressBar: View {
    let value: Double        // 0–1
    let tone: DSChipTone
    let label: String?

    @Environment(\.conduitTokens) private var t

    public init(value: Double, tone: DSChipTone = .ok, label: String? = nil) {
        self.value = value
        self.tone = tone
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let label {
                Text(label)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.surfaceSunk).frame(height: 6)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: geo.size.width * min(max(value, 0), 1), height: 6)
                        .animation(.easeInOut(duration: 0.2), value: value)
                }
            }
            .frame(height: 6)
        }
    }

    private var fillColor: Color {
        switch tone {
        case .ok:      return t.ok
        case .accent:  return t.accent
        case .info:    return t.info
        case .danger:  return t.danger
        case .warn:    return t.warn
        default:       return t.ok
        }
    }
}

// MARK: - ProgressSegmented
// primitives.css:143-154

public struct DSProgressSegmented: View {
    let total: Int
    let done: Int
    let active: Int   // index of the currently active segment

    @Environment(\.conduitTokens) private var t

    public init(total: Int, done: Int, active: Int = -1) {
        self.total = total
        self.done = done
        self.active = active
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(segColor(i))
                    .frame(height: 6)
            }
        }
    }

    private func segColor(_ i: Int) -> Color {
        if i < done { return t.ok }
        if i == active { return t.accent }
        return t.surfaceSunk
    }
}

// MARK: - ExitChip
// primitives.css:238-251

public struct DSExitChip: View {
    let code: Int
    @Environment(\.conduitTokens) private var t

    public init(code: Int) { self.code = code }

    public var body: some View {
        HStack(spacing: 4) {
            DSIconView(code == 0 ? .check : .close, size: 11,
                       color: code == 0 ? t.ok : t.danger)
            Text(code == 0 ? "exit 0" : "exit \(code)")
                .font(.dsMonoPt(11, weight: .semibold))
                .tracking(11 * 0.04)
                .opacity(0.75)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(code == 0 ? t.okSoft : t.dangerSoft)
        .foregroundStyle(code == 0 ? t.ok : t.danger)
        .clipShape(Capsule())
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - AgentIdentityBadge
// primitives.css:257-289 — pill with colored agent mark + label.

public enum AgentKey: String, Sendable {
    case claudeCode = "claude-code"
    case codex
    case kimi
    case cursor
    case opencode
    case devin
    case snippet
    case unknown

    public var markLabel: String {
        switch self {
        case .claudeCode: return "CC"
        case .codex:      return "CX"
        case .kimi:       return "KM"
        case .cursor:     return "CR"
        case .opencode:   return "OC"
        case .devin:      return "DV"
        case .snippet:    return "·"
        case .unknown:    return "?"
        }
    }

    public var markColor: Color {
        switch self {
        case .claudeCode: return Color(.sRGB, red: 0.820, green: 0.439, blue: 0.184, opacity: 1) // orange
        case .codex:      return Color(.sRGB, red: 0.153, green: 0.157, blue: 0.176, opacity: 1) // dark grey
        case .kimi:       return Color(.sRGB, red: 0.047, green: 0.541, blue: 0.545, opacity: 1)
        case .cursor:     return Color(.sRGB, red: 0.290, green: 0.196, blue: 0.816, opacity: 1) // purple
        case .opencode:   return Color(.sRGB, red: 0.153, green: 0.157, blue: 0.176, opacity: 1)
        case .devin:      return Color(.sRGB, red: 0.153, green: 0.157, blue: 0.176, opacity: 1)
        case .snippet:    return Color(.sRGB, red: 0.082, green: 0.078, blue: 0.059, opacity: 1)
        case .unknown:    return Color(.sRGB, red: 0.500, green: 0.500, blue: 0.500, opacity: 1)
        }
    }
}

public struct AgentIdentityBadge: View {
    let agent: AgentKey
    let label: String?
    let dark: Bool

    @Environment(\.conduitTokens) private var t

    public init(agent: AgentKey, label: String? = nil, dark: Bool = false) {
        self.agent = agent
        self.label = label
        self.dark = dark
    }

    public var body: some View {
        HStack(spacing: 5) {
            // Colored mark tile
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(agent.markColor)
                    .frame(width: 14, height: 14)
                Text(agent.markLabel)
                    .font(.dsMonoPt(9, weight: .bold))
                    .foregroundStyle(.white)
            }
            if let label {
                Text(label)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(dark ? Color(.sRGB, red: 0.541, green: 0.553, blue: 0.588, opacity: 1) : t.text2)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(dark ? Color.white.opacity(0.05) : t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.10) : t.border, lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - DSSearchField
// primitives.css:327-354 — pill search bar using TextField, NOT .searchable.

public struct DSSearchField: View {
    @Binding var text: String
    let placeholder: String
    let kbd: String?

    @Environment(\.conduitTokens) private var t
    @FocusState private var isFocused: Bool

    public init(text: Binding<String>, placeholder: String = "Search", kbd: String? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.kbd = kbd
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.dsMonoPt(13, weight: .medium))
                .foregroundStyle(t.accent)
            TextField(placeholder, text: $text)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .tint(t.accent)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    DSIconView(.close, size: 14, color: t.text3)
                }
                .buttonStyle(.plain)
            } else if let kbd, !isFocused {
                Text(kbd)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(t.surfaceSunk)
                    .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 38)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(isFocused ? t.accent : t.border, lineWidth: 1)
        )
    }
}

// MARK: - SectionHead
// primitives.css:360-376, composites.css:519

public struct SectionHead: View {
    let title: String
    let count: Int?
    let trailingLabel: String?

    @Environment(\.conduitTokens) private var t

    public init(_ title: String, count: Int? = nil, trailing: String? = nil) {
        self.title = title
        self.count = count
        self.trailingLabel = trailing
    }

    public var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.dsMonoPt(11, weight: .medium))
                    .tracking(11 * 0.10)
                    .textCase(.uppercase)
                    .foregroundStyle(t.text3)
                if let n = count {
                    Text("\(n)")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text4)
                }
            }
            Spacer()
            if let trailing = trailingLabel {
                Text(trailing)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - EmptyState
// primitives.css:378-389

public struct DSEmptyState: View {
    let icon: DSIcon
    let dotState: DotMatrixState?
    let title: String
    let subtitle: String?
    let action: (label: String, handler: () -> Void)?

    @Environment(\.conduitTokens) private var t

    public init(
        icon: DSIcon,
        title: String,
        subtitle: String? = nil,
        action: (label: String, handler: () -> Void)? = nil
    ) {
        self.icon = icon
        self.dotState = nil
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    /// BLOCKS state card — the dot-matrix carries the mood (idle / error / done).
    public init(
        dotMatrix: DotMatrixState,
        title: String,
        subtitle: String? = nil,
        action: (label: String, handler: () -> Void)? = nil
    ) {
        self.icon = .terminal
        self.dotState = dotMatrix
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            if let dotState {
                DotMatrixView(state: dotState, cols: 22, rows: 6, cell: 7, dot: 3)
                    .padding(.bottom, 4)
            } else {
                DSIconView(icon, size: 28, color: t.text4)
            }
            Text(title)
                .font(.dsSansPt(14, weight: .medium))
                .foregroundStyle(t.text)
            if let sub = subtitle {
                Text(sub)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let act = action {
                Button(act.label, action: act.handler)
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(t.borderStrong)
        )
    }
}

// MARK: - DSKey (keyboard key)
// primitives.css:418-437

public enum DSKeySize { case md, lg }

public struct DSKey: View {
    let label: String
    let accent: Bool
    let wide: Bool
    let size: DSKeySize

    @Environment(\.conduitTokens) private var t

    public init(_ label: String, accent: Bool = false, wide: Bool = false, size: DSKeySize = .md) {
        self.label = label
        self.accent = accent
        self.wide = wide
        self.size = size
    }

    public var body: some View {
        Text(label)
            .font(.dsMonoPt(12, weight: .medium))
            .foregroundStyle(accent ? t.termAccent : t.termText)
            .padding(.horizontal, wide ? 14 : 8)
            .frame(minWidth: size == .lg ? 48 : 34, minHeight: size == .lg ? 40 : 32)
            .background(t.termSurface2)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                    .strokeBorder(t.termBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 0, y: 2)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - Path helper (shared across this file)
private extension CGPoint {
    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x, y: y) }
}

private extension Path {
    static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path(); path.move(to: a); path.addLine(to: b); return path
    }
}
