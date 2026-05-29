import SwiftUI

// MARK: - PixelBox
// 3×3 grid, per-cell independent random delay/duration, state-driven animations.
// State colors from STATE_META (agent-status-bar.jsx:45-81).

public struct PixelBox: View {
    private enum Mode { case state(AgentState); case color(Color) }
    private let mode: Mode
    let size: CGFloat
    let gap: CGFloat

    public init(state: AgentState = .offline, size: CGFloat = 5, gap: CGFloat = 1) {
        self.mode = .state(state)
        self.size = size
        self.gap = gap
    }

    /// Explicit-color glowing grid — used by the onboarding logo
    /// (`PixelBox(color: t.accent, size: 64)` → a pulsing accent logo).
    public init(color: Color, size: CGFloat = 5, gap: CGFloat = 1.5) {
        self.mode = .color(color)
        self.size = size
        self.gap = gap
    }

    private var cellColor: Color {
        switch mode {
        case .color(let c):  return c
        case .state(let s):  return Self.stateColor(s)
        }
    }

    /// offline = static dim, done = static solid; every other state pulses + glows.
    private var animates: Bool {
        switch mode {
        case .color:        return true
        case .state(let s): return s != .offline && s != .done
        }
    }

    public var body: some View {
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        PixelCell(
                            color: cellColor,
                            animates: animates,
                            cellIndex: row * 3 + col,
                            cellSize: size
                        )
                    }
                }
            }
        }
    }

    static func stateColor(_ state: AgentState) -> Color {
        switch state {
        case .thinking:  return Color(.sRGB, red: 0.820, green: 0.439, blue: 0.184, opacity: 1) // orange
        case .streaming: return Color(.sRGB, red: 0.318, green: 0.573, blue: 0.929, opacity: 1) // blue
        case .approval:  return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1) // amber
        case .done:      return Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1) // green
        case .error:     return Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1) // red
        case .offline:   return Color(.sRGB, red: 0.118, green: 0.133, blue: 0.157, opacity: 1) // dim #1e2228
        }
    }
}

// MARK: - Individual cell (continuously pulses + glows when animated)

private struct PixelCell: View {
    let color: Color
    let animates: Bool
    let cellIndex: Int
    let cellSize: CGFloat

    @State private var lit = false

    // Stable per-cell delay + duration seeded from index → out-of-phase shimmer
    // (mirrors agent-status-bar.jsx makeCells random --del / --dur).
    private var delay: Double { Double(cellIndex * 7 % 15) * 0.1 }            // 0–1.4s
    private var duration: Double { 0.7 + Double(cellIndex * 3 % 9) * 0.095 }  // 0.7–1.55s

    var body: some View {
        RoundedRectangle(cornerRadius: max(0.5, cellSize * 0.08), style: .continuous)
            .fill(color)
            .frame(width: cellSize, height: cellSize)
            .opacity(animates ? (lit ? 1.0 : 0.22) : 0.9)
            .shadow(color: animates && lit ? color.opacity(0.85) : .clear,
                    radius: animates && lit ? cellSize * 0.28 : 0)
            .onAppear {
                guard animates else { return }
                withAnimation(
                    .easeInOut(duration: duration)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) { lit = true }
            }
    }
}

// MARK: - TickBars (state-driven variant added)

public struct TickBars: View {
    let values: [Double]
    let barColor: Color
    let barWidth: CGFloat
    let spacing: CGFloat
    let maxHeight: CGFloat

    // Legacy init (values-based, keeps old API)
    public init(
        values: [Double],
        barColor: Color = .white.opacity(0.7),
        barWidth: CGFloat = 2,
        spacing: CGFloat = 1,
        maxHeight: CGFloat = 20
    ) {
        self.values = values
        self.barColor = barColor
        self.barWidth = barWidth
        self.spacing = spacing
        self.maxHeight = maxHeight
    }

    // State-driven convenience
    public init(
        state: AgentState,
        count: Int = 16,
        barWidth: CGFloat = 2,
        spacing: CGFloat = 1.5,
        maxHeight: CGFloat = 20
    ) {
        let filledRatio: Double = switch state {
            case .done: 1.0
            case .offline: 0.0
            default: 0.58
        }
        let stateColor: Color = switch state {
            case .thinking:  Color(.sRGB, red: 0.820, green: 0.439, blue: 0.184, opacity: 1)
            case .streaming: Color(.sRGB, red: 0.318, green: 0.573, blue: 0.929, opacity: 1)
            case .approval:  Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1)
            case .done:      Color(.sRGB, red: 0.247, green: 0.753, blue: 0.435, opacity: 1)
            case .error:     Color(.sRGB, red: 0.875, green: 0.353, blue: 0.290, opacity: 1)
            case .offline:   Color(.sRGB, red: 0.373, green: 0.357, blue: 0.329, opacity: 1)
        }

        var vals = [Double]()
        for i in 0..<count {
            let h = sin(Double(i) * 0.72) * 0.4 + 0.6  // organic height variation
            let filled = Double(i) < Double(count) * filledRatio
            vals.append(filled ? h : 0.18)
        }
        self.values = vals
        self.barColor = stateColor
        self.barWidth = barWidth
        self.spacing = spacing
        self.maxHeight = maxHeight
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(values.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor)
                    .frame(width: barWidth, height: max(2, values[i] * maxHeight))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
    }
}
