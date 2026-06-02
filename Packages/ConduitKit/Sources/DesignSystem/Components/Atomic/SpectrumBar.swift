import SwiftUI

// MARK: - SpectrumBar — the famicom signature device
// A row of cartridge-era hues that doubles as a live indicator. Four modes:
//   idle    — static decorative rule (header underline)
//   loading — sweeping shine (indeterminate progress)
//   working — sequential per-segment pulse (agent / command active)
//   scan    — bright scan line (connecting)
// Port of `Spec` from the handoff (lib/viz-shared.jsx). Animated via TimelineView(.animation).

public enum SpectrumMode: String, Sendable, Equatable {
    case idle, loading, working, scan
}

public struct SpectrumBar: View {
    public var mode: SpectrumMode
    public var height: CGFloat
    public var gap: CGFloat

    @State private var start = Date()

    private let segs = ConduitTokens.spectrumColors

    public init(mode: SpectrumMode = .idle, height: CGFloat = 6, gap: CGFloat = 1.5) {
        self.mode = mode
        self.height = height
        self.gap = gap
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            GeometryReader { geo in
                let w = geo.size.width
                let n = segs.count
                let segW = (w - gap * CGFloat(n - 1)) / CGFloat(max(1, n))
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(0..<n, id: \.self) { i in
                            Rectangle()
                                .fill(segs[i])
                                .frame(width: segW, height: height)
                                .opacity(mode == .working ? workingOpacity(i, t) : 1)
                        }
                    }
                    if mode == .loading { shine(width: w, t: t) }
                    if mode == .scan { scan(width: w, t: t) }
                }
                .frame(width: w, height: height, alignment: .leading)
                .clipped()
            }
            .frame(height: height)
        }
        .onChange(of: mode) { _, _ in start = Date() }
        .accessibilityHidden(true)
    }

    // working: staggered ease-in-out pulse per segment
    private func workingOpacity(_ i: Int, _ t: Double) -> Double {
        let s = 0.5 + 0.5 * sin(2 * .pi * (t / 1.05 - Double(i) * 0.105))
        return 0.4 + 0.6 * s
    }

    // loading: a soft white highlight sweeping left → right, overlay-blended
    private func shine(width w: CGFloat, t: Double) -> some View {
        let band = w * 0.5
        let travel = w + band
        let p = (t / 1.4).truncatingRemainder(dividingBy: 1)
        let x = CGFloat(p) * travel - band
        return Rectangle()
            .fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.85), location: 0.5),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing))
            .frame(width: band, height: height)
            .offset(x: x)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }

    // scan: a bright blurred bar tracking across
    private func scan(width w: CGFloat, t: Double) -> some View {
        let band = max(8, w * 0.13)
        let p = (t / 1.2).truncatingRemainder(dividingBy: 1)
        let x = CGFloat(p) * (w + band) - band
        return Rectangle()
            .fill(Color.white.opacity(0.9))
            .frame(width: band, height: height)
            .blur(radius: 2)
            .offset(x: x)
            .allowsHitTesting(false)
    }
}
