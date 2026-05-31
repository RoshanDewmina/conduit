import SwiftUI

// MARK: - PixelBox
// 3×3 grid with a distinct *emotional* animation per agent state, driven by a
// single per-box TimelineView so every cell is a pure function of elapsed time.
// This makes motion continuous and intentional rather than a discrete toggle:
//   • thinking  → evolving: colors cycle through a warm gradient, sweeping the grid
//   • streaming → flowing:  a brightness wave travels diagonally (data in motion)
//   • approval  → breathing: calm synchronized pulse (patient, attention-seeking)
//   • error     → glitching: stutter, dead pixels, corruption spikes, tearing
//   • done/offline → still

public struct PixelBox: View {
    private enum Mode { case state(AgentState); case color(Color) }
    private let mode: Mode
    let size: CGFloat
    let gap: CGFloat
    /// When > 1, each of the 9 cells is itself rendered as a `subdivisions ×
    /// subdivisions` grid of micro-cells that shimmer on smooth, desynced waves
    /// — a self-similar "pixels made of pixels" effect. Sub-cells animate even
    /// in otherwise-still states, so the grid is always gently alive. Default 1
    /// keeps the original flat behaviour for existing call sites.
    let subdivisions: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: AgentState = .offline, size: CGFloat = 5, gap: CGFloat = 1, subdivisions: Int = 1) {
        self.mode = .state(state)
        self.size = size
        self.gap = gap
        self.subdivisions = max(1, subdivisions)
    }

    /// Explicit-color glowing grid — used by the onboarding logo
    /// (`PixelBox(color: t.accent, size: 64)` → a breathing accent logo).
    public init(color: Color, size: CGFloat = 5, gap: CGFloat = 1.5, subdivisions: Int = 1) {
        self.mode = .color(color)
        self.size = size
        self.gap = gap
        self.subdivisions = max(1, subdivisions)
    }

    private var behavior: CellBehavior {
        // When Reduce Motion is enabled, collapse all animated states to their
        // still equivalent so the grid is static (no TimelineView, no flicker).
        if reduceMotion {
            switch mode {
            case .color(let c): return .still(RGB(c), opacity: 0.85)
            case .state(let s):
                switch s {
                case .thinking:  return .still(RGB(0.82, 0.44, 0.18), opacity: 0.90)
                case .streaming: return .still(RGB.blue,               opacity: 0.90)
                case .approval:  return .still(RGB.amber,              opacity: 0.90)
                case .error:     return .still(RGB.red,                opacity: 0.90)
                case .done:      return .still(RGB.green,              opacity: 0.92)
                case .offline:   return .still(RGB.offline,            opacity: 0.90)
                }
            }
        }
        switch mode {
        case .color(let c):  return .breathing(RGB(c))
        case .state(let s):
            switch s {
            case .thinking:  return .evolving
            case .streaming: return .flowing
            case .approval:  return .breathing(RGB.amber)
            case .error:     return .glitching
            case .done:      return .still(RGB.green, opacity: 0.92)
            case .offline:   return .still(RGB.offline, opacity: 0.9)
            }
        }
    }

    public var body: some View {
        let beh = behavior
        // Subdivided grids always animate (the micro-cells shimmer even when the
        // macro state is still), so drive a TimelineView whenever either applies.
        // Reduce Motion collapses behaviour to still(), which never enters the
        // animated path and also disables sub-cell shimmer.
        let effectiveSubs = reduceMotion ? 1 : subdivisions
        Group {
            if beh.isAnimated || effectiveSubs > 1 {
                TimelineView(.animation) { tl in
                    grid(behavior: beh, subdivisions: effectiveSubs, now: tl.date.timeIntervalSinceReferenceDate)
                }
            } else {
                grid(behavior: beh, subdivisions: effectiveSubs, now: 0)
            }
        }
        // PixelBox is decorative status art — VoiceOver should skip it and read
        // the containing element's accessibility label instead.
        .accessibilityHidden(true)
    }

    private func grid(behavior: CellBehavior, subdivisions: Int, now: TimeInterval) -> some View {
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        PixelCell(
                            behavior: behavior,
                            cellIndex: row * 3 + col,
                            cellSize: size,
                            gap: gap,
                            subdivisions: subdivisions,
                            now: now
                        )
                    }
                }
            }
        }
    }

    public static func stateColor(_ state: AgentState) -> Color {
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

// MARK: - Cell behavior

private enum CellBehavior {
    case evolving                       // thinking
    case flowing                        // streaming
    case breathing(RGB)                 // approval / explicit-color logo
    case glitching                      // error
    case still(RGB, opacity: Double)    // done / offline

    var isAnimated: Bool {
        if case .still = self { return false }
        return true
    }
}

// MARK: - Lightweight RGB for cross-platform color math (no UIKit dependency)

private struct RGB {
    let r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    /// Best-effort extraction of sRGB components from a SwiftUI Color.
    /// Falls back to the resolved values where available; otherwise mid-grey.
    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.r = Double(resolved.red)
        self.g = Double(resolved.green)
        self.b = Double(resolved.blue)
    }

    func color(_ opacity: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    static let amber   = RGB(0.820, 0.604, 0.180)
    static let green   = RGB(0.173, 0.608, 0.349)
    static let offline = RGB(0.118, 0.133, 0.157)
    static let blue    = RGB(0.318, 0.573, 0.929)
    static let blueLit = RGB(0.62, 0.80, 1.0)
    static let red     = RGB(0.80, 0.20, 0.16)
    static let corrupt = RGB(0.98, 0.86, 0.86)   // hot near-white for glitch spikes
}

private func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
}
private func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }
private func frac(_ x: Double) -> Double { x - floor(x) }
/// Deterministic value-noise in [0,1) — no Foundation randomness needed.
private func hash(_ x: Double) -> Double { frac(sin(x) * 43758.5453) }

