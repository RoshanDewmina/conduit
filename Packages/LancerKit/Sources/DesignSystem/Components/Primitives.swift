import SwiftUI

// MARK: - DSStatusDot
// primitives.css:174-193 — 8×8 circle, tone→color, optional pulse ring.

public enum DSStatusDotTone { case ok, warn, danger, info, accent, orange, off }

public struct DSStatusDot: View {
    let tone: DSStatusDotTone
    let pulse: Bool
    let size: CGFloat
    let accessibilityLabel: String?

    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0.6

    public init(tone: DSStatusDotTone, pulse: Bool = false, size: CGFloat = 8, accessibilityLabel: String? = nil) {
        self.tone = tone
        self.pulse = pulse
        self.size = size
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        // The solid dot owns the layout footprint (size×size). The pulse ring is an
        // overlay drawn with scaleEffect, so its growth is a render transform that
        // never resizes the parent — otherwise the expanding ring reflows whatever
        // band/row contains the dot once per cycle ("expand and reset" bug).
        Circle()
            .fill(dotColor)
            .frame(width: size, height: size)
            .overlay {
                if pulse {
                    Circle()
                        .stroke(dotColor.opacity(pulseOpacity), lineWidth: 1.5)
                        .scaleEffect(pulseScale)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                                pulseScale = 2.2
                                pulseOpacity = 0
                            }
                        }
                }
            }
            .accessibilityLabel(accessibilityLabel ?? toneAccessibilityLabel)
    }

    private var toneAccessibilityLabel: String {
        switch tone {
        case .ok: return "Status: OK"
        case .warn: return "Status: warning"
        case .danger: return "Status: error"
        case .info: return "Status: informational"
        case .accent: return "Status: active"
        case .orange: return "Status: attention needed"
        case .off: return "Status: inactive"
        }
    }

    private var dotColor: Color {
        switch tone {
        case .ok:      return t.ok
        case .warn:    return t.warn
        case .orange:  return LancerTokens.riskOrange
        case .danger:  return t.danger
        case .info:    return t.info
        case .accent:  return t.accent
        case .off:     return t.text4
        }
    }
}

// MARK: - ExitChip
// primitives.css:238-251

public struct DSExitChip: View {
    let code: Int
    @Environment(\.lancerTokens) private var t

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

// MARK: - DSSearchField
// primitives.css:327-354 — pill search bar using TextField, NOT .searchable.

public struct DSSearchField: View {
    @Binding var text: String
    let placeholder: String
    let kbd: String?

    @Environment(\.lancerTokens) private var t
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

// MARK: - EmptyState
// primitives.css:378-389

public struct DSEmptyState: View {
    let icon: DSIcon
    let dotState: DotMatrixState?
    let title: String
    let subtitle: String?
    let action: (label: String, handler: () -> Void)?

    @Environment(\.lancerTokens) private var t

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
