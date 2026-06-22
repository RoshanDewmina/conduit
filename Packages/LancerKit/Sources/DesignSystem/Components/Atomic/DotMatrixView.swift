import SwiftUI

// MARK: - DotMatrixView — the BLOCKS signature status field
// A single animated dot-matrix indicator with a distinct motion per state. Replaces spinners,
// progress bars and per-session activity glyphs. Faithful port of the design handoff's `dmField`
// engine (lib/dotmatrix.jsx), driven by TimelineView(.animation) over a SwiftUI Canvas.

public enum DotMatrixState: String, Sendable, CaseIterable, Equatable {
    case idle        // connected · nothing running
    case connecting  // ssh handshake · attaching tmux
    case thinking    // agent reasoning · awaiting model
    case working     // command / agent running
    case error       // command failed · needs you
    case done        // completed successfully

    /// Accent colour that reads the state at a glance (matches DM_STATES in the handoff).
    public var tint: Color {
        switch self {
        case .idle:       return Color(.sRGB, red: 0.337, green: 0.349, blue: 0.388, opacity: 1) // grey
        case .connecting: return Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1) // blue
        case .thinking:   return Color(.sRGB, red: 0.494, green: 0.310, blue: 0.710, opacity: 1) // violet
        case .working:    return Color(.sRGB, red: 0.886, green: 0.400, blue: 0.173, opacity: 1) // ember
        case .error:      return Color(.sRGB, red: 0.878, green: 0.325, blue: 0.247, opacity: 1) // red
        case .done:       return Color(.sRGB, red: 0.212, green: 0.761, blue: 0.420, opacity: 1) // green
        }
    }
}

public struct DotMatrixView: View {
    public var state: DotMatrixState
    public var cols: Int
    public var rows: Int
    public var cell: CGFloat
    public var dot: CGFloat
    public var glow: Bool
    public var speed: Double

    @State private var start = Date()

    public init(state: DotMatrixState = .idle,
                cols: Int = 20, rows: Int = 6,
                cell: CGFloat = 7, dot: CGFloat = 3,
                glow: Bool = true, speed: Double = 1) {
        self.state = state
        self.cols = cols
        self.rows = rows
        self.cell = cell
        self.dot = dot
        self.glow = glow
        self.speed = speed
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, _ in
                let t = timeline.date.timeIntervalSince(start) * speed
                for y in 0..<rows {
                    for x in 0..<cols {
                        let f = Self.field(state, x, y, t, cols, rows)
                        let a = clampD(f.b)
                        if a < 0.04 { continue }
                        let px = CGFloat(x) * cell + cell / 2
                        let py = CGFloat(y) * cell + cell / 2
                        let sz = dot * (0.6 + 0.4 * a)
                        if glow && a > 0.55 {
                            let hr = sz * 1.8
                            let halo = CGRect(x: px - hr / 2, y: py - hr / 2, width: hr, height: hr)
                            ctx.fill(Path(ellipseIn: halo),
                                     with: .color(Color(.sRGB, red: f.rgb.0, green: f.rgb.1, blue: f.rgb.2, opacity: a * 0.22)))
                        }
                        let rect = CGRect(x: px - sz / 2, y: py - sz / 2, width: sz, height: sz)
                        ctx.fill(Path(ellipseIn: rect),
                                 with: .color(Color(.sRGB, red: f.rgb.0, green: f.rgb.1, blue: f.rgb.2, opacity: a)))
                    }
                }
            }
            .frame(width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
        }
        .onChange(of: state) { _, _ in start = Date() }
        .accessibilityHidden(true)
    }

    // MARK: per-state brightness + colour field (port of dmField)

    private typealias RGB = (Double, Double, Double)

    private static let grey:  RGB = (0.337, 0.349, 0.388)
    private static let blue:  RGB = (0.184, 0.263, 1.000)
    private static let green: RGB = (0.212, 0.761, 0.420)
    private static let red:   RGB = (0.878, 0.325, 0.247)
    private static let spec: [RGB] = [
        (0.784, 0.259, 0.231), (0.886, 0.400, 0.173), (0.941, 0.573, 0.180),
        (0.949, 0.757, 0.306), (0.780, 0.482, 0.651), (0.494, 0.310, 0.710),
        (0.329, 0.376, 0.784),
    ]

    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    private static func field(_ state: DotMatrixState, _ x: Int, _ y: Int,
                              _ t: Double, _ cols: Int, _ rows: Int) -> (b: Double, rgb: RGB) {
        let X = Double(x), Y = Double(y)
        switch state {
        case .idle:
            let b = 0.07 + 0.05 * sin(t * 0.85 + X * 0.5 + Y * 0.42)
            return (b, grey)
        case .connecting:
            let span = Double(cols) + 8
            let pos = (t * 0.62).truncatingRemainder(dividingBy: 1) * span - 4
            let d = abs(X - pos)
            let tail = X < pos ? clampD(1 - (pos - X) / 6) * 0.35 : 0
            let b = clampD(max(1 - d / 2.2, tail) * 0.95, 0.05, 1)
            return (b, blue)
        case .thinking:
            let n = sin(X * 1.27 + t * 1.9) * sin(Y * 1.63 - t * 1.35) * 0.5 + 0.5
            let b = 0.1 + 0.82 * pow(n, 2.6)
            var rgb = mix(blue, spec[5], clampD(Y / Double(max(1, rows - 1))))
            let pop = sin(X * 5.1 + Y * 3.3 + t * 0.6)
            if b > 0.62 && pop > 0.8 { rgb = spec[(x * 3 + y) % 7] }
            return (b, rgb)
        case .working:
            let prog = (t * 0.34).truncatingRemainder(dividingBy: 1.18)
            let frac = cols <= 1 ? 0 : X / Double(cols - 1)
            let idx = min(6, Int(frac * 7))
            if frac <= prog {
                let dist = prog - frac
                let edge = max(0, 1 - dist * 5)
                let b = clampD(0.42 + 0.55 * edge + 0.08 * sin(t * 5 + X * 0.6), 0.12, 1)
                return (b, spec[idx])
            }
            return (0.06, grey)
        case .error:
            let flash = sin(t * 6.5) > 0.35 ? 1.0 : 0.22
            let jit = sin(X * 4.2 + Y * 2.7 + Double(Int(t * 11))) * 0.5 + 0.5
            let b = clampD((0.14 + 0.78 * pow(jit, 1.4)) * flash, 0.04, 1)
            return (b, red)
        case .done:
            let cx = Double(cols - 1) / 2, cy = Double(rows - 1) / 2
            let dist = hypot((X - cx) / Double(cols), (Y - cy) / Double(rows)) * 2.2
            let wave = clampD((t * 0.9) - dist * 1.4)
            let b = clampD(wave * (0.5 + 0.35 * sin(t * 1.2 + X * 0.3 + Y * 0.25)) + 0.06, 0.04, 1)
            return (b, green)
        }
    }
}

@inline(__always) private func clampD(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
    max(lo, min(hi, v))
}