/// Sample a looping multi-stop gradient at `phase`, eased between stops.
private func sampleGradient(_ stops: [RGB], _ phase: Double) -> RGB {
    let p = frac(phase)
    let scaled = p * Double(stops.count)
    let i = Int(scaled) % stops.count
    let f = smoothstep(scaled - floor(scaled))
    return lerp(stops[i], stops[(i + 1) % stops.count], f)
}

// Warm, energetic palette for "thinking" — ember → gold → coral → magenta, looping.
private let evolveStops: [RGB] = [
    RGB(0.82, 0.44, 0.18),  // ember orange
    RGB(0.94, 0.68, 0.22),  // gold
    RGB(0.88, 0.36, 0.30),  // coral
    RGB(0.74, 0.34, 0.62),  // soft magenta
]

// MARK: - Individual cell

private struct PixelCell: View {
    let behavior: CellBehavior
    let cellIndex: Int
    let cellSize: CGFloat
    var gap: CGFloat = 1
    var subdivisions: Int = 1
    let now: TimeInterval

    private var row: Int { cellIndex / 3 }
    private var col: Int { cellIndex % 3 }
    private var diag: Double { Double(row + col) }   // 0…4, for diagonal sweeps

    private struct Look {
        var rgb: RGB
        var opacity: Double
        var glow: CGFloat
        var dx: CGFloat = 0
        var dy: CGFloat = 0
    }

    var body: some View {
        if subdivisions <= 1 {
            soloCell
        } else {
            subdividedCell
        }
    }

    private var soloCell: some View {
        let look = computeLook()
        return RoundedRectangle(cornerRadius: max(0.5, cellSize * 0.08), style: .continuous)
            .fill(look.rgb.color(look.opacity))
            .frame(width: cellSize, height: cellSize)
            .shadow(color: look.glow > 0 ? look.rgb.color(0.85) : .clear, radius: look.glow)
            .offset(x: look.dx, y: look.dy)
    }

    // Each cell becomes a sub-grid whose micro-cells shimmer around the cell's
    // base look on two desynced sine waves — continuous, never strobing.
    private var subdividedCell: some View {
        let base = computeLook()
        let n = subdivisions
        // Sub-cells are tighter than the macro gap, so the 3×3 structure always
        // reads first and the sub-pixels stay a subtle inner texture.
        let subGap = max(0.5, gap * 0.34)
        let subSize = (cellSize - subGap * CGFloat(n - 1)) / CGFloat(n)
        return Grid(horizontalSpacing: subGap, verticalSpacing: subGap) {
            ForEach(0..<n, id: \.self) { sr in
                GridRow {
                    ForEach(0..<n, id: \.self) { sc in
                        let look = subLook(base: base, sr: sr, sc: sc, n: n)
                        RoundedRectangle(cornerRadius: max(0.4, subSize * 0.18), style: .continuous)
                            .fill(look.rgb.color(look.opacity))
                            .frame(width: subSize, height: subSize)
                            .shadow(color: look.glow > 0 ? look.rgb.color(0.7) : .clear, radius: look.glow)
                    }
                }
            }
        }
        .frame(width: cellSize, height: cellSize)
        .offset(x: base.dx, y: base.dy)
    }

    private func subLook(base: Look, sr: Int, sc: Int, n: Int) -> Look {
        let subIdx = Double(sr * n + sc)
        let subDiag = Double(sr + sc)
        // Two slow, mutually-prime-ish waves → organic, non-repeating shimmer.
        let w1 = sin(now * 2.1 + Double(cellIndex) * 0.8 + subDiag * 1.15)
        let w2 = sin(now * 1.3 + subIdx * 0.55 + Double(cellIndex) * 0.31)
        let s = 0.5 + 0.25 * w1 + 0.25 * w2                       // 0…1, smooth
        // Subtle: sub-cells only breathe within ~80–100% of the cell's opacity
        // and barely shift hue, so the inner texture is gentle, not busy.
        let opacity = min(1.0, max(0.30, base.opacity * (0.80 + 0.20 * s)))
        let rgb = lerp(base.rgb, lerp(base.rgb, RGB.corrupt, 0.08), s)
        return Look(rgb: rgb, opacity: opacity, glow: base.glow * 0.35 * s)
    }

    private func computeLook() -> Look {
        switch behavior {
        case .still(let rgb, let opacity):
            return Look(rgb: rgb, opacity: opacity, glow: 0)

        case .evolving:
            // Color sweeps diagonally across the grid and evolves over time.
            let phase = now / 3.1 + diag * 0.07
            let rgb = sampleGradient(evolveStops, phase)
            // Gentle, slightly desynced breathing so it feels alive, not strobing.
            let b = 0.5 + 0.5 * sin(now * 1.25 + Double(cellIndex) * 0.32)
            let opacity = 0.68 + 0.32 * b
            return Look(rgb: rgb, opacity: opacity, glow: cellSize * 0.55 * b)

        case .flowing:
            // A brightness wave travels along the diagonal — data in motion.
            let wave = sin(now * 3.0 - diag * 0.95)
            let b = 0.5 + 0.5 * wave
            let rgb = lerp(RGB.blue, RGB.blueLit, b)
            let opacity = 0.32 + 0.68 * b
            return Look(rgb: rgb, opacity: opacity, glow: cellSize * 0.65 * b)

        case .breathing(let base):
            // Calm, near-synchronized swell (a heartbeat). Tiny per-cell offset for life.
            let b = 0.5 + 0.5 * sin(now * 1.55 + Double(cellIndex) * 0.05)
            let rgb = lerp(base, lerp(base, RGB.corrupt, 0.18), b) // brighten slightly at peak
            let opacity = 0.40 + 0.60 * b
            return Look(rgb: rgb, opacity: opacity, glow: cellSize * 0.34 * b)

        case .glitching:
            return glitchLook()
        }
    }

    // error — broken & urgent. Time is quantized so values *hold then jump* (stutter),
    // with dead pixels, corruption flashes, and occasional whole-grid horizontal tearing.
    private func glitchLook() -> Look {
        let step = floor(now * 13)                       // ~13 Hz stutter
        let h1 = hash(step + Double(cellIndex) * 1.73)
        let h2 = hash(step * 1.7 + Double(cellIndex) * 3.31 + 9.1)

        // Whole-grid tear: every so often the row shears sideways.
        let tearOn = hash(step * 0.91 + 4.2) > 0.86
        let tearDX: CGFloat = tearOn ? CGFloat((hash(step + 7.3) - 0.5) * Double(cellSize) * 0.8) : 0

        var look: Look
        if h1 > 0.80 {
            // Bright corruption spike — hot, near-white, jumps position.
            let rgb = lerp(RGB.red, RGB.corrupt, 0.65)
            look = Look(rgb: rgb, opacity: 0.95, glow: cellSize * 0.40,
                        dx: CGFloat((h2 - 0.5) * Double(cellSize) * 0.45),
                        dy: CGFloat((hash(step + Double(cellIndex)) - 0.5) * Double(cellSize) * 0.3))
        } else if h1 < 0.12 {
            // Dead pixel — nearly black, the grid looks broken.
            look = Look(rgb: lerp(RGB.red, RGB.offline, 0.85), opacity: 0.06, glow: 0)
        } else {
            // Unstable baseline — dim, jittering red.
            let op = 0.22 + 0.18 * h2
            look = Look(rgb: RGB.red, opacity: op, glow: cellSize * 0.08 * h2)
        }
        look.dx += tearDX
        return look
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
